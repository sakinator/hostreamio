import 'dart:async';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// TamilUltra (tamilultra.co.uk) Indian Live TV & Entertainment Scraper.
/// Specialized in South Indian (Tamil, Telugu, Malayalam, Kannada) and Hindi TV channels & movies.
class TamilUltraScraper extends StreamScraper {
  @override
  String get name => 'TamilUltra';

  @override
  String get providerId => 'tamilultra';

  @override
  String get providerName => 'TamilUltra';

  static const List<String> _baseUrls = [
    'https://tamilultra.co.uk',
    'https://tamilultra.team',
  ];

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9,ta;q=0.8,hi;q=0.7',
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
        final postCards = doc.querySelectorAll('article.post, div.post-item, div.entry-title a, h2 a');

        for (final card in postCards) {
          final link = card.querySelector('a')?.attributes['href'] ?? card.attributes['href'];
          final postTitle = card.text.trim();
          if (link == null || link.isEmpty) continue;

          final fullLink = link.startsWith('http') ? link : '$base$link';
          final epRes = await http.get(Uri.parse(fullLink), headers: _headers).timeout(const Duration(seconds: 4));
          if (epRes.statusCode != 200) continue;

          final epDoc = html_parser.parse(epRes.body);

          // 1. Direct HLS or MP4 stream links
          final iframes = epDoc.querySelectorAll('iframe');
          for (final iframe in iframes) {
            final src = iframe.attributes['src'] ?? iframe.attributes['data-src'];
            if (src == null || src.isEmpty) continue;
            final fullSrc = src.startsWith('//') ? 'https:$src' : (src.startsWith('http') ? src : '$base$src');

            if (fullSrc.contains('.m3u8') || fullSrc.contains('.mp4')) {
              yield StreamSource(
                url: fullSrc,
                name: 'TamilUltra [1080p HLS]',
                title: '${postTitle.isNotEmpty ? postTitle : title}\n⚡ High-Speed Direct HLS Stream [tamilultra.co.uk]',
                addonName: 'TamilUltra',
                providerName: 'TamilUltra',
                providerId: providerId,
              );
            } else if (fullSrc.contains('player') || fullSrc.contains('embed')) {
              yield StreamSource(
                url: fullSrc,
                name: 'TamilUltra [Player]',
                title: '${postTitle.isNotEmpty ? postTitle : title}\n🌴 South Indian Web Player [tamilultra.co.uk]',
                addonName: 'TamilUltra',
                providerName: 'TamilUltra',
                providerId: providerId,
              );
            }
          }

          // 2. Direct Video Sources
          final videos = epDoc.querySelectorAll('video source, video');
          for (final v in videos) {
            final src = v.attributes['src'];
            if (src != null && src.isNotEmpty && (src.contains('.m3u8') || src.contains('.mp4'))) {
              yield StreamSource(
                url: src.startsWith('http') ? src : '$base$src',
                name: 'TamilUltra [Direct HD]',
                title: '${postTitle.isNotEmpty ? postTitle : title}\n⚡ Direct Video Stream [tamilultra.co.uk]',
                addonName: 'TamilUltra',
                providerName: 'TamilUltra',
                providerId: providerId,
              );
            }
          }
          break; // Stop after first match
        }
        break; // Successfully queried base
      } catch (_) {
        continue;
      }
    }
  }
}
