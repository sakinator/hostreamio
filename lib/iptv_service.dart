import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'config.dart';

class IptvChannel {
  final String id;
  final String name;
  final String logo;
  final String category;
  final String country;
  final String url;
  final String source;
  final Map<String, String>? headers;

  IptvChannel({
    required this.id,
    required this.name,
    required this.logo,
    required this.category,
    required this.country,
    required this.url,
    this.source = 'IPTV-Org',
    this.headers,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'logo': logo,
        'category': category,
        'country': country,
        'url': url,
        'source': source,
        if (headers != null && headers!.isNotEmpty) 'headers': headers,
      };

  factory IptvChannel.fromJson(Map<String, dynamic> j) => IptvChannel(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        logo: j['logo']?.toString() ?? '',
        category: j['category']?.toString() ?? 'General',
        country: j['country']?.toString() ?? 'Global',
        url: j['url']?.toString() ?? '',
        source: j['source']?.toString() ?? 'IPTV-Org',
        headers: j['headers'] is Map
            ? (j['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()))
            : null,
      );

  /// Resolves playable stream URL. If stream requires headers (Referer, User-Agent, Origin),
  /// routes through local proxy to eliminate player CORS/header restrictions.
  String getStreamUrl({String? localBaseUrl}) {
    if (headers != null && headers!.isNotEmpty && localBaseUrl != null && localBaseUrl.isNotEmpty) {
      final encodedUrl = Uri.encodeComponent(url);
      final encodedHeaders = Uri.encodeComponent(jsonEncode(headers));
      return '$localBaseUrl/proxy?url=$encodedUrl&headers=$encodedHeaders';
    }
    return url;
  }
}

/// IptvService: Loads, parses, caches, and filters global live broadcast streams
/// across multiple sources (IPTV-Org, Pluto TV, Samsung TV Plus, and Custom user M3U feeds).
///
/// Features:
/// - URL-keyed deduplication: Identical channel names from different IPs/sources/servers are retained as mirrors!
/// - Pluto TV & Samsung TV Plus 1080p high-speed legal FAST channel ingestion.
/// - Custom user M3U/M3U8 playlist subscription and local caching.
/// - Header injection via local proxy for referer-gated live streams.
class IptvService {
  static final IptvService instance = IptvService._();
  IptvService._();

  static const String _m3uUrl = 'https://iptv-org.github.io/iptv/index.category.m3u';
  static const String _indiaM3uUrl = 'https://iptv-org.github.io/iptv/countries/in.m3u';
  static const String _plutoM3uUrl = 'https://raw.githubusercontent.com/dtankdempse/pluto-tv-m3u/refs/heads/main/pluto-tv.m3u';
  static const String _samsungM3uUrl = 'https://raw.githubusercontent.com/dtankdempse/samsung-tv-plus-m3u/refs/heads/main/samsung-tv-plus.m3u';
  static final File _cacheFile = File('data/iptv_cache.json');

  List<IptvChannel> _channels = [];
  DateTime? _lastLoaded;
  bool _isLoading = false;

  List<IptvChannel> get allChannels => _channels;

  Completer<void>? _loadCompleter;

  /// Loads channels from memory, local cache, or remote M3U feeds.
  Future<List<IptvChannel>> loadChannels({bool forceRefresh = false}) async {
    if (!forceRefresh && _channels.isNotEmpty && _lastLoaded != null) {
      if (DateTime.now().difference(_lastLoaded!).inHours < 12) {
        return _channels;
      }
    }

    if (_isLoading) {
      await _loadCompleter?.future;
      return _channels;
    }

    _isLoading = true;
    _loadCompleter = Completer<void>();
    try {
      // 1. Try reading local cache file if fresh (< 24h)
      if (!forceRefresh && await _cacheFile.exists()) {
        try {
          final content = await _cacheFile.readAsString();
          final list = jsonDecode(content) as List;
          _channels = list.map((e) => IptvChannel.fromJson(e as Map<String, dynamic>)).toList();
          _lastLoaded = DateTime.now();
          if (_channels.isNotEmpty) {
            _isLoading = false;
            // Background refresh if older than 12 hours
            final modified = await _cacheFile.lastModified();
            if (DateTime.now().difference(modified).inHours >= 12) {
              unawaited(_fetchRemoteM3u());
            }
            return _channels;
          }
        } catch (_) {}
      }

      // 2. Fetch from remote M3U feeds
      await _fetchRemoteM3u();
    } finally {
      _isLoading = false;
      _loadCompleter?.complete();
      _loadCompleter = null;
    }

    return _channels;
  }

  Future<void> _fetchRemoteM3u() async {
    // We de-duplicate strictly by normalized stream URL so that the same channel name/id
    // from different IPs, CDNs, or providers is preserved as playable alternative mirrors!
    final Map<String, IptvChannel> channelMap = {};

    void mergeChannels(List<IptvChannel> incoming) {
      for (final ch in incoming) {
        final urlKey = ch.url.trim().toLowerCase();
        if (urlKey.isEmpty) continue;
        if (!channelMap.containsKey(urlKey)) {
          channelMap[urlKey] = ch;
        }
      }
    }

    // 1. Dedicated India Playlist (738+ high-speed Indian regional live channels)
    try {
      final inRes = await http.get(Uri.parse(_indiaM3uUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Hostreamio/1.0.0',
      }).timeout(const Duration(seconds: 15));
      if (inRes.statusCode == 200) {
        final inChannels = parseM3u(inRes.body, defaultCountry: 'IN', defaultSource: 'IPTV-Org India');
        mergeChannels(inChannels);
        print('[IptvService] Loaded ${inChannels.length} Indian live channels from iptv-org.');
      }
    } catch (e) {
      print('[IptvService] India M3U fetch error: $e');
    }

    // 2. Pluto TV High-Definition FAST Channels (Legal 1080p US/Global live feeds)
    try {
      final plutoRes = await http.get(Uri.parse(_plutoM3uUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Hostreamio/1.0.0',
      }).timeout(const Duration(seconds: 15));
      if (plutoRes.statusCode == 200) {
        final plutoChannels = parseM3u(plutoRes.body, defaultCountry: 'US', defaultSource: 'Pluto TV');
        mergeChannels(plutoChannels);
        print('[IptvService] Loaded ${plutoChannels.length} FAST channels from Pluto TV.');
      }
    } catch (e) {
      print('[IptvService] Pluto TV M3U fetch error: $e');
    }

    // 3. Samsung TV Plus High-Definition FAST Channels (Legal 1080p feeds)
    try {
      final samsungRes = await http.get(Uri.parse(_samsungM3uUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Hostreamio/1.0.0',
      }).timeout(const Duration(seconds: 15));
      if (samsungRes.statusCode == 200) {
        final samsungChannels = parseM3u(samsungRes.body, defaultCountry: 'US', defaultSource: 'Samsung TV+');
        mergeChannels(samsungChannels);
        print('[IptvService] Loaded ${samsungChannels.length} FAST channels from Samsung TV Plus.');
      }
    } catch (e) {
      print('[IptvService] Samsung TV Plus M3U fetch error: $e');
    }

    // 4. Custom User M3U Playlists from AddonConfig
    final customUrls = AddonConfig.instance.customM3uUrls;
    for (int i = 0; i < customUrls.length; i++) {
      final url = customUrls[i];
      try {
        String body = '';
        if (url.startsWith('http://') || url.startsWith('https://')) {
          final res = await http.get(Uri.parse(url), headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Hostreamio/1.0.0',
          }).timeout(const Duration(seconds: 15));
          if (res.statusCode == 200) body = res.body;
        } else {
          final file = File(url.replaceFirst('file://', ''));
          if (await file.exists()) {
            body = await file.readAsString();
          }
        }
        if (body.isNotEmpty) {
          final customChannels = parseM3u(body, defaultCountry: 'Custom', defaultSource: 'Custom #${i + 1}');
          mergeChannels(customChannels);
          print('[IptvService] Loaded ${customChannels.length} channels from custom feed: $url');
        }
      } catch (e) {
        print('[IptvService] Custom M3U fetch error for $url: $e');
      }
    }

    // 5. Global Category Playlist (Worldwide channels)
    try {
      final res = await http.get(Uri.parse(_m3uUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Hostreamio/1.0.0',
      }).timeout(const Duration(seconds: 20));

      if (res.statusCode == 200) {
        final parsed = parseM3u(res.body, defaultSource: 'IPTV-Org Global');
        mergeChannels(parsed);
        print('[IptvService] Total unified channels loaded: ${channelMap.length}.');
      }
    } catch (e) {
      print('[IptvService] Remote global M3U fetch error: $e');
    }

    if (channelMap.isNotEmpty) {
      _channels = channelMap.values.toList();
      _lastLoaded = DateTime.now();
      try {
        if (!_cacheFile.parent.existsSync()) {
          _cacheFile.parent.createSync(recursive: true);
        }
        final jsonStr = jsonEncode(_channels.map((c) => c.toJson()).toList());
        await _cacheFile.writeAsString(jsonStr, flush: true);
      } catch (_) {}
    } else if (_channels.isEmpty) {
      _channels = _getFallbackChannels();
    }
  }

  /// Parses M3U content into structured IptvChannel objects
  static List<IptvChannel> parseM3u(
    String body, {
    String defaultCountry = 'Global',
    String defaultSource = 'IPTV-Org',
    Map<String, String>? defaultHeaders,
  }) {
    final lines = body.split('\n');
    final List<IptvChannel> list = [];

    String? currentName;
    String currentLogo = '';
    String currentCategory = 'General';
    String currentCountry = defaultCountry;
    String currentId = '';
    Map<String, String>? currentHeaders = defaultHeaders != null ? Map.from(defaultHeaders) : null;

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        final logoMatch = RegExp(r'tvg-logo="([^"]*)"').firstMatch(line);
        currentLogo = logoMatch != null ? logoMatch.group(1)! : '';

        final groupMatch = RegExp(r'group-title="([^"]*)"').firstMatch(line);
        currentCategory = groupMatch != null ? groupMatch.group(1)! : 'General';

        final idMatch = RegExp(r'tvg-id="([^"]*)"').firstMatch(line);
        currentId = idMatch != null ? idMatch.group(1)! : '';

        currentCountry = _extractCountry(currentId, line, fallback: defaultCountry);

        // Optional http-user-agent or referer in EXTINF
        final uaMatch = RegExp(r'http-user-agent="([^"]*)"').firstMatch(line);
        final refMatch = RegExp(r'http-referrer="([^"]*)"').firstMatch(line);
        if (uaMatch != null || refMatch != null) {
          currentHeaders ??= {};
          if (uaMatch != null) currentHeaders['User-Agent'] = uaMatch.group(1)!;
          if (refMatch != null) currentHeaders['Referer'] = refMatch.group(1)!;
        }

        final commaIdx = line.indexOf(',');
        if (commaIdx != -1 && commaIdx + 1 < line.length) {
          currentName = line.substring(commaIdx + 1).trim();
        } else {
          currentName = currentId.isNotEmpty ? currentId : 'Live Channel';
        }
      } else if (line.startsWith('#EXTVLCOPT:')) {
        // Parse VLC options for headers e.g. #EXTVLCOPT:http-referrer=https://example.com
        if (line.contains('http-referrer=')) {
          final ref = line.split('http-referrer=').last.trim();
          currentHeaders ??= {};
          currentHeaders['Referer'] = ref;
        }
        if (line.contains('http-user-agent=')) {
          final ua = line.split('http-user-agent=').last.trim();
          currentHeaders ??= {};
          currentHeaders['User-Agent'] = ua;
        }
      } else if (!line.startsWith('#') && line.startsWith('http')) {
        if (currentName != null && currentName.isNotEmpty) {
          list.add(IptvChannel(
            id: currentId.isNotEmpty ? currentId : 'ch_${list.length}',
            name: currentName,
            logo: currentLogo,
            category: currentCategory,
            country: currentCountry,
            url: line,
            source: defaultSource,
            headers: currentHeaders,
          ));
        }
        currentName = null;
        currentLogo = '';
        currentCategory = 'General';
        currentCountry = defaultCountry;
        currentId = '';
        currentHeaders = defaultHeaders != null ? Map.from(defaultHeaders) : null;
      }
    }

    return list;
  }

