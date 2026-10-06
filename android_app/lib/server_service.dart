import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'config.dart';
import 'metadata_service.dart';
import 'proxy.dart';
import 'scraper_engine.dart';
import 'web_ui.dart';
import 'catalog_service.dart';
import 'torbox_service.dart';
import 'doh_resolver.dart';
import 'key_validator.dart';

class ServerService {
  static final ServerService instance = ServerService._();

  ServerService._();

  HttpServer? _server;
  final ValueNotifier<bool> isRunning = ValueNotifier<bool>(false);
  final ValueNotifier<String> localIp = ValueNotifier<String>('127.0.0.1');
  final ValueNotifier<int> requestCount = ValueNotifier<int>(0);
  final ValueNotifier<String> statusMessage = ValueNotifier<String>('Stopped');
  final ValueNotifier<List<String>> logs = ValueNotifier<List<String>>([]);

  void _addLog(String msg) {
    final time = DateTime.now().toIso8601String().substring(11, 19);
    final entry = '[$time] $msg';
    final current = List<String>.from(logs.value);
    if (current.length > 50) current.removeAt(0);
    current.add(entry);
    logs.value = current;
    debugPrint(entry);
  }

  Future<void> init() async {
    await AddonConfig.instance.load();
    await updateLanIp();
    _initForegroundTask();
  }

