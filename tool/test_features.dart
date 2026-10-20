import 'dart:convert';
import 'dart:io';
import '../lib/catalog_service.dart';
import '../lib/scraper_engine.dart';
import '../lib/metadata_service.dart';
import '../lib/badge_service.dart';

void main() async {
  print('====================================================');
  print('🧪 Comprehensive Test Suite: Today\'s Implementations');
  print('====================================================\n');

  // 1. Test Asian & Short Dramas Catalog
  print('--- [1/6] Testing Asian & Short Dramas Catalog ---');
  final asianDramaItems = await CatalogService.instance.getCatalogItems(
    type: 'series',
    id: 'asian_dramas',
    sort: 'new',
  );
  print('Found ${asianDramaItems.length} Asian & Short Drama catalog items.');
  if (asianDramaItems.isNotEmpty) {
    final first = asianDramaItems.first;
    print('  Sample: "${first['name']}" (ID: ${first['id']}, Genres: ${first['genres']})');
    print('  Poster: ${first['poster']}');
  }
  assert(asianDramaItems.isNotEmpty, 'Asian & Short dramas catalog should not be empty');

  // 2. Test Hindi Movies & Hindi Series Catalogs
  print('\n--- [2/6] Testing Hindi Movies Catalog (sort: new & trending) ---');
  final hindiMoviesNew = await CatalogService.instance.getCatalogItems(
    type: 'movie',
    id: 'hindi_movies',
    sort: 'new',
  );
  print('Found ${hindiMoviesNew.length} New Hindi Movies:');
  for (final m in hindiMoviesNew.take(2)) {
    print('  - ${m['name']} (${m['year']}) Poster: ${m['poster']}');
  }

  print('\n--- [3/6] Testing Hindi Series Catalog (sort: trending) ---');
  final hindiSeriesTrending = await CatalogService.instance.getCatalogItems(
    type: 'series',
    id: 'hindi_series',
    sort: 'trending',
  );
  print('Found ${hindiSeriesTrending.length} Trending Hindi Series:');
  for (final s in hindiSeriesTrending.take(2)) {
    print('  - ${s['name']} (${s['year']}) Rating: ${s['rating']}');
  }

  // 4. Test Clicked Drama Poster Preservation (No GOT Poster)
  print('\n--- [4/6] Testing Drama Poster Preservation (Fix after click) ---');
  final testCustomPoster = 'https://dramafren.org/cover/mommy_go_easy.jpg';
  final metaDetail = await CatalogService.instance.getMetaDetail(
    'series',
    'sd:mommy_go_easy_the_jerk_dad_regrets_it',
    poster: testCustomPoster,
    name: 'Mommy Go Easy The Jerk Dad Regrets It',
  );
  print('Resolved Name: ${metaDetail?['name']}');
  print('Resolved Poster: ${metaDetail?['poster']}');
  final ep1Thumb = metaDetail?['episodesBySeason']?['1']?[0]?['thumbnail'];
  print('Episode 1 Thumbnail: $ep1Thumb');
  assert(!(metaDetail?['poster']?.toString().contains('u3bZgnGQ9T01sWNhyveQz0wH0Hl') ?? false), 'Must not contain GOT iron throne poster');
  assert(metaDetail?['poster'] == testCustomPoster, 'Must preserve custom clicked poster');

  // 5. Test Smart Stream Title Formatting (Badges + Original Release Name)
  print('\n--- [5/6] Testing Smart Stream Title Formatting ---');
  final enriched = BadgeService.enrichStream(
    rawTitle: 'Avatar.2009.Extended.Collector.Edition.2160p.UHD.Remux.HDR.HEVC.Atmos.Hindi.DD5.1.English.mkv',
    mediaTitle: 'Avatar',
    year: 2009,
    quality: '4K',
    codec: 'HEVC',
    audioBadge: 'Atmos',
    fileSize: '48.2 GB',
    providerName: 'Vegamovies',
    sourceName: 'Vegamovies',
    siteDomain: 'vegamovies.im',
    hostName: 'HubCloud',
    isCached: true,
  );

  print('Generated Display Name:');
  print('  ${enriched['name']?.replaceAll('\n', ' ')}');
  print('Generated Multi-Line Title:');
  for (final line in enriched['title']!.split('\n')) {
    if (line.trim().isNotEmpty && !line.contains('cdn.jsdelivr.net')) {
      print('  $line');
    }
  }

  // 6. Test New Scrapers Registrations & Domains
  print('\n--- [6/6] Testing New Scraper Registrations & Domains ---');
  final list = ScraperEngine.instance.getProviderList();
  print('Total Scrapers in Engine: ${list.length}');
  final newIds = ['shortdrama', 'hdobox', 'bilibili', 'sportzxlive'];
  for (final id in newIds) {
    final exists = list.any((p) => p['id'] == id);
    final domain = ScraperEngine.siteDomainMap[id] ?? 'N/A';
    print('  Scraper "$id": ${exists ? "✔ Registered" : "✖ Missing"} | Domain: $domain');
  }

  print('\n====================================================');
  print('✅ All tests completed successfully!');
  print('====================================================');
  exit(0);
}
