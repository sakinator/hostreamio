import 'dart:async';
import 'dart:convert';
import 'dart:io';

class AddonConfig {
  static final AddonConfig instance = AddonConfig._();

  int port = 7000;
  String host = '0.0.0.0';
  int timeoutSeconds = 9;
  bool enableProxyForHeaders = true;
  Set<String> disabledProviders = {};
  List<String> providerOrder = [];
  bool autoCheckUpdates = true;
  String appVersion = '1.0.3';

  /// TMDB API key used by metadata_service.dart.
  /// Override in data/config.json with your own key if the default is rate-limited.
  String tmdbApiKey = 'b3556f3b206e16f82df4d1f6fd4545e6';
  String torboxApiKey = '';

  /// API 5: OMDb & IMDb Ratings API Key
  String omdbApiKey = 'b9a5e69d';

  /// API 6: Fanart.tv ClearLogo & High-Res Artwork API Key
  String fanartApiKey = '';

  /// API 4: TheTVDB API Key (Episode Mappings & Alternate Ordering)
  String tvdbApiKey = '';

  /// API 7: DoesTheDogDie Content Warnings & Trigger Advisories API Key
  String dtddApiKey = '';

  // Stream Filtering Profiles & Optimization
  bool excludeCams = true;
  String maxResolution = 'all'; // 'all', '1080p', '720p'
  String preferredLanguage = 'any'; // 'any', 'hindi', 'english', 'tamil', 'telugu', 'malayalam', 'kannada', 'bengali', 'punjabi', 'dual'
  bool enableDeduplication = true;
  bool enableDeadLinkFilter = true;
  bool enableSeekProbe = true; // CNCVerse-style Range & exact Content-Length size extraction
  bool showRatingsInStreams = false;
  bool enableOpenSubtitles = true;
  bool enableTorboxCachedTorrents = true; // By default ON (Fetch 100% TorBox cached torrents, strictly 0 P2P)
  bool enableCacheBypass = true; // Prowlarr-style Cache escape (no-cache headers + query nonce)
  bool enablePublicStreams = false; // By default OFF to prevent unverified public video/porn uploads
  String proxyResolverUrl = ''; // FlareSolverr / Proxy URL (e.g. http://localhost:8191/v1)
  String preferredSubtitleLanguage = 'en'; // 'en', 'hi', 'es', 'fr', 'de', 'ar', 'pt', 'ru', 'ja', 'all'
  String cloudflareTunnelToken = ''; // Cloudflare Tunnel token for remote HTTPS access
  bool enableCloudflareTunnel = false;
  bool enableHardwareAcceleration = true; // Native GPU / ExoPlayer HWDEC decoding on Android & DXVA/D3D11 on Windows
  String defaultPlayerEngine = 'embedded'; // 'embedded', 'vlc', 'justplayer', 'chooser'
  Map<String, int> resumePositions = {}; // id/url -> position in ms
  List<Map<String, dynamic>> watchlistItems = [];
  List<Map<String, dynamic>> watchHistoryItems = [];
  List<String> customM3uUrls = []; // Custom user M3U/M3U8 playlist URLs or file paths

  static final File _configFile = File('data/config.json');

  AddonConfig._();

