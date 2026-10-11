import 'dart:async';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// MLSBD (mlsbd.co) Bangladeshi & South Asian Stream/Download Scraper.
/// Extracts direct high-speed cloud mirrors: HubCloud, DriveBot, GDFlix, Gofile, and PixelDrain.
class MLSBDScraper extends StreamScraper {
  @override
  String get name => 'MLSBD';

  @override
  String get providerId => 'mlsbd';

  @override
  String get providerName => 'MLSBD';

  static const List<String> _baseUrls = [
    'https://mlsbd.co',
    'https://mlsbd.shop',
  ];

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9,bn;q=0.8,hi;q=0.7',
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
    final query = cleanTitle.split(' ').take(3).join(' ');

    for (final base in _baseUrls) {
      try {
        final searchUrl = Uri.parse('$base/?s=${Uri.encodeComponent(query)}');
        final res = await http.get(searchUrl, headers: _headers).timeout(const Duration(seconds: 4));
        if (res.statusCode != 200) continue;

        final doc = html_parser.parse(res.body);
        final postLinks = doc.querySelectorAll('a[href*="/movie/"], a[href*="/series/"], div.post-thumb a, h2.entry-title a');

        for (final linkEl in postLinks) {
          final href = linkEl.attributes['href'];
          final postTitle = linkEl.text.trim();
          if (href == null || href.isEmpty || !href.startsWith('http')) continue;

          final detailRes = await http.get(Uri.parse(href), headers: _headers).timeout(const Duration(seconds: 4));
          if (detailRes.statusCode != 200) continue;

          final detailDoc = html_parser.parse(detailRes.body);
          final cloudLinks = detailDoc.querySelectorAll('a[href*="hubcloud"], a[href*="gofile"], a[href*="pixeldrain"], a[href*="drivebot"], a[href*="gdflix"]');

          for (final a in cloudLinks) {
            final targetLink = a.attributes['href'];
            final linkText = a.text.trim();
            if (targetLink == null || targetLink.isEmpty) continue;

            final quality = linkText.contains('4K') || linkText.contains('2160')
                ? '4K UHD'
                : (linkText.contains('1080') ? '1080p FHD' : '720p HD');

            yield StreamSource(
              url: targetLink,
              name: 'MLSBD ($quality)',
              title: '${postTitle.isNotEmpty ? postTitle : title}\n☁️ $linkText Cloud Stream [mlsbd.co]',
              addonName: 'MLSBD',
              providerName: 'MLSBD',
              providerId: providerId,
            );
          }
          break; // Stop after first matched film/series
        }
        break; // Successfully queried base
      } catch (_) {
        continue;
      }
    }
  }
}
