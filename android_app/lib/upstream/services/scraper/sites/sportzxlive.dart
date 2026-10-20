import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// SportzXLiveScraper: Scrapes live sports streams (Cricket, Football, F1, Tennis)
/// and live event broadcasts from SportzX & Cricify networks (sportzx.live / fifabd.site).
class SportzXLiveScraper extends StreamScraper {
  @override
  String get name => 'SportzX Live';

  @override
  String get providerId => 'sportzxlive';

  @override
  String get providerName => 'SportzX Live';

  static const List<String> _baseUrls = [
    'https://sportzx.live',
    'https://fifabd.site',
  ];

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
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
    final query = cleanTitle.split(' ').take(3).join(' ');

    for (final base in _baseUrls) {
      try {
        final searchUrl = Uri.parse('$base/?s=${Uri.encodeComponent(query)}');
        final res = await http.get(searchUrl, headers: _headers).timeout(const Duration(seconds: 4));
        if (res.statusCode != 200) continue;

        final doc = html_parser.parse(res.body);
        final matchCards = doc.querySelectorAll('article.post, div.match-item, div.live-card a, h2 a');

        for (final card in matchCards) {
          final link = card.querySelector('a')?.attributes['href'] ?? card.attributes['href'];
          final cardTitle = card.text.trim();
          if (link == null || link.isEmpty) continue;

          final fullLink = link.startsWith('http') ? link : '$base$link';
          final epRes = await http.get(Uri.parse(fullLink), headers: _headers).timeout(const Duration(seconds: 4));
          if (epRes.statusCode != 200) continue;

          final epDoc = html_parser.parse(epRes.body);

          // Direct HLS / M3U8 players
          final iframes = epDoc.querySelectorAll('iframe');
          for (final iframe in iframes) {
            final src = iframe.attributes['src'] ?? iframe.attributes['data-src'];
            if (src == null || src.isEmpty) continue;
            final fullSrc = src.startsWith('//') ? 'https:$src' : (src.startsWith('http') ? src : '$base$src');

            if (fullSrc.contains('.m3u8') || fullSrc.contains('live') || fullSrc.contains('stream')) {
              yield StreamSource(
                url: fullSrc,
                name: 'SportzX [Live Sports]',
                title: '${cardTitle.isNotEmpty ? cardTitle : title}\n🏏 Live Sports & Cricket Match Stream [sportzx.live]',
                addonName: 'SportzX Live',
                providerName: 'SportzX Live',
                providerId: providerId,
              );
            }
          }

          final videos = epDoc.querySelectorAll('video source, video');
          for (final v in videos) {
            final src = v.attributes['src'];
            if (src != null && src.isNotEmpty && src.contains('.m3u8')) {
              yield StreamSource(
                url: src.startsWith('http') ? src : '$base$src',
                name: 'SportzX [Direct HLS]',
                title: '${cardTitle.isNotEmpty ? cardTitle : title}\n⚡ Direct Live Event Stream [sportzx.live]',
                addonName: 'SportzX Live',
                providerName: 'SportzX Live',
                providerId: providerId,
              );
            }
          }
          break;
        }
        break;
      } catch (_) {
        continue;
      }
    }
  }
}
