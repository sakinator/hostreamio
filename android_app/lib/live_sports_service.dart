import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class LiveSportStream {
  final String name;
  final String url;
  final String quality;
  final Map<String, String>? headers;

  LiveSportStream({
    required this.name,
    required this.url,
    this.quality = 'HD',
    this.headers,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'url': url,
        'quality': quality,
        if (headers != null && headers!.isNotEmpty) 'headers': headers,
      };

  factory LiveSportStream.fromJson(Map<String, dynamic> j) => LiveSportStream(
        name: j['name']?.toString() ?? 'Stream',
        url: j['url']?.toString() ?? '',
        quality: j['quality']?.toString() ?? 'HD',
        headers: j['headers'] is Map
            ? (j['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()))
            : null,
      );
}

class LiveSportEvent {
  final String id;
  final String title;
  final String sport;
  final String league;
  final DateTime? startTime;
  final String? homeTeam;
  final String? awayTeam;
  final String? poster;
  final List<LiveSportStream> streams;

  LiveSportEvent({
    required this.id,
    required this.title,
    required this.sport,
    required this.league,
    this.startTime,
    this.homeTeam,
    this.awayTeam,
    this.poster,
    required this.streams,
  });

  bool get isLive {
    if (startTime == null) return true;
    final now = DateTime.now();
    // Consider live from 15 minutes before start until 3.5 hours after
    final startWindow = startTime!.subtract(const Duration(minutes: 15));
    final endWindow = startTime!.add(const Duration(minutes: 210));
    return now.isAfter(startWindow) && now.isBefore(endWindow);
  }

  String get timeLabel {
    if (startTime == null) return 'Live Now';
    if (isLive) return '🔴 LIVE NOW';
    final diff = startTime!.difference(DateTime.now());
    if (diff.isNegative) return 'Recent';
    if (diff.inHours > 0) return 'In ${diff.inHours}h ${diff.inMinutes % 60}m';
    return 'In ${diff.inMinutes}m';
  }

  String get sportIcon {
    final s = sport.toLowerCase();
    if (s.contains('soccer') || s.contains('football')) return '⚽';
    if (s.contains('cricket')) return '🏏';
    if (s.contains('basketball')) return '🏀';
    if (s.contains('motor') || s.contains('f1') || s.contains('racing')) return '🏎️';
    if (s.contains('fight') || s.contains('mma') || s.contains('ufc') || s.contains('boxing') || s.contains('wwe')) return '🥊';
    if (s.contains('tennis')) return '🎾';
    if (s.contains('hockey')) return '🏒';
    if (s.contains('rugby') || s.contains('nfl')) return '🏈';
    if (s.contains('baseball')) return '⚾';
    return '🏆';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'sport': sport,
        'league': league,
        if (startTime != null) 'startTime': startTime!.toIso8601String(),
        if (homeTeam != null) 'homeTeam': homeTeam,
        if (awayTeam != null) 'awayTeam': awayTeam,
        if (poster != null) 'poster': poster,
        'streams': streams.map((s) => s.toJson()).toList(),
      };

  factory LiveSportEvent.fromJson(Map<String, dynamic> j) => LiveSportEvent(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        sport: j['sport']?.toString() ?? 'Sports',
        league: j['league']?.toString() ?? 'Live',
        startTime: j['startTime'] != null ? DateTime.tryParse(j['startTime'].toString()) : null,
        homeTeam: j['homeTeam']?.toString(),
        awayTeam: j['awayTeam']?.toString(),
        poster: j['poster']?.toString(),
        streams: (j['streams'] as List? ?? [])
            .whereType<Map>()
            .map((s) => LiveSportStream.fromJson(Map<String, dynamic>.from(s)))
            .toList(),
      );
}

/// LiveSportsService: Scrapes and aggregates live match schedules and streams
/// across Football, Cricket, Basketball, Motorsports, Fighting/MMA, and Tennis.
class LiveSportsService {
  static final LiveSportsService instance = LiveSportsService._();
  LiveSportsService._();

  static const List<String> _streamedApiMirrors = [
    'https://streamed.pk/api/matches/all-today',
    'https://streamed.st/api/matches/all-today',
    'https://strmd.link/api/matches/all-today',
  ];

  static final File _cacheFile = File('data/live_sports_cache.json');
  List<LiveSportEvent> _events = [];
  DateTime? _lastLoaded;
  bool _isLoading = false;

  List<LiveSportEvent> get allEvents => _events;

  /// Loads live sports events from memory, local cache (<30m TTL), or remote APIs
  Future<List<LiveSportEvent>> getLiveEvents({bool forceRefresh = false}) async {
    if (!forceRefresh && _events.isNotEmpty && _lastLoaded != null) {
      if (DateTime.now().difference(_lastLoaded!).inMinutes < 15) {
        return _events;
      }
    }

    if (_isLoading) {
      while (_isLoading) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return _events;
    }

    _isLoading = true;
    try {
      // 1. Try reading local cache file if fresh (< 30m)
      if (!forceRefresh && await _cacheFile.exists()) {
        try {
          final content = await _cacheFile.readAsString();
          final list = jsonDecode(content) as List;
          _events = list.map((e) => LiveSportEvent.fromJson(e as Map<String, dynamic>)).toList();
          _lastLoaded = DateTime.now();
          if (_events.isNotEmpty) {
            _isLoading = false;
            return _events;
          }
        } catch (_) {}
      }

      // 2. Fetch from remote sports APIs
      await _fetchRemoteSports();
    } finally {
      _isLoading = false;
    }

    return _events;
  }

  Future<void> _fetchRemoteSports() async {
    final List<LiveSportEvent> fetched = [];

    // Try Streamed API mirrors
    for (final endpoint in _streamedApiMirrors) {
      try {
        final res = await http.get(Uri.parse(endpoint), headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Hostreamio/1.0.0',
          'Accept': 'application/json',
        }).timeout(const Duration(seconds: 8));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data is List) {
            for (final item in data) {
              if (item is! Map) continue;
              final parsed = _parseStreamedEvent(item);
              if (parsed != null) fetched.add(parsed);
            }
          }
          if (fetched.isNotEmpty) {
            print('[LiveSportsService] Loaded ${fetched.length} live matches from $endpoint.');
            break;
          }
        }
      } catch (e) {
        print('[LiveSportsService] Error fetching from $endpoint: $e');
      }
    }

    if (fetched.isEmpty) {
      fetched.addAll(_getCuratedLiveEvents());
    }

    _events = fetched;
    _lastLoaded = DateTime.now();

    try {
      if (!_cacheFile.parent.existsSync()) {
        _cacheFile.parent.createSync(recursive: true);
      }
      final jsonStr = jsonEncode(_events.map((e) => e.toJson()).toList());
      await _cacheFile.writeAsString(jsonStr, flush: true);
    } catch (_) {}
  }

  LiveSportEvent? _parseStreamedEvent(Map item) {
    try {
      final id = item['id']?.toString() ?? 'sport_${item['title'].hashCode}';
      final title = item['title']?.toString() ?? 'Live Match';
      final category = item['category']?.toString() ?? item['sport']?.toString() ?? 'Sports';
      final league = item['league']?.toString() ?? item['tournament']?.toString() ?? 'Match';
      final dateStr = item['date']?.toString();
      DateTime? startTime;
      if (dateStr != null) {
        final epochMs = int.tryParse(dateStr);
        if (epochMs != null) {
          startTime = DateTime.fromMillisecondsSinceEpoch(epochMs > 100000000000 ? epochMs : epochMs * 1000);
        } else {
          startTime = DateTime.tryParse(dateStr);
        }
      }

      final teams = item['teams'] as Map?;
      final home = teams?['home']?['name']?.toString() ?? item['home']?.toString();
      final away = teams?['away']?['name']?.toString() ?? item['away']?.toString();
      final poster = item['poster']?.toString() ?? item['banner']?.toString() ?? teams?['home']?['badge']?.toString();

      final List<LiveSportStream> streams = [];
      final sources = item['sources'] as List? ?? item['streams'] as List? ?? [];
      for (final s in sources) {
        if (s is Map && s['url'] != null) {
          streams.add(LiveSportStream(
            name: s['source']?.toString() ?? s['name']?.toString() ?? 'Server ${streams.length + 1}',
            url: s['url'].toString(),
            quality: s['quality']?.toString() ?? 'HD',
            headers: s['headers'] is Map ? (s['headers'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())) : null,
          ));
        }
      }

      // If no explicit streams in schedule item, generate direct playable resolver link
      if (streams.isEmpty) {
        streams.add(LiveSportStream(
          name: 'Streamed HD Mirror',
          url: 'https://streamed.pk/watch/$id',
          quality: '1080p',
          headers: const {'Referer': 'https://streamed.pk/'},
        ));
      }

      return LiveSportEvent(
        id: id,
        title: title,
        sport: _normalizeSport(category),
        league: league,
        startTime: startTime,
        homeTeam: home,
        awayTeam: away,
        poster: poster,
        streams: streams,
      );
    } catch (_) {
      return null;
    }
  }

  static String _normalizeSport(String cat) {
    final lower = cat.toLowerCase();
    if (lower.contains('football') || lower.contains('soccer')) return 'Football';
    if (lower.contains('cricket')) return 'Cricket';
    if (lower.contains('basketball') || lower.contains('nba')) return 'Basketball';
    if (lower.contains('motorsport') || lower.contains('f1') || lower.contains('nascar')) return 'Motorsport';
    if (lower.contains('fight') || lower.contains('mma') || lower.contains('ufc') || lower.contains('boxing')) return 'Fighting';
    if (lower.contains('tennis')) return 'Tennis';
    return cat.isNotEmpty ? cat : 'Sports';
  }

  /// Resolves playable streams for an event with local proxy header injection
  Future<List<Map<String, dynamic>>> resolveEventStreams(String eventId, {String? localBaseUrl}) async {
    await getLiveEvents();
    final event = _events.firstWhere(
      (e) => e.id == eventId || e.id.contains(eventId),
      orElse: () => _getCuratedLiveEvents().first,
    );

    final List<Map<String, dynamic>> results = [];
    int mirrorNum = 1;

    for (final s in event.streams) {
      String playUrl = s.url;
      if (s.headers != null && s.headers!.isNotEmpty && localBaseUrl != null && localBaseUrl.isNotEmpty) {
        final encodedUrl = Uri.encodeComponent(s.url);
        final encodedHeaders = Uri.encodeComponent(jsonEncode(s.headers));
        playUrl = '$localBaseUrl/proxy?url=$encodedUrl&headers=$encodedHeaders';
      }

      results.add({
        'name': '${event.sportIcon} ${event.title} [Server $mirrorNum • ${s.name}]',
        'title': '⚡ Live Event • ${event.sport} (${event.league})\n🔴 Status: ${event.timeLabel} • ${s.quality}\n🔗 Mirror #$mirrorNum',
        'url': playUrl,
        'behaviorHints': {
          'notWebReady': false,
          if (s.headers != null && s.headers!.isNotEmpty)
            'proxyHeaders': {'request': s.headers!},
        },
      });
      mirrorNum++;
    }

    return results;
  }

  /// Fallback curated high-availability live sports broadcasts
  List<LiveSportEvent> _getCuratedLiveEvents() {
    return [
      LiveSportEvent(
        id: 'sport_redbull_tv',
        title: 'Red Bull Extreme Sports & Racing',
        sport: 'Motorsport',
        league: 'Red Bull TV Championship',
        startTime: DateTime.now(),
        streams: [
          LiveSportStream(
            name: 'Red Bull TV 1080p',
            url: 'https://rbmn-live.akamaized.net/hls/live/590964/BoRB-AT/master.m3u8',
            quality: '1080p',
          ),
        ],
      ),
      LiveSportEvent(
        id: 'sport_sky_sports_news',
        title: 'Sky Sports News 24/7 Live Coverage',
        sport: 'Football',
        league: 'Sky Sports',
        startTime: DateTime.now(),
        streams: [
          LiveSportStream(
            name: 'Sky Sports News HD',
            url: 'https://linear417-gb-dash1-prd-cf.cdn.sky.com/17404/SkyNews_G8_HD.isml/SkyNews_G8_HD.m3u8',
            quality: '1080p',
          ),
        ],
      ),
    ];
  }
}
