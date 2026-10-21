import 'dart:async';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// M4uHD Dedicated Multi-Server Stream Scraper for PlayTorrioHTTP.
/// Extracts multi-resolution streams for Movies & TV Shows from m4uhd.vip.
class M4uHdScraper extends StreamScraper {
  @override
  String get name => 'PlayTorrioHTTP';

  @override
  String get providerId => 'm4uhd';

  @override
  String get providerName => 'M4uHD';

  static const List<String> _domains = [
    'https://m4uhd.vip',
    'https://m4uhd.tv',
  ];

  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
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

    for (final base in _domains) {
      try {
        final searchUrl = Uri.parse('$base/search/${Uri.encodeComponent(cleanTitle)}.html');
        final res = await http.get(searchUrl, headers: _headers).timeout(const Duration(seconds: 4));
        if (res.statusCode != 200) continue;

        final doc = html_parser.parse(res.body);
        final cards = doc.querySelectorAll('.item, .card-item, a[title*="${cleanTitle.split(' ').first}"]');
        if (cards.isEmpty) continue;

        for (final c in cards.take(2)) {
          final href = c.attributes['href'] ?? c.querySelector('a')?.attributes['href'];
          if (href == null || href.isEmpty) continue;

          final moviePageUrl = href.startsWith('http') ? href : '$base$href';
          final pageRes = await http.get(Uri.parse(moviePageUrl), headers: _headers).timeout(const Duration(seconds: 4));
          if (pageRes.statusCode != 200) continue;

          final pageDoc = html_parser.parse(pageRes.body);
          final iframes = pageDoc.querySelectorAll('iframe[src*="embed"], iframe[src*="stream"], iframe[src*="player"], iframe[data-src]');

          for (final f in iframes) {
            final src = f.attributes['src'] ?? f.attributes['data-src'];
            if (src == null || !src.startsWith('http')) continue;

            final quality = src.contains('1080') ? '1080p' : 'HD';

            yield StreamSource(
              name: 'M4uHD ($quality)',
              title: '🎬 $title • M4uHD Dedicated Server\n⚡ $quality Stream (Direct HLS/MP4)',
              url: src,
              addonName: 'M4uHD',
              providerId: providerId,
              providerName: providerName,
              behaviorHints: const {
                'notWebReady': false,
              },
            );
          }
        }
        break;
      } catch (_) {}
    }
  }
}