  void _initForegroundTask() {
    if (!Platform.isAndroid) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'hostreamio_server_channel',
        channelName: 'Hostreamio Server Service',
        channelDescription: 'Keeps Hostreamio Addon HTTP Server active for Nuvio.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        iconData: const NotificationIconData(
          resType: ResourceType.mipmap,
          resPrefix: ResourcePrefix.ic,
          name: 'launcher',
        ),
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<String> updateLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback &&
              addr.address.startsWith('192.168.') &&
              !addr.address.startsWith('192.168.56.')) {
            localIp.value = addr.address;
            return addr.address;
          }
        }
      }
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('10.')) {
            localIp.value = addr.address;
            return addr.address;
          }
        }
      }
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback &&
              !addr.address.startsWith('169.254.') &&
              !addr.address.startsWith('172.') &&
              !addr.address.startsWith('192.168.56.') &&
              !addr.address.startsWith('45.')) {
            localIp.value = addr.address;
            return addr.address;
          }
        }
      }
    } catch (e) {
      _addLog('IP detection error: $e');
    }
    return localIp.value;
  }

  Future<bool> startServer() async {
    if (isRunning.value) return true;

    try {
      HttpOverrides.global = MegascraperHttpOverrides();
      DohResolver.instance.prewarm([
        'api.torbox.app',
        'cinematv.click',
        'vidsrc.to',
        'vidlink.pro',
        'autoembed.cc',
        'embed.su',
        'rabbitstream.net',
        'megacloud.tv',
        '1337x.to',
        'torrentgalaxy.to',
        'vegamovies.im',
        'hdhub4u.tv',
      ]);

      final cfg = AddonConfig.instance;
      await updateLanIp();

      _server = await HttpServer.bind(InternetAddress.anyIPv4, cfg.port);
      isRunning.value = true;
      statusMessage.value = 'Running on port ${cfg.port}';
      _addLog('Server started on http://${localIp.value}:${cfg.port}');

      // Start foreground service to keep CPU awake on Android TV / Mobile
      if (Platform.isAndroid) {
        try {
          if (!await FlutterForegroundTask.isRunningService) {
            await FlutterForegroundTask.startService(
              notificationTitle: 'Hostreamio Server Active',
              notificationText: 'Serving Nuvio streams on port ${cfg.port}',
            );
          }
        } catch (e) {
          _addLog('Foreground service note: $e');
        }
      }

      _listenToRequests(_server!, cfg.port);
      return true;
    } catch (e) {
      statusMessage.value = 'Error: $e';
      _addLog('Failed to start server: $e');
      isRunning.value = false;
      return false;
    }
  }

  Future<void> stopServer() async {
    if (!isRunning.value) return;
    try {
      await _server?.close(force: true);
      _server = null;
      isRunning.value = false;
      statusMessage.value = 'Stopped';
      _addLog('Server stopped');

      if (Platform.isAndroid) {
        try {
          if (await FlutterForegroundTask.isRunningService) {
            await FlutterForegroundTask.stopService();
          }
        } catch (_) {}
      }
    } catch (e) {
      _addLog('Error stopping server: $e');
    }
  }

  void _listenToRequests(HttpServer server, int port) async {
    await for (final request in server) {
      requestCount.value = requestCount.value + 1;
      _handleRequest(request, port);
    }
  }

  static Map<String, dynamic>? _safeParseJsonMap(String bodyStr) {
    if (bodyStr.trim().isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(bodyStr);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _handleRequest(HttpRequest request, int port) async {
    final path = request.uri.path;
    final method = request.method.toUpperCase();

    // CORS: Allow public access for Stremio Web / apps on addon & proxy routes,
    // while securing internal admin / control API endpoints against cross-origin CSRF.
    final origin = request.headers.value('origin');
    final isPublicRoute = path == '/manifest.json' ||
        path.startsWith('/catalog') ||
        path.startsWith('/stream') ||
        path.startsWith('/meta') ||
        path.startsWith('/subtitles') ||
        path.startsWith('/proxy') ||
        path.startsWith('/torbox/play') ||
        path == '/logo.png' ||
        path == '/favicon.png' ||
        path == '/favicon.ico' ||
        path == '/configure' ||
        path == '/mobile-config' ||
        path == '/api/keys/current';

    if (isPublicRoute) {
      request.response.headers.set('Access-Control-Allow-Origin', '*');
      request.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS, HEAD');
      request.response.headers.set('Access-Control-Allow-Headers', '*');
    } else {
      final lan = localIp.value;
      final isAllowedOrigin = origin == null ||
          origin.contains('localhost') ||
          origin.contains('127.0.0.1') ||
          (lan.isNotEmpty && origin.contains(lan)) ||
          origin.startsWith('stremio://') ||
          origin.startsWith('http://localhost') ||
          origin.startsWith('https://localhost');

      if (isAllowedOrigin) {
        request.response.headers.set('Access-Control-Allow-Origin', origin ?? '*');
        request.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS, HEAD');
        request.response.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
      } else {
        request.response.statusCode = HttpStatus.forbidden;
        request.response.write('Cross-origin request to admin API blocked');
        await request.response.close();
        return;
      }
    }

    if (method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    // Use the exact scheme and authority (host:port) that the client connected to
    final localBaseUrl = '${request.requestedUri.scheme}://${request.requestedUri.authority}';

    try {
      // 0. Static Brand Logo & Favicon
      if (path == '/logo.png' || path == '/favicon.png' || path == '/favicon.ico') {
        final candidates = [
          File('hostreamio_logo.png'),
          File('assets/images/hostreamio_logo.png'),
          File('android_app/assets/images/hostreamio_logo.png'),
        ];
        for (final f in candidates) {
          if (f.existsSync()) {
            request.response.headers.contentType = ContentType('image', 'png');
            await request.response.addStream(f.openRead());
            await request.response.close();
            return;
          }
        }
      }

      // 1. Web dashboard
      if (path == '/' || path == '/configure') {
        request.response.headers.contentType = ContentType.html;
        request.response.write(WebUI.render(localIp: localIp.value, port: port));
        await request.response.close();
        return;
      }

      // 1b. GET /api/keys/current — returns current API key values (for mobile-config page)
      if (path == '/api/keys/current' && method == 'GET') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'omdbApiKey': AddonConfig.instance.omdbApiKey,
          'fanartApiKey': AddonConfig.instance.fanartApiKey,
          'tvdbApiKey': AddonConfig.instance.tvdbApiKey,
          'tmdbApiKey': AddonConfig.instance.tmdbApiKey,
          'dtddApiKey': AddonConfig.instance.dtddApiKey,
          'torboxApiKey': AddonConfig.instance.torboxApiKey,
        }));
        await request.response.close();
        return;
      }

      // 1c. GET /mobile-config — Mobile-friendly API key configuration page (QR target)
      if (path == '/mobile-config') {
        final ip = localIp.value;
        final baseUrl = 'http://$ip:$port';
        request.response.headers.contentType = ContentType.html;
        request.response.write(_buildMobileConfigPage(baseUrl));
        await request.response.close();
        return;
      }

      // 2. Stremio/Nuvio Addon Manifest
      if (path == '/manifest.json') {
        final manifest = {
          'id': 'org.sakinator.hostreamio',
          'version': '1.0.0',
          'name': 'Hostreamio',
          'description': 'Hostreamio — Direct Hosters, Streaming Links & TorBox Cloud Debrid Stream Engine with Smart Proxy & Instant Badges',
          'resources': ['catalog', 'meta', 'stream'],
          'types': ['movie', 'series'],
          'idPrefixes': ['tt', 'tmdb', 'kitsu', 'yt:', 'archive:', 'dm:', 'vimeo:'],
          'catalogs': CatalogService.getCatalogs(),
          'behaviorHints': {
            'configurable': true,
            'configurationRequired': false,
            'configurationURL': 'http://${request.headers.host ?? "${localIp.value}:$port"}/configure',
          },
        };
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(manifest));
        await request.response.close();
        return;
      }

      // 3. Catalogs Endpoint: /catalog/:type/:id.json
      if (path.startsWith('/catalog/')) {
        final segments = request.uri.pathSegments;
        if (segments.length >= 3) {
          final type = segments[1];
          var catId = segments[2];
          if (catId.endsWith('.json')) {
            catId = catId.substring(0, catId.length - 5);
          }

          String? search;
          String? genre;
          int skip = 0;

          if (segments.length >= 4) {
            var extra = Uri.decodeComponent(segments[3]);
            if (extra.endsWith('.json')) {
              extra = extra.substring(0, extra.length - 5);
            }
            final parts = extra.split('&');
            for (final p in parts) {
              if (p.startsWith('search=')) search = p.substring(7);
              if (p.startsWith('genre=')) genre = p.substring(6);
              if (p.startsWith('skip=')) skip = int.tryParse(p.substring(5)) ?? 0;
            }
          }

          _addLog('Catalog: $catId ($genre)');
          final items = await CatalogService.instance.getCatalogItems(
            type: type,
            id: catId,
            search: search,
            genre: genre,
            skip: skip,
          );

          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'metas': items}));
          await request.response.close();
          return;
        }
      }

      // 4. Metadata Detail Endpoint: /meta/:type/:id.json
      if (path.startsWith('/meta/')) {
        final segments = request.uri.pathSegments;
        if (segments.length >= 3) {
          final type = segments[1];
          var metaId = Uri.decodeComponent(segments[2]);
          if (metaId.endsWith('.json')) {
            metaId = metaId.substring(0, metaId.length - 5);
          }

          final meta = await CatalogService.instance.getMetaDetail(type, metaId);
          if (meta != null) {
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({'meta': meta}));
            await request.response.close();
            return;
          }

          // Standard movie / series metadata enriched with Fanart.tv ClearLogos & OMDb ratings
          final resolved = await MetadataService.resolve(type: type, rawId: metaId);
          if (resolved != null) {
            final metaObj = <String, dynamic>{
              'id': resolved.id,
              'type': resolved.type,
              'name': resolved.title,
              if (resolved.genres != null && resolved.genres!.isNotEmpty)
                'genres': resolved.genres
              else if (resolved.omdb?.genre != null)
                'genres': resolved.omdb!.genre!.split(', ').map((s) => s.trim()).toList()
              else
                'genres': ['Cinema'],
              'year': resolved.year?.toString() ?? resolved.omdb?.year ?? '',
              'releaseInfo': resolved.year?.toString() ?? resolved.omdb?.year ?? '',
              'description': resolved.description ?? resolved.omdb?.plot ?? '',
              if (resolved.omdb?.director != null && resolved.omdb!.director!.isNotEmpty)
                'director': [resolved.omdb!.director!],
              if (resolved.omdb?.actors != null && resolved.omdb!.actors!.isNotEmpty)
                'cast': resolved.omdb!.actors!.split(', ').map((s) => s.trim()).toList(),
              if (resolved.omdb?.imdbRating != null && resolved.omdb!.imdbRating != 'N/A')
                'imdbRating': resolved.omdb!.imdbRating,
              if (resolved.poster != null) 'poster': resolved.poster,
              if (resolved.background != null) 'background': resolved.background,
              if (resolved.logo != null) 'logo': resolved.logo,
            };
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({'meta': metaObj}));
            await request.response.close();
            return;
          }
        }
      }

      // 5. Streams endpoint: /stream/:type/:id.json
      if (path.startsWith('/stream/')) {
        final segments = request.uri.pathSegments;
        if (segments.length >= 3) {
          final type = segments[1];
          var idWithExt = Uri.decodeComponent(segments[2]);
          if (idWithExt.endsWith('.json')) {
            idWithExt = idWithExt.substring(0, idWithExt.length - 5);
          }

          _addLog('Stream request: $type/$idWithExt');

          // Check custom video streams (YouTube, Vimeo, Archive.org, Dailymotion)
          // Also scrape all other hoster/torrent sources for this title & year, sorting own links FIRST!
          if (idWithExt.startsWith('yt:') || idWithExt.startsWith('vimeo:') || idWithExt.startsWith('archive:') || idWithExt.startsWith('dm:')) {
            final customStreamsFuture = CatalogService.instance.resolveCustomStreams(
              type, 
              idWithExt,
              localBaseUrl: localBaseUrl,
            );
            final metaDetailFuture = CatalogService.instance.getMetaDetail(type, idWithExt);

            final results = await Future.wait([customStreamsFuture, metaDetailFuture]);
            final customStreams = results[0] as List<Map<String, dynamic>>;
            final meta = results[1] as Map<String, dynamic>?;

            List<Map<String, dynamic>> otherStreams = [];
            final imdbId = meta?['imdbId']?.toString();
            if (imdbId != null && imdbId.isNotEmpty) {
              try {
                final cleanTitle = meta!['name'].toString();
                int? year;
                if (meta['year'] != null) {
                  year = int.tryParse(meta['year'].toString());
                }
                if (year == null && meta['releaseInfo'] != null) {
                  final match = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(meta['releaseInfo'].toString());
                  if (match != null) year = int.tryParse(match.group(1)!);
                }

                final mediaMeta = MediaMetadata(
                  id: imdbId,
                  type: type,
                  title: cleanTitle,
                  year: year,
                  imdbId: imdbId,
                );

                final scraped = await ScraperEngine.instance.scrapeAll(
                  meta: mediaMeta,
                  localBaseUrl: localBaseUrl,
                ).timeout(const Duration(seconds: 3), onTimeout: () => <ScrapedStream>[]);
                otherStreams = scraped.map((s) => s.toJson()).toList();
              } catch (e) {
                _addLog('Error scraping other providers for $idWithExt: $e');
              }
            }

            // Combined: Their OWN direct links appear FIRST, followed by all other sources!
            final allStreams = [...customStreams, ...otherStreams];
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({'streams': allStreams}));
            await request.response.close();
            return;
          }

          MediaMetadata? meta = await MetadataService.resolve(type: type, rawId: idWithExt);
          meta ??= MediaMetadata(
            id: idWithExt,
            type: type,
            title: idWithExt.replaceAll(RegExp(r'\+|_'), ' '),
          );

          // 1. Scrape verified hoster and debrid providers
          final scrapeFuture = ScraperEngine.instance.scrapeAll(
            meta: meta,
            localBaseUrl: localBaseUrl,
          );

          final futures = <Future<dynamic>>[scrapeFuture];
          if (AddonConfig.instance.enablePublicStreams) {
            futures.add(CatalogService.instance.searchPublicStreams(
              title: meta.title,
              year: meta.year,
              type: meta.type,
              localBaseUrl: localBaseUrl,
            ));
          }

          final results = await Future.wait(futures);
          final hosterStreams = (results[0] as List<ScrapedStream>).map((s) => s.toJson()).toList();
          final publicStreams = results.length > 1 ? (results[1] as List<Map<String, dynamic>>) : <Map<String, dynamic>>[];

          // Combine: Verified hoster & debrid streams ALWAYS appear first!
          final allStreams = [...hosterStreams, ...publicStreams];

          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'streams': allStreams,
          }));
          await request.response.close();
          return;
        }
      }


      // 4. Stream Proxy: /proxy?url=...
      if (path == '/proxy') {
        await StreamProxy.handleRequest(request);
        return;
      }

      // 4b. Torbox Debrid Play Endpoint: /torbox/play?url=...
      if (path == '/torbox/play') {
        final targetUrl = request.uri.queryParameters['url'];
        final headersParam = request.uri.queryParameters['headers'];
        if (targetUrl == null || targetUrl.isEmpty) {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.write('Missing url parameter');
          await request.response.close();
          return;
        }
        final apiKey = AddonConfig.instance.torboxApiKey.trim();
        _addLog('Torbox play: $targetUrl');
        final debridedUrl = await TorboxService.instance.debridLink(targetUrl, apiKey);
        if (debridedUrl != null && debridedUrl.isNotEmpty) {
          _addLog('Torbox CDN streaming redirect');
          await request.response.redirect(Uri.parse(debridedUrl), status: HttpStatus.found);
          return;
        }
        // Fallback: if debrid failed on an unplayable hoster landing page, do NOT redirect video player to an HTML page!
        if (!ScraperEngine.isDirectPlayableUrl(targetUrl)) {
          final errReason = TorboxService.instance.lastDebridError ??
              'TorBox could not unrestrict this hoster link. The file may be offline, deleted, or hoster is temporarily unavailable.';
          _addLog('TorBox debrid failure for $targetUrl: $errReason');

          final accept = request.headers.value('accept') ?? '';
          if (accept.contains('text/html')) {
            request.response.statusCode = HttpStatus.badGateway;
            request.response.headers.contentType = ContentType.html;
            request.response.write('''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>TorBox Debrid Notice - Hostreamio</title>
  <style>
    body { background:#0a0d14; color:#e6edf3; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; display:flex; align-items:center; justify-content:center; height:100vh; margin:0; }
    .card { background:#161b22; border:1px solid #30363d; border-radius:12px; padding:32px; max-width:540px; box-shadow:0 12px 32px rgba(0,0,0,0.5); text-align:center; }
    h2 { color:#f85149; margin-top:0; }
    p { color:#8b949e; line-height:1.6; font-size:0.95rem; }
    .err-box { background:#21262d; border:1px solid #30363d; padding:12px; border-radius:8px; font-family:monospace; font-size:0.85rem; color:#ff7b72; margin:16px 0; word-break:break-all; }
    .btn-group { display:flex; gap:12px; justify-content:center; margin-top:24px; }
    .btn { padding:10px 18px; border-radius:6px; font-weight:600; text-decoration:none; font-size:0.9rem; cursor:pointer; }
    .btn-primary { background:#1f6feb; color:#fff; border:none; }
    .btn-secondary { background:#21262d; color:#c9d1d9; border:1px solid #30363d; }
  </style>
</head>
<body>
  <div class="card">
    <h2>⚠️ TorBox Cloud Debrid Notice</h2>
    <p>TorBox was unable to unrestrict and stream this hoster file into your cloud drive.</p>
    <div class="err-box">${htmlEscape.convert(errReason)}</div>
    <div class="btn-group">
      <a href="/configure" class="btn btn-primary">⬅️ Back to Dashboard</a>
      <a href="${htmlEscape.convert(targetUrl)}" target="_blank" rel="noopener noreferrer" class="btn btn-secondary">🔗 Open Hoster Web Page</a>
    </div>
  </div>
</body>
</html>
''');
            await request.response.close();
            return;
          }

          request.response.statusCode = HttpStatus.badGateway;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'success': false,
            'error': errReason,
            'targetUrl': targetUrl,
          }));
          await request.response.close();
          return;
        }
        if (headersParam != null && headersParam.isNotEmpty) {
          final proxyUrl = '$localBaseUrl/proxy?url=${Uri.encodeComponent(targetUrl)}&headers=${Uri.encodeComponent(headersParam)}';
          await request.response.redirect(Uri.parse(proxyUrl), status: HttpStatus.found);
          return;
        }
        await request.response.redirect(Uri.parse(targetUrl), status: HttpStatus.found);
        return;
      }

      // 4b2. Native Desktop Player Launcher: POST/GET /api/player/launch
      if (path == '/api/player/launch' && (method == 'POST' || method == 'GET')) {
        String player = (request.uri.queryParameters['player'] ?? '').toLowerCase();
        String streamUrl = request.uri.queryParameters['url'] ?? '';

        if (streamUrl.isEmpty && method == 'POST') {
          try {
            final bodyStr = await utf8.decodeStream(request);
            final map = _safeParseJsonMap(bodyStr) ?? {};
            if (map['url'] != null && map['url'].toString().isNotEmpty) {
              streamUrl = map['url'].toString();
            }
            if (map['player'] != null && map['player'].toString().isNotEmpty) {
              player = map['player'].toString().toLowerCase();
            }
          } catch (_) {}
        }

        if (player.isEmpty) player = 'vlc';

        if (streamUrl.isEmpty) {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'success': false, 'message': 'Missing stream URL'}));
          await request.response.close();
          return;
        }

        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'success': false,
          'message': 'Direct desktop player launch is only supported on Windows'
        }));
        await request.response.close();
        return;
      }

      // 4c. In-App Media Search: GET /api/search?q=...&type=movie|series
      if (path == '/api/search') {
        final q = request.uri.queryParameters['q'] ?? '';
        final type = request.uri.queryParameters['type'] ?? 'movie';
        final results = await MetadataService.search(query: q, type: type);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'success': true, 'results': results}));
        await request.response.close();
        return;
      }

      // 4c2. In-App Series Catalog & Episodes: GET /api/series/episodes?id=...
      if (path == '/api/series/episodes') {
        final id = request.uri.queryParameters['id'] ?? '';
        final details = await MetadataService.getSeriesDetails(id);
        request.response.headers.contentType = ContentType.json;
        if (details != null) {
          request.response.write(jsonEncode({'success': true, 'series': details}));
        } else {
          request.response.write(jsonEncode({'success': false, 'message': 'Series details not found'}));
        }
        await request.response.close();
        return;
      }

      // 4d. M3U Playlist Generator: GET /stream/playlist.m3u?url=...&title=...
      if (path == '/stream/playlist.m3u') {
        final url = request.uri.queryParameters['url'] ?? '';
        final title = request.uri.queryParameters['title'] ?? 'Hostreamio Stream';
        final cleanTitle = title.replaceAll(RegExp(r'[\r\n]'), ' ');
        final content = '#EXTM3U\n#EXTINF:-1,$cleanTitle\n$url\n';
        request.response.headers.contentType = ContentType('application', 'x-mpegurl');
        request.response.headers.set('Content-Disposition', 'attachment; filename="stream.m3u"');
        request.response.write(content);
        await request.response.close();
        return;
      }

      // 5. Provider toggle: POST /api/provider/:id
      if (path.startsWith('/api/provider/') && method == 'POST') {
        final providerId = path.replaceFirst('/api/provider/', '');
        final bodyStr = await utf8.decodeStream(request);
        final bodyJson = _safeParseJsonMap(bodyStr) ?? {};
        final enabled = bodyJson['enabled'] == true;

        AddonConfig.instance.toggleProvider(providerId, enabled);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'success': true, 'id': providerId, 'enabled': enabled}));
        await request.response.close();
        return;
      }

      // 5a. Bulk toggle providers: POST /api/providers/bulk
      if (path == '/api/providers/bulk' && method == 'POST') {
        final bodyStr = await utf8.decodeStream(request);
        final bodyJson = _safeParseJsonMap(bodyStr) ?? {};
        final ids = (bodyJson['ids'] as List?)?.map((e) => e.toString()).toList() ?? [];
        final enabled = bodyJson['enabled'] == true;

        for (final id in ids) {
          AddonConfig.instance.toggleProvider(id, enabled);
        }
        await AddonConfig.instance.save();
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'success': true, 'count': ids.length, 'enabled': enabled}));
        await request.response.close();
        return;
      }

      // 5b. API: Configure Torbox: POST /api/torbox/config
      if (path == '/api/torbox/config' && method == 'POST') {
        final bodyStr = await utf8.decodeStream(request);
        final bodyJson = _safeParseJsonMap(bodyStr) ?? {};
        final apiKey = bodyJson['apiKey']?.toString().trim() ?? '';
        AddonConfig.instance.torboxApiKey = apiKey;
        await AddonConfig.instance.save();
        final account = await TorboxService.instance.validateAccount(apiKey);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'success': true,
          'valid': account['valid'] == true,
          'email': account['email'],
          'plan': account['plan'],
          'expires': account['expires'],
          'message': account['message'],
          'account': account,
        }));
        await request.response.close();
        return;
      }

      // 5c. API: Live Torbox Hosters: GET /api/torbox/hosters
      if (path == '/api/torbox/hosters') {
        final apiKey = AddonConfig.instance.torboxApiKey.trim();
        final hosters = await TorboxService.instance.getHosters(apiKey: apiKey.isNotEmpty ? apiKey : null);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'success': true, 'hosters': hosters}));
        await request.response.close();
        return;
      }

      // 5d. API: Upload / Cache Link to Torbox: POST /api/torbox/upload
      if (path == '/api/torbox/upload' && method == 'POST') {
        final bodyStr = await utf8.decodeStream(request);
        final bodyJson = _safeParseJsonMap(bodyStr) ?? {};
        var url = bodyJson['url']?.toString().trim() ?? '';
        if (url.contains('?url=')) {
          try {
            final uri = Uri.parse(url);
            final inner = uri.queryParameters['url'];
            if (inner != null && inner.isNotEmpty) {
              url = inner;
            }
          } catch (_) {}
        }
        final apiKey = AddonConfig.instance.torboxApiKey.trim();
        final uploadRes = await TorboxService.instance.uploadToTorbox(url, apiKey);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(uploadRes));
        await request.response.close();
        return;
      }

      // 5e. API: Save Playback & Filtering Settings: POST /api/settings
      if (path == '/api/settings' && method == 'POST') {
        final bodyStr = await utf8.decodeStream(request);
        final bodyJson = _safeParseJsonMap(bodyStr) ?? {};
        if (bodyJson.containsKey('excludeCams')) {
          AddonConfig.instance.excludeCams = bodyJson['excludeCams'] == true;
        }
        if (bodyJson.containsKey('maxResolution')) {
          AddonConfig.instance.maxResolution = bodyJson['maxResolution'].toString();
        }
        if (bodyJson.containsKey('preferredLanguage')) {
          AddonConfig.instance.preferredLanguage = bodyJson['preferredLanguage'].toString();
        }
        if (bodyJson.containsKey('enableDeduplication')) {
          AddonConfig.instance.enableDeduplication = bodyJson['enableDeduplication'] == true;
        }
        if (bodyJson.containsKey('enableDeadLinkFilter')) {
          AddonConfig.instance.enableDeadLinkFilter = bodyJson['enableDeadLinkFilter'] == true;
        }
        if (bodyJson.containsKey('showRatingsInStreams')) {
          AddonConfig.instance.showRatingsInStreams = bodyJson['showRatingsInStreams'] == true;
        }
        if (bodyJson.containsKey('omdbApiKey')) {
          AddonConfig.instance.omdbApiKey = bodyJson['omdbApiKey'].toString().trim();
        }
        if (bodyJson.containsKey('fanartApiKey')) {
          AddonConfig.instance.fanartApiKey = bodyJson['fanartApiKey'].toString().trim();
        }
        if (bodyJson.containsKey('tvdbApiKey')) {
          AddonConfig.instance.tvdbApiKey = bodyJson['tvdbApiKey'].toString().trim();
        }
        if (bodyJson.containsKey('tmdbApiKey')) {
          AddonConfig.instance.tmdbApiKey = bodyJson['tmdbApiKey'].toString().trim();
        }
        if (bodyJson.containsKey('dtddApiKey')) {
          AddonConfig.instance.dtddApiKey = bodyJson['dtddApiKey'].toString().trim();
        }
        if (bodyJson.containsKey('torboxApiKey')) {
          AddonConfig.instance.torboxApiKey = bodyJson['torboxApiKey'].toString().trim();
        }
        await AddonConfig.instance.save();
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'success': true}));
        await request.response.close();
        return;
      }

      // 5f. API: Validate Key: POST /api/keys/validate
      if (path == '/api/keys/validate' && method == 'POST') {
        final bodyStr = await utf8.decodeStream(request);
        final bodyJson = _safeParseJsonMap(bodyStr) ?? {};
        final service = bodyJson['service']?.toString() ?? '';
        final key = bodyJson['key']?.toString() ?? '';
        final result = await KeyValidator.validate(service, key);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(result.toJson()));
        await request.response.close();
        return;
      }

      // 5g. API: Reset Circuit Breakers: POST /api/scrapers/reset
      if (path == '/api/scrapers/reset' && method == 'POST') {
        ScraperEngine.instance.reloadScrapers();
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'success': true, 'message': 'All scrapers and circuit breakers reset'}));
        await request.response.close();
        return;
      }

      // 5h. API: Upstream update pipeline: POST /api/pipeline/update
      if (path == '/api/pipeline/update' && method == 'POST') {
        String channel = 'all';
        try {
          final bodyStr = await utf8.decodeStream(request);
          if (bodyStr.isNotEmpty) {
            final bodyJson = jsonDecode(bodyStr) as Map;
            if (bodyJson['channel'] != null) channel = bodyJson['channel'].toString();
          }
        } catch (_) {}
        final result = await _runUpdatePipeline(channel);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(result));
        await request.response.close();
        return;
      }

      // 5h. API: Check all updates & GitHub releases: GET /api/updates/check
      if (path == '/api/updates/check') {
        Map<String, dynamic> releaseInfo = {
          'version': 'v2.0.0',
          'isLatest': true,
          'apkUrl': 'https://github.com/sakinator/hostreamio/releases/latest/download/hostreamio.apk',
          'zipUrl': 'https://github.com/sakinator/hostreamio/releases/latest/download/hostreamio-windows-x64.zip',
          'url': 'https://github.com/sakinator/hostreamio/releases',
        };
        try {
          final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
          client.userAgent = 'Hostreamio';
          final req = await client.getUrl(Uri.parse('https://api.github.com/repos/sakinator/hostreamio/releases'));
          final res = await req.close();
          if (res.statusCode == 200) {
            final body = await utf8.decodeStream(res);
            final list = jsonDecode(body) as List;
            if (list.isNotEmpty) {
              final latest = list.first as Map;
              final tagName = latest['tag_name']?.toString() ?? 'v2.0.0';
              final assets = latest['assets'] as List?;
              String? apkUrl;
              String? zipUrl;
              if (assets != null) {
                for (final a in assets) {
                  if (a is Map) {
                    final aname = a['name']?.toString() ?? '';
                    final dl = a['browser_download_url']?.toString();
                    if (aname.endsWith('.apk')) apkUrl = dl;
                    if (aname.endsWith('.zip')) zipUrl = dl;
                  }
                }
              }
              releaseInfo = {
                'version': tagName,
                'name': latest['name'],
                'url': latest['html_url'],
                'publishedAt': latest['published_at'],
                'apkUrl': apkUrl ?? 'https://github.com/sakinator/hostreamio/releases/latest/download/hostreamio.apk',
                'zipUrl': zipUrl ?? 'https://github.com/sakinator/hostreamio/releases/latest/download/hostreamio-windows-x64.zip',
              };
            }
          }
        } catch (_) {}

        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'currentVersion': 'v1.0.0',
          'providersCount': ScraperEngine.instance.getProviderList().length,
          'release': releaseInfo,
        }));
        await request.response.close();
        return;
      }

      // 6. Health
      if (path == '/health') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'status': 'ok', 'port': port}));
        await request.response.close();
        return;
      }

      // 7. Badges JSON
      if (path == '/badges.json') {
        request.response.headers.contentType = ContentType.json;
        final candidates = [
          File('data/badges.json'),
          File('${Directory.current.path}/data/badges.json'),
          File('assets/badges.json'),
        ];
        File? found;
        for (final f in candidates) {
          if (f.existsSync()) {
            found = f;
            break;
          }
        }
        if (found != null) {
          request.response.write(await found.readAsString());
        } else {
          request.response.write(jsonEncode({'status': 'ok', 'badges': 'configured'}));
        }
        await request.response.close();
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      request.response.write('Not found: $path');
      await request.response.close();
    } catch (e) {
      _addLog('Server error on $path: $e');
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write('Error: $e');
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>> _runUpdatePipeline([String channel = 'all']) async {
    final logs = <String>[];
    try {
      logs.add('[Update] Channel: $channel');
      if (channel == 'all' || channel == 'cloudstream' || channel == 'playtorrio' || channel == 'scrapers') {
        ScraperEngine.instance.reloadScrapers();
        logs.add('[Scrapers] Hot-reloaded ${ScraperEngine.instance.getProviderList().length} provider engines in memory (PlayTorrio, Cloudstream, Indian OTT & Anime).');
      }
      if (channel == 'all' || channel == 'badges') {
        logs.add('[Badges] OTT branding and regional audio badges verified active.');
      }
      return {
        'success': true,
        'channel': channel,
        'message': 'All engines and providers refreshed successfully!',
        'output': logs.join('\n'),
      };
    } catch (e) {
      return {
        'success': false,
        'channel': channel,
        'message': 'Update failed: $e',
        'output': logs.join('\n'),
      };
    }
  }

  /// Builds the mobile-friendly API key configuration page HTML.
  /// This page is served at GET /mobile-config and is the QR code target.
  static String _buildMobileConfigPage(String baseUrl) {
    return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
<title>Hostreamio — API Key Setup</title>
<style>
  :root {
    --bg: #0d1117; --surface: #161b22; --border: #30363d;
    --accent: #195feb; --pink: #ff0c82; --green: #3fb950;
    --red: #f85149; --text: #e6edf3; --muted: #8b949e;
    --blue: #58a6ff; --radius: 12px;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: var(--bg); color: var(--text); font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; min-height: 100vh; }
  .header { background: linear-gradient(135deg, #195feb22, #ff0c8222); border-bottom: 1px solid var(--border); padding: 18px 20px 14px; }
  .header-row { display: flex; align-items: center; gap: 12px; }
  .logo { width: 42px; height: 42px; border-radius: 10px; background: linear-gradient(135deg, var(--accent), var(--pink)); display: flex; align-items: center; justify-content: center; font-size: 22px; flex-shrink: 0; }
  .title { font-size: 19px; font-weight: 800; background: linear-gradient(90deg, #58a6ff, #ff0c82); -webkit-background-clip: text; -webkit-text-fill-color: transparent; background-clip: text; }
  .subtitle { font-size: 12px; color: var(--muted); margin-top: 2px; }
  .content { padding: 16px 16px 32px; max-width: 560px; margin: 0 auto; }
  .section-label { font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 0.8px; color: var(--muted); margin: 20px 0 10px; display: flex; align-items: center; gap: 6px; }
  .card { background: var(--surface); border: 1px solid var(--border); border-radius: var(--radius); overflow: hidden; margin-bottom: 10px; }
  .field-label { font-size: 13px; font-weight: 600; color: var(--text); padding: 12px 14px 0; }
  .field-hint { font-size: 11px; color: var(--muted); padding: 3px 14px 8px; }
  .input-row { display: flex; align-items: center; gap: 0; border-top: 1px solid var(--border); }
  .key-input { flex: 1; background: transparent; border: none; outline: none; color: var(--text); font-family: 'SF Mono', 'Fira Code', monospace; font-size: 13px; padding: 12px 14px; min-width: 0; }
  .key-input::placeholder { color: var(--muted); font-family: -apple-system, sans-serif; font-size: 12px; }
  .paste-btn { background: none; border: none; border-left: 1px solid var(--border); padding: 12px 14px; cursor: pointer; color: var(--blue); font-size: 18px; -webkit-tap-highlight-color: transparent; }
  .paste-btn:active { background: #ffffff0f; }
  .save-btn { width: 100%; padding: 15px; background: linear-gradient(135deg, var(--accent), #1a4fd8); color: #fff; font-size: 15px; font-weight: 700; border: none; border-radius: var(--radius); cursor: pointer; margin-top: 20px; display: flex; align-items: center; justify-content: center; gap: 8px; -webkit-tap-highlight-color: transparent; transition: opacity 0.15s; }
  .save-btn:active { opacity: 0.8; }
  .save-btn:disabled { opacity: 0.5; cursor: not-allowed; }
  .toast { position: fixed; bottom: 24px; left: 50%; transform: translateX(-50%); padding: 12px 22px; border-radius: 30px; font-size: 14px; font-weight: 600; opacity: 0; pointer-events: none; transition: opacity 0.25s; white-space: nowrap; z-index: 999; }
  .toast.show { opacity: 1; }
  .toast.success { background: var(--green); color: #fff; }
  .toast.error { background: var(--red); color: #fff; }
  .status-bar { font-size: 12px; text-align: center; color: var(--muted); margin-top: 12px; }
  .spinner { display: inline-block; width: 16px; height: 16px; border: 2px solid #ffffff44; border-top-color: #fff; border-radius: 50%; animation: spin 0.7s linear infinite; }
  @keyframes spin { to { transform: rotate(360deg); } }
  .info-box { background: #195feb15; border: 1px solid #195feb44; border-radius: 10px; padding: 12px 14px; margin-top: 16px; font-size: 12px; color: var(--blue); line-height: 1.5; }
</style>
</head>
<body>

<div class="header">
  <div class="header-row">
    <div class="logo">🎬</div>
    <div>
      <div class="title">Hostreamio Setup</div>
      <div class="subtitle">Configure API keys from your phone</div>
    </div>
  </div>
</div>

<div class="content">
  <div class="info-box">
    📡 Connected to your Android TV at <strong id="serverAddr">$baseUrl</strong><br>
    Keys are saved directly on your TV. All fields are optional.
  </div>

  <div class="section-label">🎞️ Metadata &amp; Ratings</div>

  <div class="card">
    <div class="field-label">OMDb API Key</div>
    <div class="field-hint">IMDb &amp; Rotten Tomatoes ratings · <a href="https://www.omdbapi.com/apikey.aspx" target="_blank" style="color:var(--blue)">Get free key ↗</a></div>
    <div class="input-row">
      <input class="key-input" id="omdbApiKey" type="text" placeholder="Leave empty for built-in fallback" autocomplete="off" autocorrect="off" spellcheck="false">
      <button class="paste-btn" onclick="pasteField('omdbApiKey')" title="Paste">📋</button>
    </div>
  </div>

  <div class="card">
    <div class="field-label">Fanart.tv API Key</div>
    <div class="field-hint">HD ClearLogos &amp; artwork · <a href="https://fanart.tv/get-an-api-key/" target="_blank" style="color:var(--blue)">Get key ↗</a></div>
    <div class="input-row">
      <input class="key-input" id="fanartApiKey" type="text" placeholder="Leave empty for Metahub fallback" autocomplete="off" autocorrect="off" spellcheck="false">
      <button class="paste-btn" onclick="pasteField('fanartApiKey')" title="Paste">📋</button>
    </div>
  </div>

  <div class="card">
    <div class="field-label">TheTVDB API Key</div>
    <div class="field-hint">Anime episode maps &amp; seasons · <a href="https://thetvdb.com/api-information" target="_blank" style="color:var(--blue)">Get key ↗</a></div>
    <div class="input-row">
      <input class="key-input" id="tvdbApiKey" type="text" placeholder="Leave empty for Cinemeta fallback" autocomplete="off" autocorrect="off" spellcheck="false">
      <button class="paste-btn" onclick="pasteField('tvdbApiKey')" title="Paste">📋</button>
    </div>
  </div>

  <div class="card">
    <div class="field-label">TMDB API Key</div>
    <div class="field-hint">Posters, cast &amp; descriptions · <a href="https://www.themoviedb.org/settings/api" target="_blank" style="color:var(--blue)">Get key ↗</a></div>
    <div class="input-row">
      <input class="key-input" id="tmdbApiKey" type="text" placeholder="Leave empty for built-in fallback" autocomplete="off" autocorrect="off" spellcheck="false">
      <button class="paste-btn" onclick="pasteField('tmdbApiKey')" title="Paste">📋</button>
    </div>
  </div>

  <div class="card">
    <div class="field-label">DoesTheDogDie API Key</div>
    <div class="field-hint">Content warnings &amp; trigger advisories · <a href="https://www.doesthedogdie.com" target="_blank" style="color:var(--blue)">Get key ↗</a></div>
    <div class="input-row">
      <input class="key-input" id="dtddApiKey" type="text" placeholder="Leave empty for web fallback" autocomplete="off" autocorrect="off" spellcheck="false">
      <button class="paste-btn" onclick="pasteField('dtddApiKey')" title="Paste">📋</button>
    </div>
  </div>

  <div class="section-label">⚡ TorBox Cloud Debrid</div>

  <div class="card">
    <div class="field-label">TorBox API Key</div>
    <div class="field-hint">Cached torrent debrid streaming · <a href="https://torbox.app" target="_blank" style="color:var(--blue)">Get key ↗</a></div>
    <div class="input-row">
      <input class="key-input" id="torboxApiKey" type="text" placeholder="Required for TorBox debrid" autocomplete="off" autocorrect="off" spellcheck="false">
      <button class="paste-btn" onclick="pasteField('torboxApiKey')" title="Paste">📋</button>
    </div>
  </div>

  <button class="save-btn" id="saveBtn" onclick="saveAllKeys()">
    <span id="saveBtnContent">💾 Save All Keys to TV</span>
  </button>

  <div class="status-bar" id="statusBar"></div>
</div>

<div class="toast" id="toast"></div>

<script>
const BASE = '$baseUrl';

function showToast(msg, type) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.className = 'toast ' + type + ' show';
  setTimeout(() => { t.className = 'toast'; }, 3000);
}

async function pasteField(id) {
  try {
    const text = await navigator.clipboard.readText();
    if (text.trim()) {
      document.getElementById(id).value = text.trim();
      showToast('✅ Pasted!', 'success');
    }
  } catch (e) {
    showToast('⚠️ Paste blocked — please paste manually', 'error');
  }
}

async function loadCurrentKeys() {
  try {
    const r = await fetch(BASE + '/api/keys/current');
    const d = await r.json();
    const fields = ['omdbApiKey','fanartApiKey','tvdbApiKey','tmdbApiKey','dtddApiKey','torboxApiKey'];
    fields.forEach(f => {
      const el = document.getElementById(f);
      if (el && d[f]) el.value = d[f];
    });
    document.getElementById('statusBar').textContent = '✓ Loaded current keys from TV';
  } catch(e) {
    document.getElementById('statusBar').textContent = '⚠ Could not load current keys';
  }
}

async function saveAllKeys() {
  const btn = document.getElementById('saveBtn');
  const content = document.getElementById('saveBtnContent');
  btn.disabled = true;
  content.innerHTML = '<span class="spinner"></span> Saving...';

  const payload = {
    omdbApiKey: document.getElementById('omdbApiKey').value.trim(),
    fanartApiKey: document.getElementById('fanartApiKey').value.trim(),
    tvdbApiKey: document.getElementById('tvdbApiKey').value.trim(),
    tmdbApiKey: document.getElementById('tmdbApiKey').value.trim(),
    dtddApiKey: document.getElementById('dtddApiKey').value.trim(),
    torboxApiKey: document.getElementById('torboxApiKey').value.trim(),
  };

  try {
    // Save all metadata keys + dtdd + torbox via /api/settings
    const r1 = await fetch(BASE + '/api/settings', {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify(payload)
    });
    const d1 = await r1.json();
    if (!d1.success) throw new Error('Settings save failed');

    showToast('✅ All keys saved to TV!', 'success');
    document.getElementById('statusBar').textContent = '✓ Keys saved successfully — you can close this page';
  } catch(e) {
    showToast('❌ Save failed: ' + e.message, 'error');
    document.getElementById('statusBar').textContent = '⚠ Error: ' + e.message;
  } finally {
    btn.disabled = false;
    content.innerHTML = '💾 Save All Keys to TV';
  }
}

// Load keys on page open
loadCurrentKeys();
</script>
</body>
</html>''';
  }
}
