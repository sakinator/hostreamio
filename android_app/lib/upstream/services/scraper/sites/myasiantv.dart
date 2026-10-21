import 'dart:async';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// MyAsianTV Asian Drama Scraper for PlayTorrioHTTP.
/// Extracts high-efficiency streams for Korean, Chinese, and Japanese Dramas.
class MyAsianTvScraper extends StreamScraper {
  @override
  String get name => 'PlayTorrioHTTP';

  @override
  String get providerId => 'myasiantv';

  @override
  String get providerName => 'MyAsianTV';

  static const List<String> _domains = [
    'https://myasiantv.com.bz',
    'https://myasiantv.cx',
    'https://myasiantv.ac',
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
    final epNum = episode ?? 1;
    final cleanTitle = title.replaceAll(RegExp(r'[^\w\s]'), ' ').trim();

    for (final base in _domains) {
      try {
        final searchUrl = Uri.parse('$base/search.html?key=${Uri.encodeComponent(cleanTitle)}');
        final res = await http.get(searchUrl, headers: _headers).timeout(const Duration(seconds: 4));
        if (res.statusCode != 200) continue;

        final doc = html_parser.parse(res.body);
        final dramaLinks = doc.querySelectorAll('.item a, .list-drama a, a[title*="${cleanTitle.split(' ').first}"]');
        if (dramaLinks.isEmpty) continue;

        for (final a in dramaLinks.take(2)) {
          final href = a.attributes['href'];
          if (href == null || href.isEmpty) continue;

          final dramaPageUrl = href.startsWith('http') ? href : '$base$href';
          final epUrl = dramaPageUrl.contains('episode')
              ? dramaPageUrl
              : '$dramaPageUrl/episode-$epNum.html';

          final epRes = await http.get(Uri.parse(epUrl), headers: _headers).timeout(const Duration(seconds: 4));
          if (epRes.statusCode != 200) continue;

          final epDoc = html_parser.parse(epRes.body);
          final iframes = epDoc.querySelectorAll('iframe[src*="embed"], iframe[src*="stream"], iframe[src*="player"], iframe[data-src]');

          for (final f in iframes) {
            final src = f.attributes['src'] ?? f.attributes['data-src'];
            if (src == null || !src.startsWith('http')) continue;

            yield StreamSource(
              name: 'MyAsianTV [Ep $epNum]',
              title: '🎎 $title - Ep $epNum\n⚡ MyAsianTV Asian Drama Direct Stream',
              url: src,
              addonName: 'MyAsianTV',
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
