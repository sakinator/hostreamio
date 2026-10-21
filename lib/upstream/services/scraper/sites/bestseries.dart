import 'dart:async';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// BestSeries (bstsrs.in / topsrs.day) Dedicated TV Series Scraper for PlayTorrioHTTP.
/// Extracts high-speed direct episode streams for TV series.
class BestSeriesScraper extends StreamScraper {
  @override
  String get name => 'PlayTorrioHTTP';

  @override
  String get providerId => 'bestseries';

  @override
  String get providerName => 'BestSeries';

  static const List<String> _domains = [
    'https://bstsrs.in',
    'https://topsrs.day',
    'https://srstop.link',
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
    if (type == 'movie') return;
    final sNum = season ?? 1;
    final epNum = episode ?? 1;
    final cleanTitle = title.replaceAll(RegExp(r'[^\w\s]'), ' ').trim();

    for (final base in _domains) {
      try {
        final searchUrl = Uri.parse('$base/search?q=${Uri.encodeComponent(cleanTitle)}');
        final res = await http.get(searchUrl, headers: _headers).timeout(const Duration(seconds: 4));
        if (res.statusCode != 200) continue;

        final doc = html_parser.parse(res.body);
        final results = doc.querySelectorAll('.item-film a, .search-result a');
        if (results.isEmpty) continue;

        for (final item in results.take(2)) {
          final href = item.attributes['href'];
          if (href == null || href.isEmpty) continue;

          final showUrl = href.startsWith('http') ? href : '$base$href';
          final epPageUrl = '$showUrl/season-$sNum-episode-$epNum';

          final epRes = await http.get(Uri.parse(epPageUrl), headers: _headers).timeout(const Duration(seconds: 4));
          if (epRes.statusCode != 200) continue;

          final epDoc = html_parser.parse(epRes.body);
          final players = epDoc.querySelectorAll('iframe[src*="stream"], iframe[src*="embed"], iframe[src*="player"], a[data-src]');

          for (final p in players) {
            final src = p.attributes['src'] ?? p.attributes['data-src'];
            if (src == null || !src.startsWith('http')) continue;

            yield StreamSource(
              name: 'BestSeries [S${sNum}E$epNum]',
              title: '📺 $title • S${sNum}E$epNum\n⚡ BestSeries Fast Host Stream',
              url: src,
              addonName: 'BestSeries',
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