  Future<void> load() async {
    try {
      if (await _configFile.exists()) {
        final content = await _configFile.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        port = map['port'] is int ? map['port'] : port;
        host = map['host']?.toString() ?? host;
        timeoutSeconds = map['timeoutSeconds'] is int ? map['timeoutSeconds'] : timeoutSeconds;
        enableProxyForHeaders = map['enableProxyForHeaders'] is bool
            ? map['enableProxyForHeaders']
            : enableProxyForHeaders;
        if (map['disabledProviders'] is List) {
          disabledProviders =
              (map['disabledProviders'] as List).map((e) => e.toString().toLowerCase()).toSet();
        }
        if (map['providerOrder'] is List) {
          providerOrder =
              (map['providerOrder'] as List).map((e) => e.toString().toLowerCase()).toList();
        }
        autoCheckUpdates =
            map['autoCheckUpdates'] is bool ? map['autoCheckUpdates'] : autoCheckUpdates;
        if (map['tmdbApiKey'] is String && (map['tmdbApiKey'] as String).isNotEmpty) {
          tmdbApiKey = map['tmdbApiKey'];
        }
        if (map['torboxApiKey'] is String) {
          torboxApiKey = map['torboxApiKey'];
        }
        if (map['omdbApiKey'] is String && (map['omdbApiKey'] as String).isNotEmpty) {
          omdbApiKey = map['omdbApiKey'];
        }
        if (map['fanartApiKey'] is String) {
          fanartApiKey = map['fanartApiKey'];
        }
        if (map['tvdbApiKey'] is String) {
          tvdbApiKey = map['tvdbApiKey'];
        }
        if (map['dtddApiKey'] is String) {
          dtddApiKey = map['dtddApiKey'];
        }
        if (map['showRatingsInStreams'] is bool) {
          showRatingsInStreams = map['showRatingsInStreams'];
        }
        if (map['excludeCams'] is bool) {
          excludeCams = map['excludeCams'];
        }
        if (map['maxResolution'] is String) {
          maxResolution = map['maxResolution'];
        }
        if (map['preferredLanguage'] is String) {
          preferredLanguage = map['preferredLanguage'];
        }
        if (map['enableDeduplication'] is bool) {
          enableDeduplication = map['enableDeduplication'];
        }
        if (map['enableDeadLinkFilter'] is bool) {
          enableDeadLinkFilter = map['enableDeadLinkFilter'];
        }
        if (map['enableSeekProbe'] is bool) {
          enableSeekProbe = map['enableSeekProbe'];
        }
        if (map['enableOpenSubtitles'] is bool) {
          enableOpenSubtitles = map['enableOpenSubtitles'];
        }
        if (map['cloudflareTunnelToken'] is String) {
          cloudflareTunnelToken = map['cloudflareTunnelToken'];
        }
        if (map['enableCloudflareTunnel'] is bool) {
          enableCloudflareTunnel = map['enableCloudflareTunnel'];
        }
        if (map['enableHardwareAcceleration'] is bool) {
          enableHardwareAcceleration = map['enableHardwareAcceleration'];
        }
        if (map['defaultPlayerEngine'] is String && (map['defaultPlayerEngine'] as String).isNotEmpty) {
          defaultPlayerEngine = map['defaultPlayerEngine'];
        }
        if (map['enableTorboxCachedTorrents'] is bool) {
          enableTorboxCachedTorrents = map['enableTorboxCachedTorrents'];
        }
        if (map['enableCacheBypass'] is bool) {
          enableCacheBypass = map['enableCacheBypass'];
        }
        if (map['enablePublicStreams'] is bool) {
          enablePublicStreams = map['enablePublicStreams'];
        }
        if (map['proxyResolverUrl'] is String) {
          proxyResolverUrl = map['proxyResolverUrl'];
        }
        if (map['preferredSubtitleLanguage'] is String && (map['preferredSubtitleLanguage'] as String).isNotEmpty) {
          preferredSubtitleLanguage = map['preferredSubtitleLanguage'];
        }
        if (map['resumePositions'] is Map) {
          final resMap = map['resumePositions'] as Map;
          resumePositions = resMap.map((k, v) => MapEntry(k.toString(), (v is num) ? v.toInt() : 0));
        }
        if (map['watchlistItems'] is List) {
          watchlistItems = (map['watchlistItems'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        if (map['watchHistoryItems'] is List) {
          watchHistoryItems = (map['watchHistoryItems'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        if (map['customM3uUrls'] is List) {
          customM3uUrls = (map['customM3uUrls'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty)
              .toList();
        }
      }
    } catch (e) {
      print('[AddonConfig] Error loading config: $e');
    }
  }

  Timer? _saveDebounceTimer;

  void scheduleSave() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      save();
    });
  }

  Future<void> save() async {
    try {
      if (!await _configFile.parent.exists()) {
        await _configFile.parent.create(recursive: true);
      }
      final data = {
        'port': port,
        'host': host,
        'timeoutSeconds': timeoutSeconds,
        'enableProxyForHeaders': enableProxyForHeaders,
        'disabledProviders': disabledProviders.toList(),
        'providerOrder': providerOrder,
        'autoCheckUpdates': autoCheckUpdates,
        'tmdbApiKey': tmdbApiKey,
        'torboxApiKey': torboxApiKey,
        'omdbApiKey': omdbApiKey,
        'fanartApiKey': fanartApiKey,
        'tvdbApiKey': tvdbApiKey,
        'dtddApiKey': dtddApiKey,
        'showRatingsInStreams': showRatingsInStreams,
        'excludeCams': excludeCams,
        'maxResolution': maxResolution,
        'preferredLanguage': preferredLanguage,
        'enableDeduplication': enableDeduplication,
        'enableDeadLinkFilter': enableDeadLinkFilter,
        'enableSeekProbe': enableSeekProbe,
        'enableOpenSubtitles': enableOpenSubtitles,
        'cloudflareTunnelToken': cloudflareTunnelToken,
        'enableCloudflareTunnel': enableCloudflareTunnel,
        'enableHardwareAcceleration': enableHardwareAcceleration,
        'defaultPlayerEngine': defaultPlayerEngine,
        'enableTorboxCachedTorrents': enableTorboxCachedTorrents,
        'enableCacheBypass': enableCacheBypass,
        'enablePublicStreams': enablePublicStreams,
        'proxyResolverUrl': proxyResolverUrl,
        'preferredSubtitleLanguage': preferredSubtitleLanguage,
        'resumePositions': resumePositions,
        'watchlistItems': watchlistItems,
        'watchHistoryItems': watchHistoryItems,
        'customM3uUrls': customM3uUrls,
      };
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final tmpFile = File('${_configFile.path}.tmp');
      await tmpFile.writeAsString(jsonStr, flush: true);
      try {
        await tmpFile.rename(_configFile.path);
      } catch (_) {
        // Fallback for Windows file lock on atomic rename
        await tmpFile.copy(_configFile.path);
        try {
          await tmpFile.delete();
        } catch (_) {}
      }
    } catch (e) {
      print('[AddonConfig] Error saving config: $e');
    }
  }

  bool isProviderEnabled(String providerId) {
    return !disabledProviders.contains(providerId.toLowerCase());
  }

  void toggleProvider(String providerId, bool enabled) {
    final id = providerId.toLowerCase();
    if (enabled) {
      disabledProviders.remove(id);
    } else {
      disabledProviders.add(id);
    }
    scheduleSave(); // debounced & non-blocking
  }
}