  static String _extractCountry(String tvgId, String extInfLine, {String fallback = 'Global'}) {
    final lowerId = tvgId.toLowerCase();
    final lowerLine = extInfLine.toLowerCase();
    if (lowerId.contains('.in@') || lowerId.endsWith('.in') || lowerId.contains('@in') || lowerId.contains('@india') || lowerLine.contains('country="in"') || lowerLine.contains('tvg-country="in"') || lowerLine.contains('(india)') || lowerLine.contains(' india') || lowerLine.contains('[india]') || lowerLine.contains('hindi') || lowerLine.contains('tamil') || lowerLine.contains('telugu') || lowerLine.contains('malayalam') || lowerLine.contains('kannada') || lowerLine.contains('bengali') || lowerLine.contains('marathi') || lowerLine.contains('punjabi')) return 'IN';
    if (lowerId.contains('.us@') || lowerId.endsWith('.us') || lowerLine.contains('country="us"') || lowerLine.contains('tvg-country="us"')) return 'US';
    if (lowerId.contains('.uk@') || lowerId.endsWith('.uk') || lowerId.contains('.gb@') || lowerLine.contains('country="uk"') || lowerLine.contains('country="gb"')) return 'UK';
    if (lowerId.contains('.ca@') || lowerId.endsWith('.ca') || lowerLine.contains('country="ca"')) return 'CA';
    if (lowerId.contains('.fr@') || lowerId.endsWith('.fr') || lowerLine.contains('country="fr"')) return 'FR';
    if (lowerId.contains('.de@') || lowerId.endsWith('.de') || lowerLine.contains('country="de"')) return 'DE';
    if (lowerId.contains('.es@') || lowerId.endsWith('.es') || lowerLine.contains('country="es"')) return 'ES';
    if (lowerId.contains('.it@') || lowerId.endsWith('.it') || lowerLine.contains('country="it"')) return 'IT';
    if (lowerId.contains('.au@') || lowerId.endsWith('.au') || lowerLine.contains('country="au"')) return 'AU';
    if (lowerId.contains('.jp@') || lowerId.endsWith('.jp') || lowerLine.contains('country="jp"')) return 'JP';
    if (lowerId.contains('.br@') || lowerId.endsWith('.br') || lowerLine.contains('country="br"')) return 'BR';
    if (lowerId.contains('.mx@') || lowerId.endsWith('.mx') || lowerLine.contains('country="mx"')) return 'MX';
    if (lowerId.contains('.kr@') || lowerId.endsWith('.kr') || lowerLine.contains('country="kr"')) return 'KR';
    if (lowerId.contains('.ru@') || lowerId.endsWith('.ru') || lowerLine.contains('country="ru"')) return 'RU';
    if (lowerId.contains('.tr@') || lowerId.endsWith('.tr') || lowerLine.contains('country="tr"')) return 'TR';
    if (lowerId.contains('.ae@') || lowerId.endsWith('.ae') || lowerLine.contains('country="ae"')) return 'AE';
    if (lowerId.contains('.pk@') || lowerId.endsWith('.pk') || lowerLine.contains('country="pk"')) return 'PK';
    if (lowerId.contains('.bd@') || lowerId.endsWith('.bd') || lowerLine.contains('country="bd"')) return 'BD';
    if (lowerId.contains('.nl@') || lowerId.endsWith('.nl') || lowerLine.contains('country="nl"')) return 'NL';
    return fallback;
  }

