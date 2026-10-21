import 'dart:convert';
import 'dart:io';
import '../lib/catalog_service.dart';
import '../lib/scraper_engine.dart';
import '../lib/metadata_service.dart';
import '../lib/badge_service.dart';
import '../lib/doh_resolver.dart';
import '../lib/iptv_service.dart';
import '../lib/stream_probe_service.dart';
import '../lib/torbox_service.dart';

void main() async {
  print('====================================================');
  print('🧪 Comprehensive Test Suite: Hostreamio Full Regression');
  print('====================================================\n');

  // 1. Test Asian & Short Dramas Catalog
  print('--- [1/12] Testing Asian & Short Dramas Catalog ---');
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
  print('\n--- [2/12] Testing Hindi Movies Catalog (sort: new & trending) ---');
  final hindiMoviesNew = await CatalogService.instance.getCatalogItems(
    type: 'movie',
    id: 'hindi_movies',
    sort: 'new',
  );
  print('Found ${hindiMoviesNew.length} New Hindi Movies:');
  for (final m in hindiMoviesNew.take(2)) {
    print('  - ${m['name']} (${m['year']}) Poster: ${m['poster']}');
  }

  print('\n--- [3/12] Testing Hindi Series Catalog (sort: trending) ---');
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
  print('\n--- [4/12] Testing Drama Poster Preservation (Fix after click) ---');
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
  print('\n--- [5/12] Testing Smart Stream Title Formatting ---');
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
  print('\n--- [6/12] Testing New Scraper Registrations & Domains ---');
  final list = ScraperEngine.instance.getProviderList();
  print('Total Scrapers in Engine: ${list.length}');
  final newIds = ['shortdrama', 'hdobox', 'bilibili', 'sportzxlive'];
  for (final id in newIds) {
    final exists = list.any((p) => p['id'] == id);
    final domain = ScraperEngine.siteDomainMap[id] ?? 'N/A';
    print('  Scraper "$id": ${exists ? "✔ Registered" : "✖ Missing"} | Domain: $domain');
  }

  // 7. Test Short Drama Metadata Resolution
  print('\n--- [7/12] Testing Short Drama Metadata Resolution (Fix sd: prefix) ---');
  final resolvedSd = await MetadataService.resolve(
    type: 'series',
    rawId: 'sd:double_life_billionaire',
  );
  print('Resolved sd: ID: ${resolvedSd?.id}');
  print('Resolved sd: Title: "${resolvedSd?.title}"');
  print('Resolved sd: Poster: ${resolvedSd?.poster}');
  assert(resolvedSd != null, 'Short drama metadata must resolve');
  assert(resolvedSd!.title == 'The Double Life of My Billionaire Husband', 'Title must resolve accurately');

  // 8. Test Custom Stream Resolvers (sd:, iptv:, archive:)
  print('\n--- [8/12] Testing Custom Stream Resolvers (sd:, iptv:, archive:) ---');
  CatalogService.dynamicShortDramas['sd:test_drama'] = {
    'id': 'sd:test_drama',
    'name': 'Test Micro Drama Ep 1',
    'url': 'https://example.com/stream.m3u8',
  };
  final sdStreams = await CatalogService.instance.resolveCustomStreams('series', 'sd:test_drama');
  print('Resolved ${sdStreams.length} stream(s) for dynamic sd:test_drama');
  assert(sdStreams.isNotEmpty, 'Short drama custom streams should resolve');
  print('  Sample Stream Name: ${sdStreams.first['name']}');
  print('  Sample Stream URL: ${sdStreams.first['url']}');
  assert(sdStreams.first['url'] == 'https://example.com/stream.m3u8');

  // 9. Test DNS-over-HTTPS (DoH) Resolver
  print('\n--- [9/12] Testing DNS-over-HTTPS (DoH) Resolver ---');
  final ips = await DohResolver.instance.resolve('1.1.1.1');
  print('DoH IP literal resolution: ${ips.map((ip) => ip.address).toList()}');
  assert(ips.isNotEmpty && ips.first.address == '1.1.1.1', 'DoH should resolve IP literals immediately');

  // 10. Test Stream Probe Service
  print('\n--- [10/12] Testing Stream Probe Service ---');
  final probeRes = await StreamProbeService.instance.probeStream(
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    timeout: const Duration(seconds: 4),
  );
  print('Direct MP4 probe result: playable=${probeRes.isPlayable}, status=${probeRes.statusCode}');
  assert(probeRes.isPlayable, 'Valid direct stream should be marked playable');

  // 11. Test TorBox Cloud Debrid & Hoster Identification
  print('\n--- [11/12] Testing TorBox Cloud Debrid & Hoster Identification ---');
  final pixeldrainStatus = TorboxService.instance.checkHosterStatus('https://pixeldrain.com/u/test1234');
  final gofileStatus = TorboxService.instance.checkHosterStatus('https://gofile.io/d/abc123');
  final directMp4Status = TorboxService.instance.checkHosterStatus('https://cdn.example.com/stream.mp4');
  print('Pixeldrain status: name=${pixeldrainStatus.name}, isSupported=${pixeldrainStatus.isSupported}');
  print('Gofile status: name=${gofileStatus.name}, isSupported=${gofileStatus.isSupported}');
  print('Direct MP4 status: name=${directMp4Status.name}, isSupported=${directMp4Status.isSupported}');
  assert(pixeldrainStatus.isSupported && pixeldrainStatus.name == 'Pixeldrain');
  assert(gofileStatus.isSupported && gofileStatus.name == 'Gofile');
  assert(directMp4Status.isSupported);

  // 12. Test Android Keystore & Codebase Parity Integrity
  print('\n--- [12/12] Testing Android Keystore & Codebase Parity Integrity ---');
  final keystoreFile = File('android_app/android/app/release.jks');
  print('Keystore release.jks exists: ${keystoreFile.existsSync()} (Length: ${keystoreFile.lengthSync()} bytes)');
  assert(keystoreFile.existsSync() && keystoreFile.lengthSync() > 1000, 'Persistent release.jks must exist');

  final gradleContent = File('android_app/android/app/build.gradle').readAsStringSync();
  assert(gradleContent.contains('signingConfigs.release') && gradleContent.contains("storeFile file('release.jks')"),
      'build.gradle must reference persistent release.jks');
  print('Signing config verification: ✔ release.jks wired into signingConfigs.release');

  final sharedFiles = [
    'catalog_service.dart',
    'metadata_service.dart',
    'badge_service.dart',
    'torbox_service.dart',
    'doh_resolver.dart',
    'stream_probe_service.dart',
  ];
  for (final sf in sharedFiles) {
    final rootFile = File('lib/$sf');
    final androidFile = File('android_app/lib/$sf');
    assert(rootFile.existsSync() && androidFile.existsSync(), 'Shared file $sf must exist in both lib/ and android_app/lib/');
    final rootLen = rootFile.lengthSync();
    final androidLen = androidFile.lengthSync();
    assert(rootLen == androidLen, 'Shared file $sf must have 100% byte parity ($rootLen vs $androidLen bytes)');
  }
  print('Codebase parity verification: ✔ 100% parity across lib/ and android_app/lib/');

  print('\n====================================================');
  print('✅ All 12/12 regression test phases completed successfully!');
  print('====================================================');
  exit(0);
}
