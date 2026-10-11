import 'dart:async';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// Einthusan (einthusan.tv) Stream Scraper for Hostreamio.
/// Premier legal & high-definition Indian multi-language cinema provider:
/// Hindi, Tamil, Telugu, Malayalam, Kannada, Bengali, Marathi, and Punjabi.
class EinthusanScraper extends StreamScraper {
  @override
  String get name => 'Einthusan';

  @override
  String get providerId => 'einthusan';

  @override
  String get providerName => 'Einthusan';

  static const List<String> _baseUrls = [
    'https://einthusan.tv',
    'https://einthusan.ca',
  ];

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9,hi;q=0.8,ta;q=0.7,te;q=0.7',
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

    // Test across Hindi, Tamil, and Telugu sections
    final sections = ['hindi', 'tamil', 'telugu', 'malayalam'];

    for (final base in _baseUrls) {
      for (final sec in sections) {
        try {
          final searchUrl = Uri.parse('$base/movie/results/?lang=$sec&query=${Uri.encodeComponent(query)}');
          final res = await http.get(searchUrl, headers: _headers).timeout(const Duration(seconds: 4));
          if (res.statusCode != 200) continue;

          final doc = html_parser.parse(res.body);
          final movieCards = doc.querySelectorAll('ul#UIMovieSummary li, div.block1, div.info');

          for (final card in movieCards) {
            final link = card.querySelector('a.title, a')?.attributes['href'];
            final cardTitle = card.querySelector('a.title, h3, h2')?.text.trim() ?? card.text.trim();
            if (link == null || link.isEmpty) continue;

            final movieUrl = link.startsWith('http') ? link : '$base$link';
            final watchRes = await http.get(Uri.parse(movieUrl), headers: _headers).timeout(const Duration(seconds: 4));
            if (watchRes.statusCode != 200) continue;

            final watchDoc = html_parser.parse(watchRes.body);

            // Extract video stream or player JSON attributes
            final playerDiv = watchDoc.querySelector('div#UIVideoPlayer, div[data-mp4], div[data-hls]');
            final hlsUrl = playerDiv?.attributes['data-hls'];
            final mp4Url = playerDiv?.attributes['data-mp4'];

            if (hlsUrl != null && hlsUrl.isNotEmpty) {
              yield StreamSource(
                url: hlsUrl.startsWith('http') ? hlsUrl : '$base$hlsUrl',
                name: 'Einthusan (1080p)',
                title: '$cardTitle ($sec)\n⚡ 1080p High-Bitrate HLS Stream [einthusan.tv]',
                addonName: 'Einthusan',
                providerName: 'Einthusan',
                providerId: providerId,
              );
            }

            if (mp4Url != null && mp4Url.isNotEmpty) {
              yield StreamSource(
                url: mp4Url.startsWith('http') ? mp4Url : '$base$mp4Url',
                name: 'Einthusan (MP4)',
                title: '$cardTitle ($sec)\n⚡ Direct High-Def MP4 Stream [einthusan.tv]',
                addonName: 'Einthusan',
                providerName: 'Einthusan',
                providerId: providerId,
              );
            }

            // Extract direct video tag if present
            final videoTag = watchDoc.querySelector('video source, video');
            final vSrc = videoTag?.attributes['src'];
            if (vSrc != null && vSrc.isNotEmpty) {
              yield StreamSource(
                url: vSrc.startsWith('http') ? vSrc : '$base$vSrc',
                name: 'Einthusan (Direct)',
                title: '$cardTitle ($sec)\n⚡ Original High-Def Stream [einthusan.tv]',
                addonName: 'Einthusan',
                providerName: 'Einthusan',
                providerId: providerId,
              );
            }
            break; // Found matching movie in section
          }
        } catch (_) {
          continue;
        }
      }
    }
  }
}
