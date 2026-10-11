import 'dart:async';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// ShortDramaScraper: Scrapes vertical micro-dramas (DramaBox, ReelShort, ShortMax, Sereal+ style).
/// Aggregates free web portals and mirror platforms hosting full unlocked short drama episodes.
class ShortDramaScraper extends StreamScraper {
  @override
  String get name => 'ShortDrama';

  @override
  String get providerId => 'shortdrama';

  @override
  String get providerName => 'ShortDrama';

  static const List<String> _baseUrls = [
    'https://dramafren.org',
    'https://shortdramatop.com',
    'https://reelpulse.net',
  ];

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9,zh;q=0.8',
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
        final dramaPosts = doc.querySelectorAll('article.post, div.post-item, div.film-item, div.short-item a');

        for (final post in dramaPosts) {
          final link = post.querySelector('a')?.attributes['href'] ?? post.attributes['href'];
          final postTitle = post.querySelector('h2, h3, .title, a')?.text.trim() ?? post.text.trim();
          if (link == null || link.isEmpty) continue;

          final dramaUrl = link.startsWith('http') ? link : '$base$link';
          final epRes = await http.get(Uri.parse(dramaUrl), headers: _headers).timeout(const Duration(seconds: 4));
          if (epRes.statusCode != 200) continue;

          final epDoc = html_parser.parse(epRes.body);

          // 1. Direct Video / Source Tags
          final videos = epDoc.querySelectorAll('video source, video');
          for (final v in videos) {
            final src = v.attributes['src'];
            if (src != null && src.isNotEmpty && (src.contains('.m3u8') || src.contains('.mp4'))) {
              yield StreamSource(
                url: src.startsWith('http') ? src : '$base$src',
                name: 'ShortDrama [Direct HD]',
                title: '$postTitle ${episode != null ? "EP $episode" : ""}\n⚡ Unlocked Vertical Micro-Drama Stream [shortdramatop.com]'.trim(),
                addonName: 'ShortDrama',
                providerName: 'ShortDrama',
                providerId: providerId,
              );
            }
          }

          // 2. Embedded Video Players / Cloud Iframes
          final iframes = epDoc.querySelectorAll('iframe');
          for (final iframe in iframes) {
            final src = iframe.attributes['src'] ?? iframe.attributes['data-src'];
            if (src == null || src.isEmpty) continue;
            final fullSrc = src.startsWith('//') ? 'https:$src' : (src.startsWith('http') ? src : '$base$src');

            if (fullSrc.contains('.m3u8') || fullSrc.contains('.mp4') || fullSrc.contains('embed')) {
              yield StreamSource(
                url: fullSrc,
                name: 'ShortDrama [Player]',
                title: '$postTitle ${episode != null ? "EP $episode" : ""}\n📱 Vertical Web Player [shortdramatop.com]'.trim(),
                addonName: 'ShortDrama',
                providerName: 'ShortDrama',
                providerId: providerId,
              );
            }
          }
          break; // Stop at first matched drama series
        }
        break; // Successfully queried base
      } catch (_) {
        continue;
      }
    }
  }
}