  /// Filters channels in memory by search query, category, country, and source
  List<IptvChannel> filterChannels({
    String? search,
    String? category,
    String? country,
    String? source,
  }) {
    final query = (search ?? '').toLowerCase().trim();
    final cat = (category ?? 'All').toLowerCase();
    final ctry = (country ?? 'All').toUpperCase();
    final src = (source ?? 'All').toLowerCase();

    return _channels.where((c) {
      if (cat != 'all' && !c.category.toLowerCase().contains(cat)) {
        return false;
      }
      if (ctry != 'ALL' && c.country.toUpperCase() != ctry) {
        return false;
      }
      if (src != 'all' && !c.source.toLowerCase().contains(src)) {
        return false;
      }
      if (query.isNotEmpty) {
        final matchesName = c.name.toLowerCase().contains(query);
        final matchesCategory = c.category.toLowerCase().contains(query);
        final matchesCountry = c.country.toLowerCase().contains(query);
        final matchesSource = c.source.toLowerCase().contains(query);
        if (!matchesName && !matchesCategory && !matchesCountry && !matchesSource) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  /// Finds first channel matching ID
  Future<IptvChannel?> getChannelById(String id) async {
    await loadChannels();
    for (final c in _channels) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Finds all available channel feeds/mirrors matching ID or Name (case-insensitive)
  /// Enables multiple IP feeds or mirrors from different sources for the same channel.
  Future<List<IptvChannel>> getChannelsByIdOrName(String query) async {
    await loadChannels();
    final clean = query.toLowerCase().trim();
    final List<IptvChannel> matches = [];

    // Exact ID match first
    for (final c in _channels) {
      if (c.id.toLowerCase() == clean) matches.add(c);
    }

    // Name match
    if (matches.isEmpty) {
      for (final c in _channels) {
        if (c.name.toLowerCase() == clean) matches.add(c);
      }
    }

    // Partial contains match if still empty
    if (matches.isEmpty) {
      for (final c in _channels) {
        if (c.name.toLowerCase().contains(clean) || c.id.toLowerCase().contains(clean)) {
          matches.add(c);
        }
      }
    }

    return matches;
  }

  /// Returns all alternative mirrors/servers for the given channel
  Future<List<IptvChannel>> getMirrors(IptvChannel channel) async {
    await loadChannels();
    final cleanName = channel.name.toLowerCase().trim();
    return _channels.where((c) => c.name.toLowerCase().trim() == cleanName && c.url != channel.url).toList();
  }

  /// Adds a custom user M3U URL and reloads channels
  Future<void> addCustomM3uUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    final cfg = AddonConfig.instance;
    if (!cfg.customM3uUrls.contains(trimmed)) {
      cfg.customM3uUrls.add(trimmed);
      cfg.scheduleSave();
      await loadChannels(forceRefresh: true);
    }
  }

  /// Removes a custom M3U URL and reloads channels
  Future<void> removeCustomM3uUrl(String url) async {
    final cfg = AddonConfig.instance;
    if (cfg.customM3uUrls.remove(url.trim())) {
      cfg.scheduleSave();
      await loadChannels(forceRefresh: true);
    }
  }

  /// Built-in high-availability fallback channels (News, Sports, Entertainment)
  List<IptvChannel> _getFallbackChannels() {
    return [
      IptvChannel(
        id: 'sky_news_uk',
        name: 'Sky News (UK)',
        logo: 'https://i.imgur.com/7bK7QYI.png',
        category: 'News',
        country: 'UK',
        source: 'IPTV-Org Fallback',
        url: 'https://linear417-gb-dash1-prd-cf.cdn.sky.com/17404/SkyNews_G8_HD.isml/SkyNews_G8_HD.m3u8',
      ),
      IptvChannel(
        id: 'al_jazeera_eng',
        name: 'Al Jazeera English',
        logo: 'https://i.imgur.com/rN9kZgM.png',
        category: 'News',
        country: 'Global',
        source: 'IPTV-Org Fallback',
        url: 'https://live-hls-web-aje.getaj.net/AJE/03.m3u8',
      ),
      IptvChannel(
        id: 'dw_english',
        name: 'DW English HD',
        logo: 'https://i.imgur.com/uR4XfVp.png',
        category: 'News',
        country: 'DE',
        source: 'IPTV-Org Fallback',
        url: 'https://dwamdstream102.akamaized.net/hls/live/2015525/dwstream102/index.m3u8',
      ),
      IptvChannel(
        id: 'france24_en',
        name: 'France 24 English',
        logo: 'https://i.imgur.com/h5T2Jsl.png',
        category: 'News',
        country: 'FR',
        source: 'IPTV-Org Fallback',
        url: 'https://static.france24.com/live/F24_EN_LO_HLS/live_tv.m3u8',
      ),
      IptvChannel(
        id: 'redbull_tv',
        name: 'Red Bull TV Sports & Adventure',
        logo: 'https://i.imgur.com/B7sXW8D.png',
        category: 'Sports',
        country: 'Global',
        source: 'IPTV-Org Fallback',
        url: 'https://rbmn-live.akamaized.net/hls/live/590964/BoRB-AT/master.m3u8',
      ),
      IptvChannel(
        id: 'ndtv_24x7',
        name: 'NDTV 24x7 India',
        logo: 'https://i.imgur.com/9C3iKeq.png',
        category: 'News',
        country: 'IN',
        source: 'IPTV-Org Fallback',
        url: 'https://ndtv24x7elemadmin.akamaized.net/hls/live/2003678/ndtv24x7/ndtv24x7master.m3u8',
      ),
      IptvChannel(
        id: 'nasa_tv',
        name: 'NASA TV HD',
        logo: 'https://i.imgur.com/X2f8V5t.png',
        category: 'Documentary',
        country: 'US',
        source: 'IPTV-Org Fallback',
        url: 'https://ntv1.akamaized.net/hls/live/2014075/NASA-NTV1-HLS/master.m3u8',
      ),
    ];
  }
}
