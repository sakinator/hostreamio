import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// KickAssAnime Non-Torrent Stream Scraper for PlayTorrioHTTP.
/// Extracts high-bitrate 1080p, 720p, and multi-sub anime streams.
class KickAssAnimeScraper extends StreamScraper {
  @override
  String get name => 'PlayTorrioHTTP';

  @override
  String get providerId => 'kickassanime';

  @override
  String get providerName => 'KickAssAnime';

  static const List<String> _domains = [
    'https://kaa.lt',
    'https://kickassanime.am',
    'https://kickassanime.mx',
  ];

  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
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
        final searchUrl = Uri.parse('$base/api/anime/search?query=${Uri.encodeComponent(cleanTitle)}');
        final res = await http.get(searchUrl, headers: _headers).timeout(const Duration(seconds: 4));
        if (res.statusCode != 200) continue;

        final data = jsonDecode(res.body);
        final list = (data is List)
            ? data
            : (data is Map && data['result'] is List)
                ? data['result'] as List
                : [];

        if (list.isEmpty) continue;

        for (final item in list.take(2)) {
          if (item is! Map) continue;
          final slug = item['slug']?.toString() ?? item['id']?.toString();
          if (slug == null || slug.isEmpty) continue;

          final epUrl = Uri.parse('$base/api/anime/$slug/episode/$epNum');
          final epRes = await http.get(epUrl, headers: _headers).timeout(const Duration(seconds: 4));
          if (epRes.statusCode != 200) continue;

          final epData = jsonDecode(epRes.body);
          if (epData is! Map) continue;

          final servers = epData['servers'] as List? ?? epData['streams'] as List? ?? [];
          for (final s in servers) {
            if (s is! Map) continue;
            final streamUrl = s['url']?.toString() ?? s['src']?.toString();
            if (streamUrl == null || !streamUrl.startsWith('http')) continue;

            final serverName = s['name']?.toString() ?? 'KAA Cloud';
            final quality = s['quality']?.toString() ?? '1080p';

            yield StreamSource(
              name: 'KickAssAnime ($quality)',
              title: '⛩️ $title - Ep $epNum • $serverName\n⚡ $quality KickAssAnime Direct Stream',
              url: streamUrl,
              addonName: 'KickAssAnime',
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
