import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'config.dart';
import 'omdb_service.dart';
import 'torbox_service.dart';
import 'iptv_service.dart';

class CatalogService {
  static final CatalogService instance = CatalogService._();

  CatalogService._();

  // Invidious public instances with automatic fallback
  static const List<String> _invidiousInstances = [
    'https://invidious.projectsegfau.lt',
    'https://inv.nadeko.net',
    'https://invidious.nerdvpn.de',
    'https://vid.puffyan.us',
    'https://inv.tux.pizza',
  ];

  static final Map<String, dynamic> _cache = {};
  static final Map<String, Map<String, dynamic>> _enrichmentCache = {};
  static final Map<String, Map<String, dynamic>> dynamicShortDramas = {};

  static const Set<String> _nsfwKeywords = {
    'porn',
    'xxx',
    'nude',
    'nsfw',
    'erotica',
    'erotic',
    'sex',
    'fetish',
    'felicia',
    'bikini',
    'swimsuit',
    'lingerie',
    'softcore',
    'hardcore',
    'naked',
    'playboy',
    'hentai',
    'camgirl',
    'onlyfans',
    'pussy',
    'boobs',
    'penis',
    'blowjob',
    'milf',
    'masturbat',
    'incest',
    'threesome',
    'gangbang',
    'bhabhi',
    'sensual',
    'seduction',
    'adultcdroms',
  };

  /// Returns true if any text contains adult/NSFW terminology or collections
  static bool isNsfwContent(String? text) {
    if (text == null || text.isEmpty) return false;
    final lower = text.toLowerCase();
    for (final kw in _nsfwKeywords) {
      if (lower.contains(kw)) return true;
    }
    return false;
  }

  /// Verifies that candidateTitle strictly matches targetTitle (no loose substrings, verified year)
  static bool isStrictTitleMatch({
    required String targetTitle,
    required String candidateTitle,
    int? targetYear,
    int? candidateYear,
  }) {
    if (targetTitle.trim().isEmpty || candidateTitle.trim().isEmpty) return false;

    // Check year if both are present: must be within +/- 1 year
    if (targetYear != null && candidateYear != null) {
      if ((targetYear - candidateYear).abs() > 1) return false;
    }

    final cleanT = targetTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final cleanC = candidateTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    if (cleanT == cleanC) return true;

    final wordsT = cleanT.split(' ').where((w) => w.length > 1).toSet();
    final wordsC = cleanC.split(' ').where((w) => w.length > 1).toSet();

    if (wordsT.isEmpty || wordsC.isEmpty) return false;

    // All meaningful words of targetTitle MUST be present in candidateTitle
    if (!wordsT.every((w) => wordsC.contains(w))) return false;

    // Disallow candidates with extraneous irrelevant words (compilations, unrelated titles, adult variants)
    final extraWords = wordsC.difference(wordsT);
    const allowedExtras = {'full', 'movie', 'film', 'hd', '1080p', '720p', '4k', 'uhd', 'hindi', 'english', 'dubbed', 'subtitles', 'official', 'the', 'a', 'an'};
    final badExtras = extraWords.where((w) => !allowedExtras.contains(w) && !RegExp(r'^(19\d\d|20\d\d)$').hasMatch(w));

    return badExtras.isEmpty;
  }

  /// Returns catalog specifications for manifest.json
  static List<Map<String, dynamic>> getCatalogs() {
    return [
      {
        'type': 'movie',
        'id': 'yt_indian',
        'name': 'YouTube Indian Cinema',
        'posterShape': 'poster',
        'extra': [
          {'name': 'search', 'isRequired': false},
          {
            'name': 'genre',
            'options': [
              'All',
              'Bollywood Full Movies',
              'South Hindi Dubbed',
              'Indian Web Series',
              'Classic Hindi',
              'Comedy Hindi Movies',
            ],
            'isRequired': false,
          },
          {'name': 'skip', 'isRequired': false},
        ],
      },
      {
        'type': 'movie',
        'id': 'yt_international',
        'name': 'YouTube International',
        'posterShape': 'poster',
        'extra': [
          {'name': 'search', 'isRequired': false},
          {
            'name': 'genre',
            'options': [
              'All',
              'Action Movies',
              'Sci-Fi & Thriller',
              'Documentaries',
              'Indie Cinema',
            ],
            'isRequired': false,
          },
          {'name': 'skip', 'isRequired': false},
        ],
      },
      {
        'type': 'movie',
        'id': 'vimeo_picks',
        'name': 'Vimeo Staff Picks & Shorts',
        'posterShape': 'poster',
        'extra': [
          {'name': 'search', 'isRequired': false},
          {
            'name': 'genre',
            'options': [
              'All',
              'Staff Picks',
              'Short of the Week',
              'Animation',
              'Documentaries',
            ],
            'isRequired': false,
          },
          {'name': 'skip', 'isRequired': false},
        ],
      },
      {
        'type': 'movie',
        'id': 'archive_movies',
        'name': 'Internet Archive Movies',
        'posterShape': 'poster',
        'extra': [
          {'name': 'search', 'isRequired': false},
          {
            'name': 'genre',
            'options': [
              'All',
              'Indian Classics',
              'Golden Era Hollywood',
              'Film Noir',
              'Sci-Fi & Horror',
              'Silent Era',
            ],
            'isRequired': false,
          },
          {'name': 'skip', 'isRequired': false},
        ],
      },
      {
        'type': 'movie',
        'id': 'hindi_movies',
        'name': '🇮🇳 Hindi Movies',
        'posterShape': 'poster',
        'extra': [
          {'name': 'search', 'isRequired': false},
          {
            'name': 'genre',
            'options': [
              'All',
              'Bollywood Blockbusters',
              'Action & Thriller',
              'Comedy & Family',
              'Romance & Drama',
              'South Hindi Dubbed',
              'Classic Bollywood',
            ],
            'isRequired': false,
          },
          {'name': 'skip', 'isRequired': false},
        ],
      },
      {
        'type': 'series',
        'id': 'hindi_series',
        'name': '🇮🇳 Hindi Series',
        'posterShape': 'poster',
        'extra': [
          {'name': 'search', 'isRequired': false},
          {
            'name': 'genre',
            'options': [
              'All',
              'Trending OTT Series',
              'Crime & Thriller',
              'Action & Drama',
              'Comedy & Family',
              'Mystery & Suspense',
            ],
            'isRequired': false,
          },
          {'name': 'skip', 'isRequired': false},
        ],
      },
      {
        'type': 'series',
        'id': 'asian_dramas',
        'name': '🎎 Asian & Short Dramas',
        'posterShape': 'poster',
        'extra': [
          {'name': 'search', 'isRequired': false},
          {
            'name': 'genre',
            'options': [
              'All',
              'Trending K-Dramas',
              'Chinese Dramas (C-Drama)',
              'Anime & Donghua',
              'Vertical Micro-Dramas',
              'DramaBox Unlocked',
              'ReelShort Hits',
              'ShortMax & Sereal+',
              'Billionaire Romance',
              'Werewolf & Alpha',
              'Revenge & CEO',
            ],
            'isRequired': false,
          },
          {'name': 'skip', 'isRequired': false},
        ],
      },
      {
        'type': 'movie',
        'id': 'dm_movies',
        'name': 'Dailymotion Indian & Global',
        'posterShape': 'poster',
        'extra': [
          {'name': 'search', 'isRequired': false},
          {
            'name': 'genre',
            'options': [
              'All',
              'Hindi Movies & Dramas',
              'Pakistani Dramas',
              'International Movies',
            ],
            'isRequired': false,
          },
          {'name': 'skip', 'isRequired': false},
        ],
      },
      {
        'type': 'tv',
        'id': 'iptv_global',
        'name': 'Free Global Live IPTV',
        'posterShape': 'square',
        'extra': [
          {'name': 'search', 'isRequired': false},
          {
            'name': 'genre',
            'options': [
              'All',
              'India (All Regional)',
              'News',
              'Sports',
              'Movies',
              'Animation',
              'Music',
              'Entertainment',
              'Documentary',
            ],
            'isRequired': false,
          },
          {'name': 'skip', 'isRequired': false},
        ],
      },
    ];
  }

  /// Handles /catalog/:type/:id.json and /catalog/:type/:id/:extra.json
  Future<List<Map<String, dynamic>>> getCatalogItems({
    required String type,
    required String id,
    String? search,
    String? genre,
    String sort = 'new',
    int skip = 0,
  }) async {
    final cacheKey = '$id:$search:$genre:$sort:$skip';
    if (_cache.containsKey(cacheKey)) {
      return List<Map<String, dynamic>>.from(_cache[cacheKey]);
    }

    List<Map<String, dynamic>> items = [];

    try {
      if (id == 'hindi_movies') {
        items = await _fetchHindiMovies(search: search, genre: genre, sort: sort, skip: skip);
      } else if (id == 'hindi_series') {
        items = await _fetchHindiSeries(search: search, genre: genre, sort: sort, skip: skip);
      } else if (id == 'asian_dramas' || id == 'short_dramas') {
        items = await _fetchAsianDramas(search: search, genre: genre, sort: sort, skip: skip);
      } else if (id == 'yt_indian') {
        items = await _fetchYouTubeIndian(search: search, genre: genre, skip: skip);
      } else if (id == 'yt_international') {
        items = await _fetchYouTubeInternational(search: search, genre: genre, skip: skip);
      } else if (id == 'vimeo_picks') {
        items = await _fetchVimeo(search: search, genre: genre, skip: skip);
      } else if (id == 'archive_movies') {
        items = await _fetchArchiveOrg(search: search, genre: genre, skip: skip);
      } else if (id == 'dm_movies') {
        items = await _fetchDailymotion(search: search, genre: genre, skip: skip);
      } else if (id == 'iptv_global') {
        items = await _fetchIptvCatalog(search: search, genre: genre, skip: skip);
      }
    } catch (e) {
      print('[CatalogService] Error fetching catalog $id: $e');
    }

    if (items.isNotEmpty &&
        id != 'iptv_global' &&
        id != 'short_dramas' &&
        id != 'asian_dramas' &&
        id != 'hindi_movies' &&
        id != 'hindi_series') {
      try {
        final enriched = await Future.wait(
          items.map((it) => _enrichItem(it)),
        ).timeout(const Duration(seconds: 10), onTimeout: () => items);
        items = enriched;
      } catch (e) {
        print('[CatalogService] Catalog enrichment timeout/error (using fallbacks): $e');
      }
    }

    _cache[cacheKey] = items;
    return items;
  }

