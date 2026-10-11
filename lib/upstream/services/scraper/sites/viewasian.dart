import 'dart:async';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// ViewAsian (viewasian.co / watchasian) Asian Drama Stream Scraper.
/// Specialized in Korean Dramas (K-Drama), Chinese Dramas (C-Drama),
/// Japanese Dramas (J-Drama), and Asian TV variety shows with multi-server HLS/MP4 streams.
class ViewAsianScraper extends StreamScraper {
  @override
  String get name => 'ViewAsian';

  @override
  String get providerId => 'viewasian';

  @override
  String get providerName => 'ViewAsian';

  static const List<String> _baseUrls = [
    'https://viewasian.co',
    'https://watchasian.sk',
    'https://watchasian.la',
  ];

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9,ko;q=0.8,zh;q=0.7',
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
        final searchUrl = Uri.parse('$base/search.html?keyword=${Uri.encodeComponent(query)}');
        final res = await http.get(searchUrl, headers: _headers).timeout(const Duration(seconds: 4));
        if (res.statusCode != 200) continue;

        final doc = html_parser.parse(res.body);
        final dramaCards = doc.querySelectorAll('ul.list-episode-item li, div.movies-list div.ml-item, div.film_list-wrap a');

        for (final card in dramaCards) {
          final link = card.querySelector('a')?.attributes['href'] ?? card.attributes['href'];
          final cardTitle = card.querySelector('h3, .title, .film-name')?.text.trim() ?? card.text.trim();
          if (link == null || link.isEmpty) continue;

          final dramaUrl = link.startsWith('http') ? link : '$base$link';

          // Target specific episode or primary video page
          String targetUrl = dramaUrl;
          if (episode != null && episode > 0) {
            targetUrl = dramaUrl.replaceAll(RegExp(r'-episode-\d+'), '') + '-episode-$episode.html';
          }

          final epRes = await http.get(Uri.parse(targetUrl), headers: _headers).timeout(const Duration(seconds: 4));
          if (epRes.statusCode != 200) continue;

          final epDoc = html_parser.parse(epRes.body);

          // Extract embedded players and streaming iframes
          final iframes = epDoc.querySelectorAll('iframe, div.play-video iframe, div.watch_player iframe');
          for (final iframe in iframes) {
            final src = iframe.attributes['src'] ?? iframe.attributes['data-src'];
            if (src == null || src.isEmpty) continue;
            final fullSrc = src.startsWith('//') ? 'https:$src' : (src.startsWith('http') ? src : '$base$src');

            if (fullSrc.contains('.m3u8') || fullSrc.contains('.mp4')) {
              yield StreamSource(
                url: fullSrc,
                name: 'ViewAsian [1080p FHD]',
                title: '$cardTitle ${episode != null ? "EP $episode" : ""}\n⚡ Direct HLS Asian Drama Stream [viewasian.co]'.trim(),
                addonName: 'ViewAsian',
                providerName: 'ViewAsian',
                providerId: providerId,
              );
            } else if (fullSrc.contains('streamwish') || fullSrc.contains('vidhide') || fullSrc.contains('filelions') || fullSrc.contains('asianload')) {
              yield StreamSource(
                url: fullSrc,
                name: 'ViewAsian (Multi-Host)',
                title: '$cardTitle ${episode != null ? "EP $episode" : ""}\n☁️ Cloud Mirror Stream [viewasian.co]'.trim(),
                addonName: 'ViewAsian',
                providerName: 'ViewAsian',
                providerId: providerId,
              );
            }
          }

          // Extract direct server download/stream links
          final serverLinks = epDoc.querySelectorAll('li.linkserver, a.linkserver, div.anime_muti_link a');
          for (final srv in serverLinks) {
            final dataVideo = srv.attributes['data-video'] ?? srv.attributes['href'];
            final srvName = srv.text.trim();
            if (dataVideo == null || dataVideo.isEmpty || dataVideo.startsWith('javascript')) continue;

            final fullVideo = dataVideo.startsWith('//') ? 'https:$dataVideo' : dataVideo;
            yield StreamSource(
              url: fullVideo,
              name: 'ViewAsian ($srvName)',
              title: '$cardTitle ${episode != null ? "EP $episode" : ""}\n⚡ Server $srvName [viewasian.co]'.trim(),
              addonName: 'ViewAsian',
              providerName: 'ViewAsian',
              providerId: providerId,
            );
          }
          break; // Found matching drama
        }
        break; // Successfully queried base
      } catch (_) {
        continue;
      }
    }
  }
}
