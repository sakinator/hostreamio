import 'dart:async';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import '../stream_scraper.dart';
import '../../../models/stream/stream_model.dart';

/// CoolMovies (coolmovies.to / coolmoviez) Stream Scraper for Hostreamio.
/// Scrapes Bollywood, Hollywood Hindi Dubbed, South Indian, and Punjabi movies & series.
class CoolMoviesScraper extends StreamScraper {
  @override
  String get name => 'CoolMovies';

  @override
  String get providerId => 'coolmovies';

  @override
  String get providerName => 'CoolMovies';

  static const List<String> _baseUrls = [
    'https://coolmovies.to',
    'https://coolmoviez.shop',
    'https://coolmoviez.win',
    'https://coolmoviez.wiki',
  ];

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept':
        'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9,hi;q=0.8',
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
        final searchUrl = Uri.parse('$base/search?q=${Uri.encodeComponent(query)}');
        final res = await http.get(searchUrl, headers: _headers).timeout(const Duration(seconds: 4));
        if (res.statusCode != 200) continue;

        final doc = html_parser.parse(res.body);
        final movieCards = doc.querySelectorAll('div.movie-card, div.flw-item, div.film_list-wrap a, article.post, div.ml-item a');

        for (final card in movieCards) {
          final link = card.attributes['href'] ?? card.querySelector('a')?.attributes['href'];
          final cardTitle = card.querySelector('.film-name, .movie-title, h2, h3, a')?.text.trim() ?? card.text.trim();
          if (link == null || link.isEmpty) continue;

          final fullLink = link.startsWith('http') ? link : '$base$link';
          final firstWord = cleanTitle.split(' ').first.toLowerCase();
          if (!cardTitle.toLowerCase().contains(firstWord)) continue;

          // Fetch post detail page
          final postRes = await http.get(Uri.parse(fullLink), headers: _headers).timeout(const Duration(seconds: 4));
          if (postRes.statusCode != 200) continue;

          final postDoc = html_parser.parse(postRes.body);

          // Find direct download/stream links (hubcloud, pixeldrain, fastdl, dood, streamtape, mp4/mkv direct)
          final streamButtons = postDoc.querySelectorAll(
            'a[href*="hubcloud"], a[href*="pixeldrain"], a[href*="fastdl"], a[href*="vcloud"], a[href*="dood"], a[href*="streamtape"], a[href*=".mp4"], a[href*=".mkv"]'
          );

          for (final btn in streamButtons) {
            final targetUrl = btn.attributes['href'];
            if (targetUrl == null || targetUrl.isEmpty || !targetUrl.startsWith('http')) continue;

            final btnText = btn.parent?.text.trim() ?? btn.text.trim();
            final quality = btnText.contains('2160p') || btnText.contains('4K')
                ? '4K UHD'
                : btnText.contains('1080p')
                    ? '1080p FHD'
                    : btnText.contains('720p')
                        ? '720p HD'
                        : btnText.contains('480p')
                            ? '480p SD'
                            : 'HD';

            final isHindi = btnText.toLowerCase().contains('hindi') ||
                            btnText.toLowerCase().contains('dual') ||
                            cardTitle.toLowerCase().contains('hindi');

            // Clean size if mentioned in button text
            final sizeMatch = RegExp(r'(\d+(?:\.\d+)?\s*(?:GB|MB))', caseSensitive: false).firstMatch(btnText);
            final fileSize = sizeMatch?.group(1);

            final sizeStr = fileSize != null ? '💾 $fileSize • ' : '';

            yield StreamSource(
              name: 'CoolMovies ($quality)',
              title: '$cardTitle\n⚡ ${isHindi ? "🇮🇳 Hindi • " : ""}$sizeStr$quality Direct Cloud Stream [coolmovies.to]',
              url: targetUrl,
              addonName: 'CoolMovies',
              providerId: providerId,
              providerName: providerName,
              behaviorHints: {
                'notWebReady': false,
              },
            );
          }
        }
        break; // Successfully scraped this mirror
      } catch (_) {}
    }
  }
}