  Future<List<Map<String, dynamic>>> _fetchIptvCatalog({
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    await IptvService.instance.loadChannels();
    final isIndia = genre == 'India' || genre == 'Indian' || genre == 'India (All Regional)';
    final filtered = IptvService.instance.filterChannels(
      search: search,
      category: (genre == 'All' || isIndia) ? null : genre,
      country: isIndia ? 'IN' : null,
    );
    final slice = filtered.skip(skip).take(50);
    return slice.map((c) => {
      'id': 'iptv:${c.id}',
      'type': 'tv',
      'name': c.name,
      'poster': c.logo.isNotEmpty ? c.logo : 'https://i.imgur.com/7bK7QYI.png',
      'genres': [c.category, c.country],
      'description': 'Live TV broadcast: ${c.name} (${c.category} - ${c.country})',
      'posterShape': 'square',
    }).toList();
  }

  // ── YouTube Indian Fetcher ──────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _fetchYouTubeIndian({
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    String query;
    if (search != null && search.isNotEmpty) {
      query = '$search full movie hindi';
    } else {
      switch (genre) {
        case 'South Hindi Dubbed':
          query = 'south indian full movie hindi dubbed hd';
          break;
        case 'Indian Web Series':
          query = 'hindi web series full episodes hd';
          break;
        case 'Classic Hindi':
          query = 'old classic hindi full movie';
          break;
        case 'Comedy Hindi Movies':
          query = 'comedy full movie hindi';
          break;
        case 'Bollywood Full Movies':
        default:
          query = 'bollywood full movie hd';
          break;
      }
    }

    return _searchInvidious(query, genre: genre ?? 'Indian');
  }

  // ── YouTube International Fetcher ───────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _fetchYouTubeInternational({
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    String query;
    if (search != null && search.isNotEmpty) {
      query = '$search full movie';
    } else {
      switch (genre) {
        case 'Sci-Fi & Thriller':
          query = 'sci-fi thriller full movie english';
          break;
        case 'Documentaries':
          query = 'documentary full movie english hd';
          break;
        case 'Indie Cinema':
          query = 'award winning indie full movie';
          break;
        case 'Action Movies':
        default:
          query = 'action full movie english hd';
          break;
      }
    }

