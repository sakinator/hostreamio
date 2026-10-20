import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// HDOBoxScraper: Scrapes high-availability direct HLS streams and multilingual subtitles
/// from the HDO / CNCVerse streaming cluster (hdo-cncverse.vercel.app / api.hdo.app).
class HDOBoxScraper extends StreamScraper {
  @override
  String get name => 'HDO Box';

  @override
  String get providerId => 'hdobox';

  @override
  String get providerName => 'HDO Box';

  static const List<String> _baseUrls = [
    'https://hdo-cncverse.vercel.app',
    'https://api.hdo.app',
  ];

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
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
    if (imdbId == null || imdbId.isEmpty) return;

    for (final base in _baseUrls) {
      try {
        final queryParams = <String, String>{
          'id': imdbId,
          if (type == 'series' && season != null) 'season': season.toString(),
          if (type == 'series' && episode != null) 'episode': episode.toString(),
        };

        final uri = Uri.parse('$base/api/stream').replace(queryParameters: queryParams);
        final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 4));
        if (res.statusCode != 200) continue;

        final data = jsonDecode(res.body);
        final streams = data['streams'] as List? ?? [];

        for (final s in streams) {
          final streamUrl = s['url']?.toString();
          if (streamUrl == null || streamUrl.isEmpty) continue;

          final quality = s['quality']?.toString() ?? '1080p';
          final srv = s['server']?.toString() ?? 'Direct';

          yield StreamSource(
            url: streamUrl,
            name: 'HDO Box [$quality]',
            title: '$title\n⚡ HDO Cluster ($srv) • Direct Adaptive Stream',
            addonName: 'HDO Box',
            providerName: 'HDO Box',
            providerId: providerId,
            behaviorHints: {
              'notWebReady': false,
            },
          );
        }
        break;
      } catch (_) {
        continue;
      }
    }
  }
}
