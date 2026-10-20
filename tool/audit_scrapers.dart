import 'dart:async';
import '../lib/scraper_registry.dart';
import '../lib/upstream/models/stream/stream_model.dart';

/// Automated Scraper Health Auditor for Hostreamio.
/// Tests all registered scrapers against sample titles (Movies & Series)
/// and provides an instant diagnostic report on response times, working status, and error states.
void main(List<String> args) async {
  print('\x1B[36m===============================================================\x1B[0m');
  print('\x1B[35m 🩺 Hostreamio Automated Scraper Health Auditor\x1B[0m');
  print('\x1B[36m===============================================================\x1B[0m');

  final scrapers = ScraperRegistry.getAllScrapers();
  print('Discovered ${scrapers.length} registered scrapers to audit.\n');

  final movieTest = {'title': 'Avatar', 'year': 2009, 'type': 'movie', 'imdbId': 'tt0499549'};

  int working = 0;
  int empty = 0;
  int failed = 0;

  for (int i = 0; i < scrapers.length; i++) {
    final s = scrapers[i];
    final progress = '[${i + 1}/${scrapers.length}]';
    final name = s.providerName.padRight(22);
    final sw = Stopwatch()..start();

    try {
      final streams = <StreamSource>[];
      final completer = Completer<void>();

      // Test with movie first
      final sub = s.scrapeStream(
        type: movieTest['type'] as String,
        title: movieTest['title'] as String,
        year: movieTest['year'] as int,
        imdbId: movieTest['imdbId'] as String,
      ).listen(
        (src) {
          streams.add(src);
        },
        onError: (_) {},
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: false,
      );

      await completer.future.timeout(const Duration(seconds: 4), onTimeout: () {
        sub.cancel();
      });
      sw.stop();

      if (streams.isNotEmpty) {
        working++;
        print('$progress \x1B[32m✔ $name\x1B[0m (${sw.elapsedMilliseconds}ms) -> \x1B[32m${streams.length} stream(s)\x1B[0m [${streams.first.quality ?? 'HD'}]');
      } else {
        empty++;
        print('$progress \x1B[33m○ $name\x1B[0m (${sw.elapsedMilliseconds}ms) -> 0 streams (query mismatch or offline)');
      }
    } catch (e) {
      sw.stop();
      failed++;
      print('$progress \x1B[31m✖ $name\x1B[0m (${sw.elapsedMilliseconds}ms) -> Error: $e');
    }
  }

  print('\n\x1B[36m===============================================================\x1B[0m');
  print('\x1B[32m✔ Working: $working\x1B[0m | \x1B[33m○ No matches/Empty: $empty\x1B[0m | \x1B[31m✖ Failed: $failed\x1B[0m | Total: ${scrapers.length}');
  print('\x1B[36m===============================================================\x1B[0m');
}