    return _searchInvidious(query, genre: genre ?? 'International');
  }

  Future<List<Map<String, dynamic>>> _searchInvidious(String query, {required String genre}) async {
    for (final instance in _invidiousInstances) {
      try {
        final url = Uri.parse('$instance/api/v1/search?q=${Uri.encodeComponent(query)}&type=video');
        final res = await http.get(url).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final list = jsonDecode(res.body) as List;
          final metas = <Map<String, dynamic>>[];
          for (final item in list) {
            final vId = item['videoId']?.toString() ?? '';
            final title = item['title']?.toString() ?? '';
            final desc = item['description']?.toString() ?? '';
            if (vId.isEmpty || title.isEmpty) continue;
            if (isNsfwContent(title) || isNsfwContent(desc)) continue;

            // Prefer HD 720p crisp thumbnail for YouTube
            final thumbs = item['videoThumbnails'] as List?;
            String poster = 'https://i.ytimg.com/vi/$vId/hq720.jpg';
            if (thumbs != null && thumbs.isNotEmpty) {
              final raw = thumbs.last['url']?.toString() ?? '';
              if (raw.startsWith('http') && !raw.contains('mqdefault') && !raw.contains('default.jpg')) {
                poster = raw;
              } else if (raw.isNotEmpty && !raw.contains('mqdefault')) {
                poster = 'https://i.ytimg.com$raw';
              }
            }

            metas.add({
              'id': 'yt:$vId',
              'type': 'movie',
              'name': title,
              'poster': poster,
              'nativePoster': poster,
              'background': 'https://i.ytimg.com/vi/$vId/maxresdefault.jpg',
              'description': desc.isNotEmpty ? desc : 'YouTube Media ($genre)',
              'releaseInfo': item['publishedText']?.toString() ?? '',
              'genres': ['YouTube', genre],
              'posterShape': 'landscape',
            });
          }
          if (metas.isNotEmpty) return metas;
        }
      } catch (_) {}
    }
    return [];
  }

  // ── Short Dramas Curated List ──────────────────────────────────────────────
  static const List<Map<String, dynamic>> shortDramaCuratedList = [
    {
      'id': 'sd:double_life_billionaire',
      'name': 'The Double Life of My Billionaire Husband',
      'poster': 'https://v-img.crazymaplestudios.com/v-images/book_cover_batch/200000000000000045/e8922dfe-037f-4b51-bf03-edeb01ec74a9.jpg',
      'genres': ['Trending Micro-Dramas', 'ReelShort Hits', 'Billionaire Romance'],
      'description': 'A sweet teacher marries an ordinary handyman who secretly happens to be the heir to the wealthiest family in the city.',
      'episodes': 76,
    },
    {
      'id': 'sd:forbidden_alpha',
      'name': 'Fated to My Forbidden Alpha',
      'poster': 'https://v-img.crazymaplestudios.com/v-images/book_cover_batch/200000000000000011/b8f0a9b5-b044-4e69-8ef9-407a0a7c7218.jpg',
      'genres': ['Trending Micro-Dramas', 'ReelShort Hits', 'Werewolf & Alpha'],
      'description': 'Rejected by her true mate, she finds herself bound to the most feared lycan king in the realm.',
      'episodes': 60,
    },
    {
      'id': 'sd:her_secrets_his_surrender',
      'name': 'Her Secrets His Surrender',
      'poster': 'https://i3.wp.com/dramafren.org/wp-content/uploads/2026/06/IMG_20260617_073446_445.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Billionaire Romance', 'DramaBox Unlocked'],
      'description': 'Behind her gentle facade lies a secret identity that brings the most powerful CEO to his knees.',
      'episodes': 63,
    },
    {
      'id': 'sd:every_marriage_makes_him_stronger',
      'name': 'Every Marriage Makes Him Stronger',
      'poster': 'https://i0.wp.com/dramafren.org/wp-content/uploads/2025/12/Screenshot_20251228_205406.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Billionaire Romance', 'DramaBox Unlocked'],
      'description': 'Bound by a mystical fate, each arranged marriage awakens hidden god-tier powers within him.',
      'episodes': 66,
    },
    {
      'id': 'sd:oops_i_married_a_prince',
      'name': 'Oops I Married a Prince',
      'poster': 'https://i2.wp.com/dramafren.org/wp-content/uploads/2026/04/IMG_20260428_122511_355.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Billionaire Romance', 'ShortMax & Sereal+'],
      'description': 'A drunken night and a rushed marriage certificate turn a broke college student into royal royalty.',
      'episodes': 69,
    },
    {
      'id': 'sd:his_hands_heal_his_fingers_kill',
      'name': 'His Hands Heal His Fingers Kill',
      'poster': 'https://i2.wp.com/dramafren.org/wp-content/uploads/2026/06/IMG_20260627_121441_404.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Revenge & CEO', 'DramaBox Unlocked'],
      'description': 'The miracle doctor of the underworld returns to civilization to protect his family and annihilate his enemies.',
      'episodes': 72,
    },
    {
      'id': 'sd:the_empress_s_modern_ally',
      'name': 'The Empress’s Modern Ally',
      'poster': 'https://i0.wp.com/dramafren.org/wp-content/uploads/2024/12/full-the-empresss-modern-ally-v0-3djb9dnz195e1.jpeg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'ShortMax & Sereal+', 'DramaBox Unlocked'],
      'description': 'A modern entrepreneur communicates through an ancient mirror to help an imperial empress conquer her empire.',
      'episodes': 75,
    },
    {
      'id': 'sd:gilded_shackles',
      'name': 'Gilded Shackles',
      'poster': 'https://i1.wp.com/dramafren.org/wp-content/uploads/2025/11/f5756a3141da0d80fef8d72dd0edef89.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Revenge & CEO', 'DramaBox Unlocked'],
      'description': 'Trapped in a gilded cage by an obsessive tycoon, she plays the ultimate game of deception to reclaim her freedom.',
      'episodes': 78,
    },
    {
      'id': 'sd:the_queen_eavesdrops_on_my_thoughts',
      'name': 'The Queen Eavesdrops on My Thoughts',
      'poster': 'https://i0.wp.com/dramafren.org/wp-content/uploads/2024/12/1000035893.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'ShortMax & Sereal+', 'DramaBox Unlocked'],
      'description': 'The ice-cold Queen can read every inner monologue of her quiet advisor, turning palace intrigue upside down.',
      'episodes': 81,
    },
    {
      'id': 'sd:the_regret_that_consumed_us_dubbed',
      'name': 'The Regret That Consumed Us',
      'poster': 'https://i0.wp.com/dramafren.org/wp-content/uploads/2025/10/41000122392.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Revenge & CEO', 'DramaBox Unlocked'],
      'description': 'He cast her aside for a superficial socialite. Years later, he discovers she was the benefactor who gave him everything.',
      'episodes': 84,
    },
    {
      'id': 'sd:with_my_heart_as_the_anchor',
      'name': 'With My Heart As the Anchor',
      'poster': 'https://i1.wp.com/dramafren.org/wp-content/uploads/2026/10/IMG_20261016_182105_338.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Billionaire Romance', 'ShortMax & Sereal+'],
      'description': 'A deep romance tested by familial betrayal and the high stakes of oceanic shipping empires.',
      'episodes': 87,
    },
    {
      'id': 'sd:she_moved_on_he_fell_apart',
      'name': 'She Moved On He Fell Apart',
      'poster': 'https://i1.wp.com/dramafren.org/wp-content/uploads/2026/09/IMG_20260905_082839_516.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Revenge & CEO', 'DramaBox Unlocked'],
      'description': 'The moment she stopped caring and walked out with her child, the billionaire husband realized he had lost his entire world.',
      'episodes': 90,
    },
    {
      'id': 'sd:no_way_back_to_my_heart',
      'name': 'No Way Back to My Heart',
      'poster': 'https://i1.wp.com/dramafren.org/wp-content/uploads/2025/09/41000121613.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Billionaire Romance', 'DramaBox Unlocked'],
      'description': 'She loved him blindly for five years. When she finally walks away, his desperate pursuit begins.',
      'episodes': 65,
    },
    {
      'id': 'sd:at_her_behest_the_ladys_dominion',
      'name': 'At Her Behest: The Lady’s Dominion',
      'poster': 'https://i3.wp.com/dramafren.org/wp-content/uploads/2025/04/IMG_20250413_135328_393.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Revenge & CEO', 'ShortMax & Sereal+'],
      'description': 'The supreme female head of the family takes control and puts every scheming relative in their place.',
      'episodes': 70,
    },
    {
      'id': 'sd:tangled_with_him',
      'name': 'Tangled With Him',
      'poster': 'https://i0.wp.com/dramafren.org/wp-content/uploads/2025/10/Screenshot_20251014_220236.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Billionaire Romance', 'ReelShort Hits'],
      'description': 'A forbidden encounter leads to an inescapable entanglement with her company’s most dangerous client.',
      'episodes': 73,
    },
    {
      'id': 'sd:the_system_i_rent_therefore_i_own',
      'name': 'The System I Rent Therefore I Own',
      'poster': 'https://i1.wp.com/dramafren.org/wp-content/uploads/2025/09/IMG_20250914_083824_954.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Revenge & CEO', 'DramaBox Unlocked'],
      'description': 'Armed with a god-tier rental upgrade system, an underdog turns pocket change into global dominance.',
      'episodes': 76,
    },
    {
      'id': 'sd:cash_in_bank_greedy_for_doom',
      'name': 'Cash in Bank Greedy for Doom',
      'poster': 'https://i0.wp.com/dramafren.org/wp-content/uploads/2026/07/IMG_20260710_072813_078.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Revenge & CEO', 'DramaBox Unlocked'],
      'description': 'A greedy cabal thought they could steal his savings, unaware his accounts are guarded by supreme military intelligence.',
      'episodes': 79,
    },
    {
      'id': 'sd:cute_wife_arrives_commander_lu',
      'name': 'Cute Wife Arrives, Commander Lu',
      'poster': 'https://i0.wp.com/dramafren.org/wp-content/uploads/2026/10/IMG_20261020_170002_170.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Billionaire Romance', 'DramaBox Unlocked'],
      'description': 'The iron-fisted commander thought he was untouchable until his bubbly arranged bride completely melted his icy heart.',
      'episodes': 82,
    },
    {
      'id': 'sd:exiled_but_adored_by_everyone',
      'name': 'Exiled but Adored by Everyone',
      'poster': 'https://i2.wp.com/dramafren.org/wp-content/uploads/2026/10/IMG_20261020_165752_629.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Revenge & CEO', 'ShortMax & Sereal+'],
      'description': 'Banished by her foolish family, she is taken in by the world’s most powerful foster family who dote on her endlessly.',
      'episodes': 85,
    },
    {
      'id': 'sd:love_the_late_breeze',
      'name': 'Love the Late Breeze',
      'poster': 'https://i1.wp.com/dramafren.org/wp-content/uploads/2026/10/IMG_20261020_165605_036.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Billionaire Romance', 'ReelShort Hits'],
      'description': 'A heartfelt second-chance romance between two wounded souls who find solace in each other’s presence.',
      'episodes': 88,
    },
    {
      'id': 'sd:mind_reading_wife_is_a_bit_cute',
      'name': 'Mind-Reading Wife Is a Bit Cute',
      'poster': 'https://i1.wp.com/dramafren.org/wp-content/uploads/2026/10/IMG_20261020_165405_493.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Billionaire Romance', 'DramaBox Unlocked'],
      'description': 'She can hear every scheming plan of her enemies, turning every palace trap into an adorable victory for her husband.',
      'episodes': 91,
    },
    {
      'id': 'sd:the_prince_s_consort_is_absolutely_slaying',
      'name': 'The Prince’s Consort Is Absolutely Slaying',
      'poster': 'https://i3.wp.com/dramafren.org/wp-content/uploads/2026/10/IMG_20261020_164858_607.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Revenge & CEO', 'DramaBox Unlocked'],
      'description': 'Reborn into the body of the bullied consort, the assassin doctor makes everyone who wronged her pay tenfold.',
      'episodes': 94,
    },
    {
      'id': 'sd:caged_top_scorer_hidden_heiress',
      'name': 'Caged Top Scorer, Hidden Heiress',
      'poster': 'https://i1.wp.com/dramafren.org/wp-content/uploads/2026/10/IMG_20261018_160203_842.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Revenge & CEO', 'ShortMax & Sereal+'],
      'description': 'Underestimated as a quiet student, she is secretly the top hacker and the sole heiress to the nation’s largest conglomerate.',
      'episodes': 68,
    },
    {
      'id': 'sd:dad_and_son_body_swap',
      'name': 'Dad and Son Body Swap',
      'poster': 'https://i3.wp.com/dramafren.org/wp-content/uploads/2026/10/IMG_20261018_160158_617.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'ShortMax & Sereal+', 'DramaBox Unlocked'],
      'description': 'A freak lightning strike swaps the bodies of a strict billionaire father and his rebellious high school son.',
      'episodes': 71,
    },
    {
      'id': 'sd:fated_to_knock_on_his_door',
      'name': 'Fated to Knock on His Door',
      'poster': 'https://i3.wp.com/dramafren.org/wp-content/uploads/2026/10/IMG_20261018_160146_974.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Billionaire Romance', 'ReelShort Hits'],
      'description': 'Running away from an arranged marriage, she knocks on a stranger’s penthouse door—only to find her true soulmate.',
      'episodes': 74,
    },
    {
      'id': 'sd:reborn_vows_beyond_deception',
      'name': 'Reborn Vows Beyond Deception',
      'poster': 'https://i0.wp.com/dramafren.org/wp-content/uploads/2026/10/IMG_20261018_160212_441.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Revenge & CEO', 'DramaBox Unlocked'],
      'description': 'Reborn on her wedding day, she publicly rejects the treacherous groom and pledges her hand to his commanding uncle.',
      'episodes': 77,
    },
    {
      'id': 'sd:second_chance_better_choice',
      'name': 'Second Chance, Better Choice',
      'poster': 'https://i3.wp.com/dramafren.org/wp-content/uploads/2026/10/IMG_20261018_160141_985.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Revenge & CEO', 'ShortMax & Sereal+'],
      'description': 'Given a second chance at youth, she ignores her toxic ex and helps the quiet genius who loved her in silence.',
      'episodes': 80,
    },
    {
      'id': 'sd:second_life_to_unmask_their_lies',
      'name': 'Second Life to Unmask Their Lies',
      'poster': 'https://i1.wp.com/dramafren.org/wp-content/uploads/2026/10/IMG_20261018_160209_024.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Revenge & CEO', 'DramaBox Unlocked'],
      'description': 'Framed and betrayed by her step-sister, she returns with vengeance to expose every dark secret in high society.',
      'episodes': 83,
    },
    {
      'id': 'sd:the_family_he_almost_missed',
      'name': 'The Family He Almost Missed',
      'poster': 'https://i2.wp.com/dramafren.org/wp-content/uploads/2026/10/IMG_20261018_160035_808.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Billionaire Romance', 'DramaBox Unlocked'],
      'description': 'Five years after a one-night encounter, the CEO meets twins who look exactly like him calling him daddy.',
      'episodes': 86,
    },
    {
      'id': 'sd:the_pawn_who_played_the_king',
      'name': 'The Pawn Who Played the King',
      'poster': 'https://i0.wp.com/dramafren.org/wp-content/uploads/2026/10/IMG_20261018_160155_242.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Revenge & CEO', 'DramaBox Unlocked'],
      'description': 'They thought he was an easily discarded pawn. When the pieces fall, he reveals he was the grandmaster all along.',
      'episodes': 89,
    },
    {
      'id': 'sd:they_all_betrayed_me_now_they_lost_everything',
      'name': 'They All Betrayed Me, Now They Lost Everything',
      'poster': 'https://i3.wp.com/dramafren.org/wp-content/uploads/2026/10/IMG_20261018_160136_864.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Revenge & CEO', 'DramaBox Unlocked'],
      'description': 'Her relatives threw her out into the cold. Within months, her new startup buys out their entire family company.',
      'episodes': 92,
    },
    {
      'id': 'sd:do_whatever_one_pleases',
      'name': 'Do Whatever One Pleases',
      'poster': 'https://i1.wp.com/dramafren.org/wp-content/uploads/2026/10/IMG_20261016_183607_758.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'ShortMax & Sereal+', 'DramaBox Unlocked'],
      'description': 'Unshackled from conservative expectations, the rebellious heiress lives life on her own uncompromising terms.',
      'episodes': 95,
    },
    {
      'id': 'sd:moon_please_give_me_a_hug',
      'name': 'Moon, Please Give Me a Hug',
      'poster': 'https://i1.wp.com/dramafren.org/wp-content/uploads/2026/10/IMG_20261016_183427_282.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Billionaire Romance', 'ReelShort Hits'],
      'description': 'An emotional romantic tale of healing and devotion under the serene moonlight.',
      'episodes': 67,
    },
    {
      'id': 'sd:phoenix_perches_on_spring_mountain',
      'name': 'Phoenix Perches on Spring Mountain',
      'poster': 'https://i2.wp.com/dramafren.org/wp-content/uploads/2026/10/IMG_20261016_183239_365.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'ShortMax & Sereal+', 'DramaBox Unlocked'],
      'description': 'The legendary female war hero returns from the borders to claim her rightful throne on the mountain.',
      'episodes': 70,
    },
    {
      'id': 'sd:six_years_after_the_breakup',
      'name': 'Six Years After the Breakup',
      'poster': 'https://i1.wp.com/dramafren.org/wp-content/uploads/2026/10/IMG_20261016_183107_228.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Billionaire Romance', 'DramaBox Unlocked'],
      'description': 'A car crash causes the CEO to lose six years of memory, making him believe he and his ex-wife are still madly in love.',
      'episodes': 73,
    },
    {
      'id': 'sd:the_heir_told_me_to_stop_pestering_him',
      'name': 'The Heir Told Me to Stop Pestering Him',
      'poster': 'https://i0.wp.com/dramafren.org/wp-content/uploads/2026/10/IMG_20261016_182909_032.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Billionaire Romance', 'ShortMax & Sereal+'],
      'description': 'He arrogantly warned her to stop pursuing him—only to learn she had already married his wealthy family patriarch.',
      'episodes': 76,
    },
    {
      'id': 'sd:the_wrong_sedan_chair',
      'name': 'The Wrong Sedan Chair',
      'poster': 'https://i1.wp.com/dramafren.org/wp-content/uploads/2026/10/IMG_20261016_182646_036.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Billionaire Romance', 'DramaBox Unlocked'],
      'description': 'Two brides are accidentally switched during a wedding procession, binding an ordinary girl to a secluded prince.',
      'episodes': 79,
    },
    {
      'id': 'sd:three_years_of_exile_for_a_divorce_letter',
      'name': 'Three Years of Exile for a Divorce Letter',
      'poster': 'https://i1.wp.com/dramafren.org/wp-content/uploads/2026/10/IMG_20261016_182400_157.jpg?resize=200,300',
      'genres': ['Trending Micro-Dramas', 'Revenge & CEO', 'DramaBox Unlocked'],
      'description': 'Banished for three years, she signs the divorce papers and hands them back along with ownership of his entire kingdom.',
      'episodes': 82,
    },
  ];

  // ── Vertical Short & Micro-Dramas Fetcher (Dynamic Live Aggregator) ────────
  /// Fetches vertical short and micro-dramas dynamically from live aggregators
  /// with automatic fallback to high-speed curated CDNs.
  Future<List<Map<String, dynamic>>> _fetchShortDramas({
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    // 1. Calculate target live page (each page holds ~39 micro-dramas)
    final page = (skip ~/ 20) + 1;

    // 2. Formulate dynamic live search/category query
    String? liveUrl;
    if (search != null && search.trim().isNotEmpty) {
      final q = Uri.encodeComponent(search.trim());
      liveUrl = (page > 1) ? 'https://dramafren.org/page/$page/?s=$q' : 'https://dramafren.org/?s=$q';
    } else if (genre != null && genre.isNotEmpty && genre != 'All') {
      String? keyword;
      if (genre.contains('Werewolf') || genre.contains('Alpha')) {
        keyword = 'alpha';
      } else if (genre.contains('Billionaire')) {
        keyword = 'billionaire';
      } else if (genre.contains('Revenge') || genre.contains('CEO')) {
        keyword = 'revenge';
      } else if (genre.contains('ReelShort')) {
        keyword = 'reelshort';
      } else if (genre.contains('DramaBox')) {
        keyword = 'dramabox';
      } else if (genre.contains('ShortMax') || genre.contains('Sereal')) {
        keyword = 'shortmax';
      }

      if (keyword != null) {
        liveUrl = (page > 1) ? 'https://dramafren.org/page/$page/?s=$keyword' : 'https://dramafren.org/?s=$keyword';
      } else {
        liveUrl = (page > 1) ? 'https://dramafren.org/page/$page/' : 'https://dramafren.org/';
      }
    } else {
      liveUrl = (page > 1) ? 'https://dramafren.org/page/$page/' : 'https://dramafren.org/';
    }

    // 3. Attempt live dynamic retrieval with fast timeout
    try {
      final res = await http.get(Uri.parse(liveUrl), headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      }).timeout(const Duration(seconds: 4));

      if (res.statusCode == 200) {
        final doc = html_parser.parse(res.body);
        final postItems = doc.querySelectorAll('article.post, .film-item, article');
        if (postItems.isNotEmpty) {
          final dynamicList = <Map<String, dynamic>>[];
          for (final it in postItems) {
            final titleEl = it.querySelector('.title, h2, h3, a[title]');
            var title = titleEl?.attributes['title'] ?? titleEl?.text.trim() ?? '';
            title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
            title = title.replaceAll(RegExp(r'\s*-\s*EP\d+.*', caseSensitive: false), '').trim();
            final link = it.querySelector('a')?.attributes['href'] ?? '';
            final img = it.querySelector('img')?.attributes['src'] ?? it.querySelector('img')?.attributes['data-src'] ?? '';
            if (title.isEmpty || img.isEmpty || !img.startsWith('http')) continue;

            final cleanId = 'sd:' + title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
            final cleanItem = {
              'id': cleanId,
              'type': 'series',
              'name': title,
              'poster': img,
              'nativePoster': img,
              'background': img,
              'description': 'Live vertical micro-drama: $title.\n📱 Format: Vertical Short Drama • ⚡ Free Stream',
              'releaseInfo': '2024 • Micro-Drama',
              'genres': [genre ?? 'Trending Micro-Dramas', 'Short Drama'],
              'posterShape': 'poster',
              'url': link,
            };
            dynamicShortDramas[cleanId] = cleanItem;
            dynamicList.add(cleanItem);
          }
          if (dynamicList.isNotEmpty) {
            return dynamicList.take(20).toList();
          }
        }
      }
    } catch (_) {
      // Graceful fallback to verified curated list if live portal is slow or unreachable
    }

    // 4. Fallback to rich curated list
    final curatedList = shortDramaCuratedList;
    var list = curatedList;
    if (genre != null && genre.isNotEmpty && genre != 'All') {
      final gLower = genre.toLowerCase();
      list = list.where((it) {
        final genres = (it['genres'] as List).map((g) => g.toString().toLowerCase()).toList();
        return genres.any((g) => g.contains(gLower) || gLower.contains(g));
      }).toList();
    }

    if (search != null && search.isNotEmpty) {
      final sLower = search.toLowerCase();
      list = list.where((it) => it['name'].toString().toLowerCase().contains(sLower)).toList();
    }

    return list.skip(skip).take(20).map<Map<String, dynamic>>((it) {
      return {
        'id': it['id'],
        'type': 'series',
        'name': it['name'],
        'poster': it['poster'],
        'nativePoster': it['poster'],
        'background': it['poster'],
        'description': '${it['description']}\n📱 Format: Vertical Micro-Drama (${it['episodes']} Episodes) • ⚡ Unlocked Playback',
        'releaseInfo': '2024 • ${it['episodes']} EPs',
        'genres': it['genres'],
        'posterShape': 'poster',
      };
    }).toList();
  }

  static String _buildTmdbSort(String sort, {bool isTv = false}) {
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    
    if (sort == 'new') {
      if (isTv) {
        return '&first_air_date.lte=$today&first_air_date.gte=2024-01-01&sort_by=first_air_date.desc&vote_count.gte=2';
      } else {
        return '&primary_release_date.lte=$today&primary_release_date.gte=2024-01-01&sort_by=primary_release_date.desc&vote_count.gte=3';
      }
    } else if (sort == 'trending') {
      if (isTv) {
        return '&first_air_date.gte=2023-01-01&sort_by=popularity.desc';
      } else {
        return '&primary_release_date.gte=2023-01-01&sort_by=popularity.desc';
      }
    } else if (sort == 'top_rated') {
      return '&sort_by=vote_average.desc&vote_count.gte=50';
    } else {
      // 'popular'
      return '&sort_by=popularity.desc';
    }
  }

  // ── Hindi Movies Fetcher ──────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _fetchHindiMovies({
    String? search,
    String? genre,
    String sort = 'new',
    int skip = 0,
  }) async {
    final page = (skip ~/ 20) + 1;
    final tmdbKey = AddonConfig.instance.tmdbApiKey.trim();
    final apiKey = tmdbKey.isNotEmpty ? tmdbKey : 'b3556f3b206e16f82df4d1f6fd4545e6';
    
    String url;
    if (search != null && search.trim().isNotEmpty) {
      url = 'https://api.tmdb.org/3/search/movie?api_key=$apiKey&query=${Uri.encodeComponent(search.trim())}&page=$page';
    } else {
      String genreQuery = '';
      if (genre == 'Action & Thriller') genreQuery = '&with_genres=28,53';
      else if (genre == 'Comedy & Family') genreQuery = '&with_genres=35,10751';
      else if (genre == 'Romance & Drama') genreQuery = '&with_genres=10749,18';
      else if (genre == 'Classic Bollywood') genreQuery = '&primary_release_date.lte=2005-01-01';

      final sortQuery = _buildTmdbSort(sort, isTv: false);
      url = 'https://api.tmdb.org/3/discover/movie?api_key=$apiKey&with_original_language=hi$sortQuery$genreQuery&page=$page';
    }

    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final results = (data['results'] as List?) ?? [];
        return results.map<Map<String, dynamic>>((r) {
          final pPath = r['poster_path']?.toString();
          final bPath = r['backdrop_path']?.toString();
          final title = r['title']?.toString() ?? 'Hindi Movie';
          final year = (r['release_date']?.toString() ?? '').split('-').first;
          final rating = (r['vote_average'] is num) ? (r['vote_average'] as num).toStringAsFixed(1) : '';
          return {
            'id': 'tmdb:${r['id']}',
            'type': 'movie',
            'name': title,
            'poster': pPath != null ? 'https://image.tmdb.org/t/p/w500$pPath' : '',
            'background': bPath != null ? 'https://image.tmdb.org/t/p/w1280$bPath' : '',
            'description': r['overview']?.toString() ?? 'Bollywood & Indian cinema streaming.',
            'year': year,
            'releaseInfo': year,
            'rating': rating,
            'imdbRating': rating,
            'genres': ['Hindi', 'Bollywood', genre ?? 'Movie'],
            'posterShape': 'poster',
          };
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  // ── Hindi Series Fetcher ──────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _fetchHindiSeries({
    String? search,
    String? genre,
    String sort = 'new',
    int skip = 0,
  }) async {
    final page = (skip ~/ 20) + 1;
    final tmdbKey = AddonConfig.instance.tmdbApiKey.trim();
    final apiKey = tmdbKey.isNotEmpty ? tmdbKey : 'b3556f3b206e16f82df4d1f6fd4545e6';
    
    String url;
    if (search != null && search.trim().isNotEmpty) {
      url = 'https://api.tmdb.org/3/search/tv?api_key=$apiKey&query=${Uri.encodeComponent(search.trim())}&page=$page';
    } else {
      String genreQuery = '';
      if (genre == 'Crime & Thriller') genreQuery = '&with_genres=80,9648';
      else if (genre == 'Action & Drama') genreQuery = '&with_genres=10759,18';
      else if (genre == 'Comedy & Family') genreQuery = '&with_genres=35,10751';
      else if (genre == 'Mystery & Suspense') genreQuery = '&with_genres=9648';

      final sortQuery = _buildTmdbSort(sort, isTv: true);
      url = 'https://api.tmdb.org/3/discover/tv?api_key=$apiKey&with_original_language=hi$sortQuery$genreQuery&page=$page';
    }

    try {
      final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final results = (data['results'] as List?) ?? [];
        return results.map<Map<String, dynamic>>((r) {
          final pPath = r['poster_path']?.toString();
          final bPath = r['backdrop_path']?.toString();
          final title = r['name']?.toString() ?? 'Hindi Series';
          final year = (r['first_air_date']?.toString() ?? '').split('-').first;
          final rating = (r['vote_average'] is num) ? (r['vote_average'] as num).toStringAsFixed(1) : '';
          return {
            'id': 'tmdb:${r['id']}',
            'type': 'series',
            'name': title,
            'poster': pPath != null ? 'https://image.tmdb.org/t/p/w500$pPath' : '',
            'background': bPath != null ? 'https://image.tmdb.org/t/p/w1280$bPath' : '',
            'description': r['overview']?.toString() ?? 'Indian OTT & Hindi drama series.',
            'year': year,
            'releaseInfo': year,
            'rating': rating,
            'imdbRating': rating,
            'genres': ['Hindi Series', 'Indian OTT', genre ?? 'Series'],
            'posterShape': 'poster',
          };
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  // ── Asian & Short Dramas Fetcher ──────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _fetchAsianDramas({
    String? search,
    String? genre,
    String sort = 'new',
    int skip = 0,
  }) async {
    if (genre == 'Trending K-Dramas' || genre == 'Chinese Dramas (C-Drama)' || genre == 'Anime & Donghua') {
      final page = (skip ~/ 20) + 1;
      final tmdbKey = AddonConfig.instance.tmdbApiKey.trim();
      final apiKey = tmdbKey.isNotEmpty ? tmdbKey : 'b3556f3b206e16f82df4d1f6fd4545e6';
      
      String langParam = 'ko';
      String genreParam = '';
      if (genre == 'Chinese Dramas (C-Drama)') {
        langParam = 'zh';
      } else if (genre == 'Anime & Donghua') {
        langParam = 'ja|zh';
        genreParam = '&with_genres=16';
      }

      final sortQuery = _buildTmdbSort(sort, isTv: true);
      final url = 'https://api.tmdb.org/3/discover/tv?api_key=$apiKey&with_original_language=$langParam$sortQuery$genreParam&page=$page';
      try {
        final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final results = (data['results'] as List?) ?? [];
          return results.map<Map<String, dynamic>>((r) {
            final pPath = r['poster_path']?.toString();
            final bPath = r['backdrop_path']?.toString();
            final title = r['name']?.toString() ?? 'Asian Drama';
            final year = (r['first_air_date']?.toString() ?? '').split('-').first;
            final rating = (r['vote_average'] is num) ? (r['vote_average'] as num).toStringAsFixed(1) : '';
            return {
              'id': 'tmdb:${r['id']}',
              'type': 'series',
              'name': title,
              'poster': pPath != null ? 'https://image.tmdb.org/t/p/w500$pPath' : '',
              'background': bPath != null ? 'https://image.tmdb.org/t/p/w1280$bPath' : '',
              'description': r['overview']?.toString() ?? 'Asian Drama series.',
              'year': year,
              'releaseInfo': year,
              'rating': rating,
              'imdbRating': rating,
              'genres': [genre ?? 'Asian Drama'],
              'posterShape': 'poster',
            };
          }).toList();
        }
      } catch (_) {}
    }

    return _fetchShortDramas(search: search, genre: genre, skip: skip);
  }

  Future<List<Map<String, dynamic>>> _fetchArchiveOrg({
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    String q;
    if (search != null && search.isNotEmpty) {
      q = 'mediatype:movies AND (title:${Uri.encodeComponent(search)} OR description:${Uri.encodeComponent(search)}) AND NOT collection:(adultcdroms) AND NOT collection:(no-preview) AND NOT subject:(porn OR nude OR nsfw OR erotica OR adult OR sex OR fetish)';
    } else {
      switch (genre) {
        case 'Indian Classics':
          q = 'mediatype:movies AND (title:hindi OR title:india OR title:bollywood OR collection:hindi_movies) AND NOT collection:(adultcdroms)';
          break;
        case 'Film Noir':
          q = 'mediatype:movies AND (collection:Film_Noir OR subject:film-noir) AND NOT collection:(adultcdroms)';
          break;
        case 'Sci-Fi & Horror':
          q = 'mediatype:movies AND (collection:SciFi_Horror OR subject:horror) AND NOT collection:(adultcdroms)';
          break;
        case 'Silent Era':
          q = 'mediatype:movies AND collection:silent_films AND NOT collection:(adultcdroms)';
          break;
        case 'Golden Era Hollywood':
        default:
          q = 'mediatype:movies AND collection:feature_films AND NOT collection:(adultcdroms)';
          break;
      }
    }

    final page = (skip / 20).floor() + 1;
    final url = Uri.parse(
        'https://archive.org/advancedsearch.php?q=$q&fl[]=identifier,title,description,year&sort[]=downloads+desc&rows=20&page=$page&output=json');

    try {
      final res = await http.get(url).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final docs = data['response']['docs'] as List;
        return docs.where((doc) {
          final id = doc['identifier']?.toString() ?? '';
          final title = doc['title']?.toString() ?? '';
          final desc = doc['description']?.toString() ?? '';
          if (isNsfwContent(title) || isNsfwContent(id) || isNsfwContent(desc)) return false;
          return true;
        }).map<Map<String, dynamic>>((doc) {
          final id = doc['identifier']?.toString() ?? '';
          final title = doc['title']?.toString() ?? id;
          final year = doc['year']?.toString() ?? '';
          final desc = doc['description']?.toString() ?? 'Internet Archive Classic';
          final poster = 'https://archive.org/download/$id/__ia_thumb.jpg';

          return {
            'id': 'archive:$id',
            'type': 'movie',
            'name': title,
            'poster': poster,
            'nativePoster': poster,
            'background': poster,
            'description': desc,
            'releaseInfo': year,
            'genres': ['Archive.org', genre ?? 'Classic'],
            'posterShape': 'landscape',
          };
        }).toList();
      }
    } catch (e) {
      print('[CatalogService] Archive.org error: $e');
    }
    return [];
  }

  // ── Vimeo Fetcher ───────────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _fetchVimeo({
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    String channel = 'staffpicks';
    if (genre == 'Short of the Week') {
      channel = 'shortsoftheweek';
    } else if (genre == 'Animation') {
      channel = 'animation';
    } else if (genre == 'Documentaries') {
      channel = 'documentary';
    }
    final page = (skip / 20).floor() + 1;
    final url = Uri.parse('https://vimeo.com/api/v2/channel/$channel/videos.json?page=$page');
    try {
      final res = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      }).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List;
        return list.where((item) {
          final title = item['title']?.toString() ?? '';
          final desc = item['description']?.toString() ?? '';
          if (isNsfwContent(title) || isNsfwContent(desc)) return false;
          return true;
        }).map<Map<String, dynamic>>((item) {
          final id = item['id'].toString();
          final title = item['title']?.toString() ?? 'Vimeo Video';
          final desc = (item['description']?.toString() ?? '')
              .replaceAll(RegExp(r'<[^>]*>'), '')
              .trim();
          final poster = item['thumbnail_large']?.toString() ?? item['thumbnail_medium']?.toString() ?? '';
          final durationSec = item['duration'] is int ? item['duration'] as int : 0;
          final durationMin = (durationSec / 60).round();
          return {
            'id': 'vimeo:$id',
            'type': 'movie',
            'name': title,
            'poster': poster,
            'nativePoster': poster,
            'background': poster,
            'description': desc.isNotEmpty ? desc : 'Vimeo Staff Pick',
            'releaseInfo': durationMin > 0 ? '$durationMin min' : '',
            'genres': ['Vimeo', genre ?? 'Staff Picks'],
            'posterShape': 'landscape',
          };
        }).toList();
      }
    } catch (e) {
      print('[CatalogService] Vimeo error: $e');
    }
    return [];
  }

  // ── Dailymotion Fetcher ─────────────────────────────────────────────────────
  Future<List<Map<String, dynamic>>> _fetchDailymotion({
    String? search,
    String? genre,
    int skip = 0,
  }) async {
    String q;
    if (search != null && search.isNotEmpty) {
      q = search;
    } else {
      switch (genre) {
        case 'Pakistani Dramas':
          q = 'pakistani drama full episode';
          break;
        case 'International Movies':
          q = 'full movie english';
          break;
        case 'Hindi Movies & Dramas':
        default:
          q = 'hindi full movie hd';
          break;
      }
    }

    final page = (skip / 20).floor() + 1;
    final url = Uri.parse(
        'https://api.dailymotion.com/videos?fields=id,title,description,thumbnail_1080_url,thumbnail_720_url,thumbnail_480_url,thumbnail_url,created_time&search=${Uri.encodeComponent(q)}&limit=20&page=$page&flags=no_live');

    try {
      final res = await http.get(url).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = data['list'] as List;
        return list.where((item) {
          final title = item['title']?.toString() ?? '';
          final desc = item['description']?.toString() ?? '';
          if (isNsfwContent(title) || isNsfwContent(desc)) return false;
          return true;
        }).map<Map<String, dynamic>>((item) {
          final id = item['id']?.toString() ?? '';
          final title = item['title']?.toString() ?? id;
          final desc = item['description']?.toString() ?? 'Dailymotion Stream';
          final poster = item['thumbnail_1080_url']?.toString() ??
              item['thumbnail_720_url']?.toString() ??
              item['thumbnail_480_url']?.toString() ??
              item['thumbnail_url']?.toString() ??
              '';

          return {
            'id': 'dm:$id',
            'type': 'movie',
            'name': title,
            'poster': poster,
            'nativePoster': poster,
            'background': poster,
            'description': desc,
            'genres': ['Dailymotion', genre ?? 'Video'],
            'posterShape': 'landscape',
          };
        }).toList();
      }
    } catch (e) {
      print('[CatalogService] Dailymotion error: $e');
    }
    return [];
  }

  // ── Meta Details Resolver (/meta/:type/:id.json) ───────────────────────────
  Future<Map<String, dynamic>?> getMetaDetail(
    String type,
    String id, {
    String? poster,
    String? name,
  }) async {
    if (id.startsWith('iptv:')) {
      final chId = id.replaceFirst('iptv:', '');
      final ch = await IptvService.instance.getChannelById(chId);
      if (ch != null) {
        return {
          'id': id,
          'type': type,
          'name': ch.name,
          'poster': ch.logo.isNotEmpty ? ch.logo : 'https://i.imgur.com/7bK7QYI.png',
          'background': ch.logo.isNotEmpty ? ch.logo : 'https://i.imgur.com/7bK7QYI.png',
          'description': 'Live TV broadcast: ${ch.name} (${ch.category} - ${ch.country})',
          'genres': [ch.category, ch.country],
        };
      }
    }

    if (id.startsWith('yt:')) {
      final vId = id.replaceFirst('yt:', '');
      String title = 'YouTube Video';
      String desc = 'Direct YouTube Stream';
      String poster = 'https://i.ytimg.com/vi/$vId/hq720.jpg';
      String bg = 'https://i.ytimg.com/vi/$vId/maxresdefault.jpg';

      for (final instance in _invidiousInstances) {
        try {
          final res = await http.get(Uri.parse('$instance/api/v1/videos/$vId')).timeout(const Duration(seconds: 3));
          if (res.statusCode == 200) {
            final json = jsonDecode(res.body);
            title = json['title']?.toString() ?? title;
            desc = json['description']?.toString() ?? desc;
            break;
          }
        } catch (_) {}
      }

      final rawMeta = {
        'id': id,
        'type': type,
        'name': title,
        'poster': poster,
        'nativePoster': poster,
        'background': bg,
        'description': desc,
      };
      return await _enrichItem(rawMeta);
    }

    if (id.startsWith('archive:')) {
      final ident = id.replaceFirst('archive:', '');
      try {
        final res = await http.get(Uri.parse('https://archive.org/metadata/$ident')).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body);
          final meta = json['metadata'] ?? {};
          final title = meta['title'] ?? ident;
          final desc = meta['description'] ?? 'Internet Archive Classic';
          final year = meta['year'] ?? '';
          final poster = 'https://archive.org/services/img/$ident';
          final rawMeta = {
            'id': id,
            'type': type,
            'name': title,
            'poster': poster,
            'nativePoster': poster,
            'background': poster,
            'description': desc,
            'releaseInfo': year,
          };
          return await _enrichItem(rawMeta);
        }
      } catch (_) {}
      final rawMeta = {
        'id': id,
        'type': type,
        'name': ident,
        'poster': 'https://archive.org/services/img/$ident',
        'nativePoster': 'https://archive.org/services/img/$ident',
        'description': 'Internet Archive Media',
      };
      return await _enrichItem(rawMeta);
    }

    if (id.startsWith('dm:')) {
      final vId = id.replaceFirst('dm:', '');
      try {
        final res = await http.get(Uri.parse('https://api.dailymotion.com/video/$vId?fields=title,description,thumbnail_720_url')).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body);
          final poster = json['thumbnail_720_url'] ?? '';
          final rawMeta = {
            'id': id,
            'type': type,
            'name': json['title'] ?? 'Dailymotion Video',
            'poster': poster,
            'nativePoster': poster,
            'background': poster,
            'description': json['description'] ?? '',
          };
          return await _enrichItem(rawMeta);
        }
      } catch (_) {}
      final rawMeta = {
        'id': id,
        'type': type,
        'name': 'Dailymotion Video',
        'description': 'Dailymotion Stream',
      };
      return await _enrichItem(rawMeta);
    }

    if (id.startsWith('vimeo:')) {
      final vId = id.replaceFirst('vimeo:', '');
      try {
        final res = await http.get(Uri.parse('https://vimeo.com/api/oembed.json?url=https://vimeo.com/$vId')).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body);
          final title = json['title']?.toString() ?? 'Vimeo Video';
          final poster = json['thumbnail_url']?.toString() ?? '';
          final author = json['author_name']?.toString() ?? '';
          final desc = json['description']?.toString() ?? (author.isNotEmpty ? 'By $author on Vimeo' : 'Vimeo Staff Pick');
          final rawMeta = {
            'id': id,
            'type': type,
            'name': title,
            'poster': poster,
            'nativePoster': poster,
            'background': poster,
            'description': desc,
          };
          return await _enrichItem(rawMeta);
        }
      } catch (_) {}
      final rawMeta = {
        'id': id,
        'type': type,
        'name': 'Vimeo Video',
        'description': 'Vimeo Stream',
      };
      return await _enrichItem(rawMeta);
    }

    if (id.startsWith('sd:') || id.startsWith('shortdrama:')) {
      final baseId = id.contains(':') && !id.startsWith('sd:')
          ? id.split(':').take(2).join(':')
          : (id.split(':').length > 2 ? id.split(':').take(2).join(':') : id);

      Map<String, dynamic>? item = dynamicShortDramas[baseId] ?? dynamicShortDramas[id];
      if (item == null) {
        try {
          item = shortDramaCuratedList.firstWhere(
            (it) => it['id'] == baseId || id.contains(it['id']!.toString().replaceFirst('sd:', '')),
          );
        } catch (_) {}
      }

      final resolvedName = (name != null && name.trim().isNotEmpty)
          ? name.trim()
          : (item?['name']?.toString() ?? baseId.split(':').last.replaceAll('_', ' '));

      final resolvedPoster = (poster != null && poster.trim().isNotEmpty)
          ? poster.trim()
          : (item?['poster']?.toString() ?? '');

      final epsCount = (item?['episodes'] as int?) ?? 60;
      final episodesList = List.generate(epsCount, (idx) {
        final epNum = idx + 1;
        return {
          'id': '$baseId:1:$epNum',
          'season': 1,
          'episode': epNum,
          'name': 'Episode $epNum',
          'thumbnail': resolvedPoster,
          'overview': 'Episode $epNum of $resolvedName',
        };
      });

      return {
        'id': id,
        'type': 'series',
        'name': resolvedName,
        'poster': resolvedPoster,
        'background': resolvedPoster,
        'description': item?['description'] ?? 'Vertical short drama mini-series.',
        'genres': item?['genres'] ?? ['Micro-Drama', 'Short Drama'],
        'seasons': [1],
        'episodesBySeason': {
          '1': episodesList,
        },
      };
    }

    return null;
  }

  // ── Poster & Rating Enrichment Helpers ─────────────────────────────────────
  static Map<String, dynamic> _cleanTitleAndExtractYear(String rawTitle) {
    var title = rawTitle;

    // 1. Extract 4-digit year (1900-2099)
    int? year;
    final yearMatch = RegExp(r'\b(19\d\d|20\d\d)\b').firstMatch(title);
    if (yearMatch != null) {
      year = int.tryParse(yearMatch.group(1)!);
    }

    // 2. Cut off channel/actors/trailers after common separator symbols
    for (final sep in ['|', ' - ', '–', '—', '•', '//', '\\']) {
      if (title.contains(sep)) {
        final candidate = title.split(sep).first.trim();
        if (candidate.length >= 3) {
          title = candidate;
          break;
        }
      }
    }

    // 3. Strip foreign script noise (e.g. Hindi Devanagari, Urdu) from search query
    title = title.replaceAll(RegExp(r'[\u0900-\u097F\u0600-\u06FF]'), ' ');

    // 4. Strip common leading noise prefixes
    title = title.replaceAll(RegExp(r'^(new\s+hindi\s+movie\s*[:\s]*|latest\s+hindi\s+movie\s*[:\s]*|hindi\s+movie\s*[:\s]*)', caseSensitive: false), '');

    // 5. Remove text in brackets like [HD], (1975), [Full Movie]
    title = title.replaceAll(RegExp(r'\[.*?\]|\(.*?\)', caseSensitive: false), ' ');

    // 6. Strip common public catalog video noise phrases
    title = title.replaceAll(RegExp(
      r'\b(full movie|full hindi movie|hindi dubbed|hindi movie|south indian movie|south indian|south movie|south dubbed|tamil dubbed|telugu dubbed|kannada dubbed|malayalam dubbed|bengali movie|bollywood movie|hollywood movie|indian movie|blockbuster movie|superhit movie|classic movie|full episodes?|complete movie|award winning|official video|official trailer|official movie|with english subtitles?|english subtitles?|eng subs?|remastered|restored|colorized|restoration|4k uhd|4k hdr|1080p|720p|480p|4k|uhd|hdr|bluray|blu-ray|web-dl|webrip|dvdrip|hd|hq)\b',
      caseSensitive: false,
    ), ' ');

    // 7. Strip common distributor / studio / actor tags
    title = title.replaceAll(RegExp(
      r'\b(shemaroo|goldmines|pen movies|rajshri|yash raj films|yrf|t-series|ultra bollywood|venus|eros now|eros|satyajit ray|guru dutt|amitabh bachchan|dharmendra|shah rukh khan|salman khan|aamir khan)\b',
      caseSensitive: false,
    ), ' ');

    // 8. Clean punctuation & extra whitespace
    title = title.replaceAll(RegExp(r'["#%*<>:;=\\_{}]'), ' ');
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();

    return {'title': title, 'year': year};
  }

  Future<Map<String, dynamic>> _enrichItem(Map<String, dynamic> item) async {
    final id = item['id']?.toString() ?? '';
    if (id.startsWith('sd:') || id.startsWith('shortdrama:')) {
      return item;
    }
    final rawName = item['name']?.toString() ?? '';
    if (rawName.isEmpty) return item;

    final parsed = _cleanTitleAndExtractYear(rawName);
    final cleanTitle = parsed['title'] as String;
    final year = parsed['year'] as int?;

    if (cleanTitle.length < 2) return item;

    final cacheKey = '$cleanTitle:${year ?? ''}';
    if (_enrichmentCache.containsKey(cacheKey)) {
      final cached = _enrichmentCache[cacheKey]!;
      return _applyEnrichment(item, cached);
    }

    Map<String, dynamic>? enriched;

    // ── Tier 1: OMDb & TMDB (User API key or built-in reliable key) ──
    try {
      final omdb = await OmdbService.instance.getMetadata(null, title: cleanTitle, year: year);
      if (omdb != null && omdb.title != null && omdb.title!.isNotEmpty) {
        final poster = (omdb.poster != null && omdb.poster != 'N/A' && omdb.poster!.startsWith('http'))
            ? omdb.poster!
            : null;
        final rating = (omdb.imdbRating != null && omdb.imdbRating != 'N/A' && omdb.imdbRating!.isNotEmpty)
            ? omdb.imdbRating!
            : null;
        final yearStr = (omdb.year != null && omdb.year != 'N/A') ? omdb.year! : (year?.toString() ?? '');
        final plot = (omdb.plot != null && omdb.plot != 'N/A') ? omdb.plot! : null;

        enriched = {
          'name': omdb.title,
          if (omdb.imdbId != null) 'imdbId': omdb.imdbId,
          if (poster != null) 'poster': poster,
          if (rating != null) 'imdbRating': rating,
          if (rating != null) 'rating': rating,
          'year': yearStr,
          'releaseInfo': yearStr,
          if (plot != null) 'description': plot,
          if (omdb.genre != null && omdb.genre != 'N/A')
            'genres': omdb.genre!.split(', ').map((g) => g.trim()).toList(),
          if (poster != null) 'posterShape': 'poster',
        };
      }
    } catch (_) {}

    // TMDB Lookup (if poster or rating still missing)
    if (enriched == null || enriched['poster'] == null) {
      final tmdbKey = AddonConfig.instance.tmdbApiKey.trim();
      final apiKey = tmdbKey.isNotEmpty ? tmdbKey : 'b3556f3b206e16f82df4d1f6fd4545e6';
      for (final host in ['https://api.themoviedb.org/3', 'https://db.speedracelight.com/3']) {
        try {
          final yParam = year != null ? '&year=$year' : '';
          final uri = Uri.parse('$host/search/movie?api_key=$apiKey&query=${Uri.encodeComponent(cleanTitle)}$yParam');
          final res = await http.get(uri).timeout(const Duration(milliseconds: 2500));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            final results = data['results'] as List?;
            if (results != null && results.isNotEmpty) {
              final first = results.first;
              final pPath = first['poster_path']?.toString();
              final bPath = first['backdrop_path']?.toString();
              final vote = first['vote_average'];
              final rating = (vote is num && vote > 0) ? vote.toStringAsFixed(1) : null;
              final rDate = first['release_date']?.toString() ?? '';
              final rYear = rDate.length >= 4 ? rDate.substring(0, 4) : (year?.toString() ?? '');
              final title = (first['title'] ?? first['name'])?.toString() ?? cleanTitle;
              final overview = first['overview']?.toString();

              String? tmdbImdbId;
              try {
                final extUri = Uri.parse('$host/movie/${first['id']}/external_ids?api_key=$apiKey');
                final extRes = await http.get(extUri).timeout(const Duration(milliseconds: 1500));
                if (extRes.statusCode == 200) {
                  final extData = jsonDecode(extRes.body);
                  final idStr = extData['imdb_id']?.toString();
                  if (idStr != null && idStr.startsWith('tt')) {
                    tmdbImdbId = idStr;
                  }
                }
              } catch (_) {}

              enriched = {
                'name': title,
                if (tmdbImdbId != null) 'imdbId': tmdbImdbId,
                if (pPath != null) 'poster': 'https://image.tmdb.org/t/p/w500$pPath',
                if (bPath != null) 'background': 'https://image.tmdb.org/t/p/w1280$bPath',
                if (rating != null) 'imdbRating': rating,
                if (rating != null) 'rating': rating,
                'year': rYear,
                'releaseInfo': rYear,
                if (overview != null && overview.isNotEmpty) 'description': overview,
                if (pPath != null) 'posterShape': 'poster',
              };
              break;
            }
          }
        } catch (_) {}
      }
    }

    // ── Tier 2: 100% Free / Zero-Key API Fallback (Cinemeta / Metahub) ──
    if (enriched == null || enriched['poster'] == null) {
      try {
        final uri = Uri.parse('https://v3-cinemeta.strem.io/catalog/movie/top/search=${Uri.encodeComponent(cleanTitle)}.json');
        final res = await http.get(uri).timeout(const Duration(milliseconds: 2500));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final metas = data['metas'] as List?;
          if (metas != null && metas.isNotEmpty) {
            final m = metas.first;
            final poster = m['poster']?.toString();
            var rating = m['imdbRating']?.toString();
            final imdbId = m['id']?.toString();
            if ((rating == null || rating.isEmpty) && imdbId != null && imdbId.startsWith('tt')) {
              try {
                final omdb = await OmdbService.instance.getMetadata(imdbId);
                rating = omdb?.imdbRating;
              } catch (_) {}
            }
            final yStr = m['year']?.toString() ?? (year?.toString() ?? '');
            enriched = {
              'name': m['name']?.toString() ?? cleanTitle,
              if (imdbId != null && imdbId.startsWith('tt')) 'imdbId': imdbId,
              if (poster != null && poster.isNotEmpty) 'poster': poster,
              if (rating != null && rating.isNotEmpty && rating != 'N/A') 'imdbRating': rating,
              if (rating != null && rating.isNotEmpty && rating != 'N/A') 'rating': rating,
              'year': yStr,
              'releaseInfo': yStr,
              if (m['description'] != null) 'description': m['description'].toString(),
              if (poster != null && poster.isNotEmpty) 'posterShape': 'poster',
            };
          }
        }
      } catch (_) {}
    }

    // ── Tier 3: Last Fallback (Native website video thumbnail itself) ──
    if (enriched != null) {
      _enrichmentCache[cacheKey] = enriched;
      return _applyEnrichment(item, enriched);
    }

    // Cache empty map so we don't re-query missing items repeatedly
    _enrichmentCache[cacheKey] = {};
    return item;
  }

  Map<String, dynamic> _applyEnrichment(Map<String, dynamic> original, Map<String, dynamic> enriched) {
    if (enriched.isEmpty) return original;
    final merged = Map<String, dynamic>.from(original);
    // Preserve original native video poster as fallback
    merged['nativePoster'] ??= original['poster'];

    if (enriched['name'] != null) merged['name'] = enriched['name'];
    if (enriched['imdbId'] != null) merged['imdbId'] = enriched['imdbId'];
    if (enriched['poster'] != null) merged['poster'] = enriched['poster'];
    if (enriched['background'] != null) merged['background'] = enriched['background'];
    if (enriched['imdbRating'] != null) merged['imdbRating'] = enriched['imdbRating'];
    if (enriched['rating'] != null) merged['rating'] = enriched['rating'];
    if (enriched['year'] != null && enriched['year'].toString().isNotEmpty) {
      merged['year'] = enriched['year'];
      merged['releaseInfo'] = enriched['year'];
    }
    if (enriched['description'] != null && enriched['description'].toString().isNotEmpty) {
      merged['description'] = enriched['description'];
    }
    if (enriched['genres'] != null && enriched['genres'] is List) {
      final List existing = (merged['genres'] as List?) ?? [];
      final List toAdd = enriched['genres'] as List;
      final set = <String>{...existing.map((e) => e.toString()), ...toAdd.map((e) => e.toString())};
      merged['genres'] = set.toList();
    }
    if (enriched['posterShape'] != null) {
      merged['posterShape'] = enriched['posterShape'];
    }
    return merged;
  }

  // ── Stream Resolvers (/stream/:type/:id.json) ──────────────────────────────
  Future<List<Map<String, dynamic>>> resolveCustomStreams(
    String type, 
    String id, 
    {String? localBaseUrl}
  ) async {
    List<Map<String, dynamic>> streams = [];

    // 1. YouTube Stream Resolver
    if (id.startsWith('yt:')) {
      final vId = id.replaceFirst('yt:', '');
      streams = await _resolveYouTubeStreams(vId);
    } else if (id.startsWith('vimeo:')) {
      // 2. Vimeo Stream Resolver
      final vId = id.replaceFirst('vimeo:', '');
      streams = await _resolveVimeoStreams(vId);
    } else if (id.startsWith('archive:')) {
      // 3. Internet Archive Stream Resolver
      final ident = id.replaceFirst('archive:', '');
      streams = await _resolveArchiveStreams(ident);
    } else if (id.startsWith('dm:')) {
      // 4. Dailymotion Stream Resolver
      final vId = id.replaceFirst('dm:', '');
      streams = await _resolveDailymotionStreams(vId);
    } else if (id.startsWith('iptv:')) {
      // 5. Free Global Live IPTV Resolver
      final chId = id.replaceFirst('iptv:', '');
      final ch = await IptvService.instance.getChannelById(chId);
      if (ch != null) {
        streams.add({
          'name': '📺 ${ch.name}',
          'title': '⚡ Live HLS Stream • ${ch.category} • ${ch.country}\n🌐 Source: iptv-org Broadcast',
          'url': ch.url,
          'behaviorHints': const {'notWebReady': false},
        });
      }
    }

    return await _applyTorboxOptions(streams, localBaseUrl);
  }

  Future<List<Map<String, dynamic>>> _resolveYouTubeStreams(String vId) async {
    final streams = <Map<String, dynamic>>[];
    for (final instance in _invidiousInstances) {
      try {
        final url = Uri.parse('$instance/api/v1/videos/$vId');
        final res = await http.get(url).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body);
          final formatStreams = json['formatStreams'] as List?;
          if (formatStreams != null) {
            for (final f in formatStreams) {
              final streamUrl = f['url']?.toString();
              final quality = f['qualityLabel']?.toString() ?? f['resolution']?.toString() ?? 'Direct';
              if (streamUrl != null && streamUrl.isNotEmpty) {
                streams.add({
                  'name': 'YouTube ($quality)',
                  'title': '⚡ Direct Stream • $quality\n🌐 Source: YouTube\n📦 Host: Google Video CDN',
                  'url': streamUrl,
                  'behaviorHints': {'notWebReady': false},
                });
              }
            }
          }
          final hlsUrl = json['hlsUrl']?.toString();
          if (hlsUrl != null && hlsUrl.isNotEmpty) {
            streams.insert(0, {
              'name': 'YouTube HLS',
              'title': '⚡ Adaptive HLS Master Stream\n🌐 Source: YouTube\n📦 Host: Google Video CDN',
              'url': hlsUrl,
              'behaviorHints': {'notWebReady': false},
            });
          }
          if (streams.isNotEmpty) return streams;
        }
      } catch (_) {}
    }

    // Fallback: direct invidious playback url
    streams.add({
      'name': 'YouTube Web Player',
      'title': 'Direct Stream Link\n🌐 Source: YouTube\n📦 Host: YouTube Web',
      'url': 'https://www.youtube.com/watch?v=$vId',
    });
    return streams;
  }

  Future<List<Map<String, dynamic>>> _resolveVimeoStreams(String vId) async {
    final streams = <Map<String, dynamic>>[];
    try {
      final url = Uri.parse('https://player.vimeo.com/video/$vId');
      final res = await http.get(url, headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://vimeo.com/$vId',
      }).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final html = res.body;
        final m = RegExp(r'(\{"cdn_url":.+?\})\s*</script>').firstMatch(html);
        if (m != null) {
          final data = jsonDecode(m.group(1)!);
          final files = data['request']?['files'] as Map?;
          if (files != null) {
            final hls = files['hls'] as Map?;
            if (hls != null) {
              final cdns = hls['cdns'] as Map?;
              if (cdns != null && cdns.isNotEmpty) {
                final defaultCdn = hls['default_cdn']?.toString() ?? cdns.keys.first;
                final cdnObj = cdns[defaultCdn] ?? cdns.values.first;
                final m3u8Url = cdnObj?['url']?.toString();
                if (m3u8Url != null && m3u8Url.isNotEmpty) {
                  streams.add({
                    'name': '⚡ Vimeo Master HLS',
                    'title': '⚡ Adaptive Quality Master Stream\n🌐 Source: Vimeo\n📦 Host: Vimeo CDN',
                    'url': m3u8Url,
                    'behaviorHints': {'notWebReady': false},
                  });
                }
              }
            }
            final progressive = files['progressive'] as List?;
            if (progressive != null) {
              for (final p in progressive) {
                if (p is Map) {
                  final q = p['quality']?.toString() ?? 'HD';
                  final pUrl = p['url']?.toString();
                  if (pUrl != null && pUrl.isNotEmpty) {
                    streams.add({
                      'name': '🌐 Vimeo Direct ($q)',
                      'title': '🌐 Direct MP4 Video • $q\n🌐 Source: Vimeo\n📦 Host: Vimeo CDN',
                      'url': pUrl,
                      'behaviorHints': {'notWebReady': false},
                    });
                  }
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print('[CatalogService] Vimeo resolve error: $e');
    }

    if (streams.isEmpty) {
      streams.add({
        'name': 'Vimeo Web Player',
        'title': '⚡ Direct Web Stream\n🌐 Source: Vimeo\n📦 Host: Vimeo Web',
        'url': 'https://vimeo.com/$vId',
      });
    }
    return streams;
  }

  Future<List<Map<String, dynamic>>> _resolveArchiveStreams(String ident) async {
    final streams = <Map<String, dynamic>>[];
    try {
      final res = await http.get(Uri.parse('https://archive.org/metadata/$ident')).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final files = data['files'] as List?;
        if (files != null) {
          // Find MP4 or MKV video files
          for (final f in files) {
            final name = f['name']?.toString() ?? '';
            final format = f['format']?.toString() ?? '';
            if (name.endsWith('.mp4') || format.contains('MPEG4') || format.contains('h.264')) {
              final size = f['size'] != null ? ' (${(int.parse(f['size'].toString()) / (1024 * 1024)).toStringAsFixed(1)} MB)' : '';
              streams.add({
                'name': 'Archive.org',
                'title': '⚡ $name$size • Direct Cloud Stream\n🌐 Source: Archive.org\n📦 Host: Archive.org',
                'url': 'https://archive.org/download/$ident/$name',
                'behaviorHints': {'notWebReady': false},
              });
            }
          }
        }
      }
    } catch (e) {
      print('[CatalogService] Archive stream resolve error: $e');
    }

    if (streams.isEmpty) {
      streams.add({
        'name': 'Archive.org',
        'title': '⚡ Direct Video Download/Stream\n🌐 Source: Archive.org\n📦 Host: Archive.org',
        'url': 'https://archive.org/download/$ident/$ident.mp4',
      });
    }
    return streams;
  }

  Future<List<Map<String, dynamic>>> _resolveDailymotionStreams(String vId) async {
    final streams = <Map<String, dynamic>>[];
    try {
      final metaUrl = Uri.parse('https://www.dailymotion.com/player/metadata/video/$vId');
      final res = await http.get(metaUrl).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final qualities = json['qualities'] as Map?;
        if (qualities != null) {
          final auto = qualities['auto'] as List?;
          if (auto != null && auto.isNotEmpty) {
            final hlsUrl = auto.first['url']?.toString();
            if (hlsUrl != null && hlsUrl.isNotEmpty) {
              streams.add({
                'name': 'Dailymotion HLS',
                'title': '⚡ Adaptive Auto Quality HLS • Direct Stream\n🌐 Source: Dailymotion\n📦 Host: Dailymotion CDN',
                'url': hlsUrl,
                'behaviorHints': {'notWebReady': false},
              });
            }
          }
        }
      }
    } catch (e) {
      print('[CatalogService] Dailymotion stream error: $e');
    }

    if (streams.isEmpty) {
      streams.add({
        'name': 'Dailymotion Direct',
        'title': '⚡ Direct Web Stream\n🌐 Source: Dailymotion\n📦 Host: Dailymotion CDN',
        'url': 'https://www.dailymotion.com/video/$vId',
      });
    }
    return streams;
  }

  /// Searches YouTube, Archive.org, and Dailymotion for a given movie/show title
  /// and returns verified, family-safe public cloud streams to display in Stremio & Nuvio!
  Future<List<Map<String, dynamic>>> searchPublicStreams({
    required String title,
    int? year,
    String type = 'movie',
    String? localBaseUrl,
  }) async {
    final cleanTitle = title.trim();
    // Default OFF to prevent random or unverified public/user-uploaded video injection
    if (cleanTitle.isEmpty || !AddonConfig.instance.enablePublicStreams) return [];

    final cacheKey = 'pub_streams:$type:$cleanTitle:$year';
    if (_cache.containsKey(cacheKey)) {
      return List<Map<String, dynamic>>.from(_cache[cacheKey]);
    }

    final publicStreams = <Map<String, dynamic>>[];
    final futures = <Future<void>>[];

    // 1. YouTube Search & Stream Resolution (Strict match, no NSFW)
    futures.add(() async {
      try {
        final query = '$cleanTitle ${year ?? ''} full movie'.trim();
        final metas = await _searchInvidious(query, genre: 'Cinema');
        for (final item in metas) {
          final itemTitle = item['name']?.toString() ?? '';
          if (isNsfwContent(itemTitle)) continue;
          if (!isStrictTitleMatch(targetTitle: cleanTitle, candidateTitle: itemTitle, targetYear: year)) continue;

          final vId = (item['id']?.toString() ?? '').replaceFirst('yt:', '');
          if (vId.isNotEmpty) {
            final ytStreams = await _resolveYouTubeStreams(vId);
            for (final s in ytStreams) {
              final q = s['name']?.toString() ?? 'Direct';
              publicStreams.add({
                'name': '⚡ YouTube ($q)',
                'title': '⚡ Direct Cloud Stream (Non-Torrent) • $itemTitle',
                'url': s['url'],
                'behaviorHints': {'notWebReady': false},
              });
            }
            if (publicStreams.isNotEmpty) break;
          }
        }
      } catch (_) {}
    }());

    // 2. Internet Archive Search & Stream Resolution (Strictly public domain classics pre-1965)
    if (type == 'movie' && (year == null || year <= 1965)) {
      futures.add(() async {
        try {
          final archiveItems = await _fetchArchiveOrg(search: cleanTitle);
          for (final matched in archiveItems) {
            final itName = matched['name']?.toString() ?? '';
            final itYearStr = matched['releaseInfo']?.toString();
            final itYear = int.tryParse(itYearStr ?? '');
            if (isNsfwContent(itName)) continue;
            if (!isStrictTitleMatch(targetTitle: cleanTitle, candidateTitle: itName, targetYear: year, candidateYear: itYear)) continue;

            final ident = (matched['id']?.toString() ?? '').replaceFirst('archive:', '');
            if (ident.isNotEmpty) {
              final aStreams = await _resolveArchiveStreams(ident);
              for (final s in aStreams.take(2)) {
                publicStreams.add({
                  'name': '🏛️ Archive.org [Classic]',
                  'title': '🏛️ Internet Archive Public Domain • $itName',
                  'url': s['url'],
                  'behaviorHints': {'notWebReady': false},
                });
              }
              if (publicStreams.isNotEmpty) break;
            }
          }
        } catch (_) {}
      }());
    }

    // 3. Dailymotion Search & Stream Resolution (Strict match, no NSFW)
    futures.add(() async {
      try {
        final dmItems = await _fetchDailymotion(search: '$cleanTitle ${year ?? ''}');
        for (final item in dmItems) {
          final itemTitle = item['name']?.toString() ?? '';
          if (isNsfwContent(itemTitle)) continue;
          if (!isStrictTitleMatch(targetTitle: cleanTitle, candidateTitle: itemTitle, targetYear: year)) continue;

          final vId = (item['id']?.toString() ?? '').replaceFirst('dm:', '');
          if (vId.isNotEmpty) {
            final dmStreams = await _resolveDailymotionStreams(vId);
            for (final s in dmStreams) {
              publicStreams.add({
                'name': '📺 Dailymotion [HLS]',
                'title': '📺 Dailymotion Cloud Stream • $itemTitle',
                'url': s['url'],
                'behaviorHints': {'notWebReady': false},
              });
            }
            if (publicStreams.isNotEmpty) break;
          }
        }
      } catch (_) {}
    }());

    try {
      await Future.wait(futures).timeout(const Duration(milliseconds: 3500));
    } catch (_) {}

    final enrichedWithTorbox = await _applyTorboxOptions(publicStreams, localBaseUrl);
    _cache[cacheKey] = enrichedWithTorbox;
    return enrichedWithTorbox;
  }

  /// Checks TorBox cache state for supported direct streams and provides:
  /// 1. ⚡ TorBox [Cached] (instant CDN play)
  /// 2. ☁️⬆️ TorBox [Start Caching] (click to cloud cache)
  /// 3. Direct Play (native cloud stream)
  Future<List<Map<String, dynamic>>> _applyTorboxOptions(
    List<Map<String, dynamic>> streams,
    String? localBaseUrl,
  ) async {
    final torboxKey = AddonConfig.instance.torboxApiKey.trim();
    if (torboxKey.isEmpty || streams.isEmpty) return streams;

    final baseUrl = localBaseUrl ?? 'http://localhost:${AddonConfig.instance.port}';
    final candidateUrls = <String>[];

    for (final s in streams) {
      final url = s['url']?.toString() ?? '';
      if (url.isEmpty || url.contains('.m3u8')) continue;
      if (TorboxService.instance.isSupportedHoster(url)) {
        candidateUrls.add(url);
      }
    }

    Map<String, bool> cacheMap = {};
    if (candidateUrls.isNotEmpty) {
      try {
        cacheMap = await TorboxService.instance.checkCachedBatch(candidateUrls, torboxKey)
            .timeout(const Duration(milliseconds: 1500), onTimeout: () => {});
      } catch (_) {}
    }

    final enrichedStreams = <Map<String, dynamic>>[];

    for (final s in streams) {
      final url = s['url']?.toString() ?? '';
      final name = s['name']?.toString() ?? 'Stream';
      final title = s['title']?.toString() ?? '';
      final isSupported = candidateUrls.contains(url);
      final isCached = cacheMap[url] == true;

      if (isSupported && isCached) {
        enrichedStreams.add({
          'name': '⚡ TorBox [Cached]\n$name',
          'title': '⚡ Cached on TorBox Cloud CDN • Instant Playback\n$title',
          'url': '$baseUrl/torbox/play?url=${Uri.encodeComponent(url)}',
          'behaviorHints': const {'notWebReady': false},
        });
      } else if (isSupported) {
        enrichedStreams.add({
          'name': '☁️⬆️ TorBox [Start Caching]\n$name',
          'title': '☁️⬆️ TorBox Cachable • Click to cache on TorBox cloud & stream\n$title',
          'url': '$baseUrl/torbox/play?url=${Uri.encodeComponent(url)}',
          'behaviorHints': const {'notWebReady': false},
        });
      }

      enrichedStreams.add(s);
    }

    return enrichedStreams;
  }
}
