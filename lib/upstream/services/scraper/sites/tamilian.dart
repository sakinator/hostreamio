import 'dart:async';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// Tamilian (embedojo.net) Stream Scraper for Hostreamio.
/// Inspired by CNCVerse Tamilian Provider.
/// Specializes in South Indian (Tamil / Telugu) dubbed & original cinema.
class TamilianScraper extends StreamScraper {
  @override
  String get name => 'Tamilian';

  @override
  String get providerId => 'tamilian';

  @override
  String get providerName => 'Tamilian';

  static const String _baseUrl = 'https://embedojo.net';

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Referer': 'https://embedojo.net/',
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

    // 1. If IMDb ID is available, attempt direct TMDB embed lookup
    if (imdbId != null && imdbId.isNotEmpty) {
      try {
        final embedUrl = Uri.parse('$_baseUrl/tamil/imdb/$imdbId');
        final res = await http.get(embedUrl, headers: _headers).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final m3u8Match = RegExp(r'https?://[^\s"<>]+?\.m3u8[^\s"<>]*').firstMatch(res.body);
          if (m3u8Match != null) {
            yield StreamSource(
              name: 'Tamilian (1080p FHD)',
              title: '$title\n⚡ 🇮🇳 Tamil Audio / Dubbed HLS Stream [embedojo.net]',
              url: m3u8Match.group(0)!,
              addonName: 'Tamilian',
              providerId: providerId,
              providerName: providerName,
              headers: {
                'Referer': 'https://embedojo.net/',
                'User-Agent': _headers['User-Agent']!,
              },
              behaviorHints: {
                'notWebReady': false,
              },
            );
            return;
          }
        }
      } catch (_) {}
    }

    // 2. Keyword search on embedojo
    try {
      final searchUrl = Uri.parse('$_baseUrl/search?q=${Uri.encodeComponent(cleanTitle)}');
      final res = await http.get(searchUrl, headers: _headers).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final doc = html_parser.parse(res.body);
        final links = doc.querySelectorAll('a[href*="/tamil/"], a[href*="/movie/"], a[href*="/player/"]');

        for (final a in links) {
          final href = a.attributes['href'];
          final linkText = a.text.trim();
          if (href == null || href.isEmpty) continue;

          final fullUrl = href.startsWith('http') ? href : '$_baseUrl$href';
          final epRes = await http.get(Uri.parse(fullUrl), headers: _headers).timeout(const Duration(seconds: 3));
          if (epRes.statusCode != 200) continue;

          final m3u8Match = RegExp(r'https?://[^\s"<>]+?\.m3u8[^\s"<>]*').firstMatch(epRes.body);
          if (m3u8Match != null) {
            yield StreamSource(
              name: 'Tamilian (HD)',
              title: '${linkText.isNotEmpty ? linkText : title}\n⚡ 🇮🇳 Tamil Dubbed Stream [embedojo.net]',
              url: m3u8Match.group(0)!,
              addonName: 'Tamilian',
              providerId: providerId,
              providerName: providerName,
              headers: {
                'Referer': 'https://embedojo.net/',
                'User-Agent': _headers['User-Agent']!,
              },
              behaviorHints: {
                'notWebReady': false,
              },
            );
            break;
          }
        }
      }
    } catch (_) {}
  }
}
