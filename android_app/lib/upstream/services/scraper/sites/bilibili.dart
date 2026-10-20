import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'dart:convert';
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// BilibiliScraper: Scrapes Asian animation, Chinese Donghua, and anime series
/// from Bilibili TV international platform (bilibili.tv / api.bilibili.tv).
class BilibiliScraper extends StreamScraper {
  @override
  String get name => 'Bilibili TV';

  @override
  String get providerId => 'bilibili';

  @override
  String get providerName => 'Bilibili TV';

  static const List<String> _baseUrls = [
    'https://api.bilibili.tv',
    'https://www.bilibili.tv',
  ];

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/html, */*',
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
        final searchUrl = Uri.parse('$base/search?keyword=${Uri.encodeComponent(query)}');
        final res = await http.get(searchUrl, headers: _headers).timeout(const Duration(seconds: 4));
        if (res.statusCode != 200) continue;

        if (res.body.startsWith('{')) {
          final json = jsonDecode(res.body);
          final items = json['data']?['items'] as List? ?? [];
          for (final it in items) {
            final playUrl = it['play_url']?.toString() ?? it['url']?.toString();
            final itemTitle = it['title']?.toString() ?? title;
            if (playUrl != null && playUrl.isNotEmpty) {
              yield StreamSource(
                url: playUrl,
                name: 'Bilibili TV [1080p Donghua]',
                title: '$itemTitle ${episode != null ? "EP $episode" : ""}\n⛩️ Asian Donghua & Anime Official Stream [bilibili.tv]',
                addonName: 'Bilibili TV',
                providerName: 'Bilibili TV',
                providerId: providerId,
              );
            }
          }
        } else {
          final doc = html_parser.parse(res.body);
          final links = doc.querySelectorAll('a[href*="/play/"], a[href*="/video/"]');
          for (final a in links) {
            final href = a.attributes['href'];
            final linkTitle = a.text.trim();
            if (href == null || href.isEmpty) continue;
            final fullLink = href.startsWith('http') ? href : '$base$href';

            yield StreamSource(
              url: fullLink,
              name: 'Bilibili TV [1080p]',
              title: '${linkTitle.isNotEmpty ? linkTitle : title}\n⛩️ Bilibili TV Stream [bilibili.tv]',
              addonName: 'Bilibili TV',
              providerName: 'Bilibili TV',
              providerId: providerId,
            );
          }
        }
        break;
      } catch (_) {
        continue;
      }
    }
  }
}
