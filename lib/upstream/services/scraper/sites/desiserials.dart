import 'dart:async';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// DesiSerials (desi-serials.to) Stream Scraper for Hostreamio.
/// Scrapes daily episodes of Indian TV Serials & Reality Shows
/// (Star Plus, Zee TV, Sony TV, Colors TV, Star Bharat, SAB TV).
/// Extracts high-speed direct HLS (video.m3u8) streams via tvlogy.
class DesiSerialsScraper extends StreamScraper {
  @override
  String get name => 'DesiSerials';

  @override
  String get providerId => 'desiserials';

  @override
  String get providerName => 'DesiSerials';

  static const String _baseUrl = 'https://www.desi-serials.to';

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9,hi;q=0.8',
  };

  @override
  Stream<StreamSource> scrapeStream({
    required String type,
    required String title,
    int? year,
    int? season,
    int? episode,
    String? imdbId,
  }) async* {
    final cleanTitle = title.replaceAll(RegExp(r'[^\w\s]'), ' ').trim();
    final query = cleanTitle.split(' ').take(2).join(' ');

    try {
      final searchUrl = Uri.parse('$_baseUrl/?s=${Uri.encodeComponent(query)}');
      final res = await http.get(searchUrl, headers: _headers).timeout(const Duration(seconds: 4));
      if (res.statusCode != 200) return;

      final doc = html_parser.parse(res.body);
      final postElements = doc.querySelectorAll('div.post-item, div.porto-post-title, article.post');

      final seenLinks = <String>{};

      for (final el in postElements) {
        final aTag = el.querySelector('h3.porto-post-title a, a[href*="/6"]');
        final postTitle = aTag?.text.trim() ?? el.text.trim();
        final postUrl = aTag?.attributes['href'] ?? el.querySelector('a')?.attributes['href'];

        if (postUrl == null || postUrl.isEmpty || !seenLinks.add(postUrl)) continue;

        final firstWord = cleanTitle.split(' ').first.toLowerCase();
        if (!postTitle.toLowerCase().contains(firstWord)) continue;

        // Fetch episode page
        final epRes = await http.get(Uri.parse(postUrl), headers: _headers).timeout(const Duration(seconds: 4));
        if (epRes.statusCode != 200) continue;

        final epDoc = html_parser.parse(epRes.body);

        // Find tvarticles or tvlogy video links
        final videoLinks = epDoc.querySelectorAll('a[href*="tvarticles.org"], a[href*="tvlogy.to"], iframe[src*="tvlogy.to"]');

        for (final vEl in videoLinks) {
          final targetUrl = vEl.attributes['href'] ?? vEl.attributes['src'];
          if (targetUrl == null || targetUrl.isEmpty) continue;

          String? plyrUrl;
          if (targetUrl.contains('tvarticles.org')) {
            // Fetch tvarticles page to extract flow.tvlogy iframe
            try {
              final artRes = await http.get(Uri.parse(targetUrl), headers: _headers).timeout(const Duration(seconds: 3));
              if (artRes.statusCode == 200) {
                final match = RegExp(r'src=[\x27"](https?://flow\.tvlogy\.to/plyr/[^\x27"]+)[\x27"]', caseSensitive: false).firstMatch(artRes.body);
                plyrUrl = match?.group(1);
              }
            } catch (_) {}
          } else if (targetUrl.contains('flow.tvlogy.to/plyr/')) {
            plyrUrl = targetUrl;
          }

          if (plyrUrl == null || plyrUrl.isEmpty) continue;

          // Fetch flow.tvlogy page with Referer header to extract direct .m3u8 source
          try {
            final plyrHeaders = {
              ..._headers,
              'Referer': 'https://tvarticles.org/',
            };
            final plyrRes = await http.get(Uri.parse(plyrUrl), headers: plyrHeaders).timeout(const Duration(seconds: 3));
            if (plyrRes.statusCode != 200) continue;

            final m3u8Match = RegExp(r'sources:\s*\[\{"src":"([^"]+)"', caseSensitive: false).firstMatch(plyrRes.body);
            final m3u8Url = m3u8Match?.group(1);

            if (m3u8Url != null && m3u8Url.startsWith('http')) {
              yield StreamSource(
                name: 'DesiSerials (720p HD)',
                title: '$postTitle\n⚡ 🇮🇳 Daily Episode HLS Stream [desi-serials.to]',
                url: m3u8Url,
                addonName: 'DesiSerials',
                providerId: providerId,
                providerName: providerName,
                headers: {
                  'Referer': 'https://flow.tvlogy.to/',
                  'User-Agent': _headers['User-Agent']!,
                },
                behaviorHints: {
                  'notWebReady': false,
                  'proxyHeaders': {
                    'request': {
                      'Referer': 'https://flow.tvlogy.to/',
                      'User-Agent': _headers['User-Agent']!,
                    },
                  },
                },
              );
              break; // Yielded working player stream
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
