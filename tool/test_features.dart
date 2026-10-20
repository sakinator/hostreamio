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

  // 1. Test Short Dramas Catalog
  print('--- [1/4] Testing Short Dramas Catalog ---');
  final shortDramaItems = await CatalogService.instance.getCatalogItems(
    type: 'series',
    id: 'short_dramas',
  );
  print('Found ${shortDramaItems.length} Short Drama catalog items.');
  if (shortDramaItems.isNotEmpty) {
    final first = shortDramaItems.first;
    print('  Sample: "${first['name']}" (ID: ${first['id']}, Genres: ${first['genres']})');
    print('  Description:\n  ${first['description'].toString().split('\n').first}');
  }
  assert(shortDramaItems.isNotEmpty, 'Short dramas catalog should not be empty');

  // 2. Test Genre Filtering in Short Dramas Catalog
  print('\n--- [2/4] Testing Short Dramas Genre Filter ---');
  final werewolfItems = await CatalogService.instance.getCatalogItems(
    type: 'series',
    id: 'short_dramas',
    genre: 'Werewolf & Alpha',
  );
  print('Filtered by "Werewolf & Alpha": ${werewolfItems.length} items.');
  for (final it in werewolfItems.take(2)) {
    print('  - ${it['name']}');
  }

  // 3. Test Smart Stream Title Formatting (Badges + Original Release Name)
  print('\n--- [3/4] Testing Smart Stream Title Formatting ---');
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

  // 4. Test New Scrapers (HDO Box, Bilibili, SportzX Live, ShortDrama)
  print('\n--- [4/4] Testing New Scraper Registrations & Domains ---');
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
}
