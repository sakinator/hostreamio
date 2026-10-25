import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// FreeLeechService: Resolves premium cyberlockers (1Fichier, Rapidgator, Mega, DDownload, etc.)
/// through public guest leech endpoints (Deepbrid free web downloader, High-Way, Get4All)
/// with zero user account or debrid key required.
class FreeLeechService {
  static final FreeLeechService instance = FreeLeechService._();

  FreeLeechService._();

  static const List<String> supportedCyberlockers = [
    '1fichier.com',
    'alterupload.com',
    'rapidgator.net',
    'rg.to',
    'mega.nz',
    'ddownload.com',
    'katfile.com',
    'turbobit.net',
    'nitroflare.com',
    'mediafire.com',
  ];

  /// Checks if a URL belongs to a supported cyberlocker.
  static bool canHandle(String url) {
    final lower = url.trim().toLowerCase();
    return supportedCyberlockers.any((domain) => lower.contains(domain));
  }

  /// Identifies the cyberlocker name from the URL.
  static String identifyLocker(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('1fichier')) return '1Fichier';
    if (lower.contains('rapidgator') || lower.contains('rg.to')) return 'Rapidgator';
    if (lower.contains('mega.nz')) return 'Mega.nz';
    if (lower.contains('ddownload')) return 'DDownload';
    if (lower.contains('katfile')) return 'Katfile';
    if (lower.contains('turbobit')) return 'Turbobit';
    if (lower.contains('nitroflare')) return 'Nitroflare';
    if (lower.contains('mediafire')) return 'Mediafire';
    return 'Cyberlocker';
  }

  /// Resolves an unrestricted direct playable stream link via public guest leech endpoints.
  Future<FreeLeechResult> resolve(String url, {Duration timeout = const Duration(seconds: 4)}) async {
    final cleanUrl = url.trim();
    if (!canHandle(cleanUrl)) {
      return FreeLeechResult.failed(cleanUrl, 'Unsupported hoster');
    }

    final client = http.Client();
    try {
      // 1. Try Deepbrid Free Web Downloader
      try {
        final res = await client.post(
          Uri.parse('https://www.deepbrid.com/backend/downloader/free'),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
            'Referer': 'https://www.deepbrid.com/downloader',
          },
          body: {'link': cleanUrl},
        ).timeout(timeout);

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data is Map) {
            final dl = data['download_url']?.toString() ?? data['link']?.toString();
            if (dl != null && dl.startsWith('http')) {
              return FreeLeechResult.success(
                originalUrl: cleanUrl,
                streamUrl: dl,
                title: data['filename']?.toString() ?? 'Deepbrid Free Leech Stream',
                provider: 'Deepbrid Guest',
                fileSize: int.tryParse(data['size']?.toString() ?? '0') ?? 0,
              );
            }
          }
        }
      } catch (_) {}

      // 2. Try High-Way Free Unrestrict API
      try {
        final res = await client.post(
          Uri.parse('https://high-way.me/api/free/unrestrict'),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'url': cleanUrl}),
        ).timeout(timeout);

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data is Map) {
            final dl = data['download']?.toString() ?? data['link']?.toString();
            if (dl != null && dl.startsWith('http')) {
              return FreeLeechResult.success(
                originalUrl: cleanUrl,
                streamUrl: dl,
                title: data['filename']?.toString() ?? 'High-Way Free Leech Stream',
                provider: 'High-Way Guest',
                fileSize: int.tryParse(data['size']?.toString() ?? '0') ?? 0,
              );
            }
          }
        }
      } catch (_) {}

      // 3. Try Get4All Multi-Host Bypass API
      try {
        final res = await client.post(
          Uri.parse('https://get4all.org/api/generate'),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
            'Referer': 'https://get4all.org/',
          },
          body: {'link': cleanUrl},
        ).timeout(timeout);

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          if (data is Map) {
            final dl = data['download_url']?.toString() ?? data['url']?.toString() ?? data['link']?.toString();
            if (dl != null && dl.startsWith('http')) {
              return FreeLeechResult.success(
                originalUrl: cleanUrl,
                streamUrl: dl,
                title: data['filename']?.toString() ?? 'Get4All Free Leech Stream',
                provider: 'Get4All Guest',
                fileSize: int.tryParse(data['size']?.toString() ?? '0') ?? 0,
              );
            }
          }
        }
      } catch (_) {}
    } finally {
      client.close();
    }

    return FreeLeechResult.failed(cleanUrl, 'Public guest leech slots currently busy');
  }
}

class FreeLeechResult {
  final bool success;
  final String originalUrl;
  final String? streamUrl;
  final String? title;
  final String? provider;
  final int fileSize;
  final String? error;

  String get fileSizeFormatted {
    if (fileSize <= 0) return '';
    if (fileSize >= 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  FreeLeechResult.success({
    required this.originalUrl,
    required this.streamUrl,
    required this.title,
    required this.provider,
    required this.fileSize,
  })  : success = true,
        error = null;

  FreeLeechResult.failed(this.originalUrl, this.error)
      : success = false,
        streamUrl = null,
        title = null,
        provider = null,
        fileSize = 0;
}
