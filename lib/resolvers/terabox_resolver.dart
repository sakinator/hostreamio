import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// TeraBox Direct Video Stream Extractor.
///
/// Resolves raw playable video CDN streams from TeraBox, 1024Tera, and mirror links
/// without requiring any user account or credentials via public worker API endpoints.
class TeraBoxResolver {
  static const List<String> supportedDomains = [
    'terabox.com',
    'teraboxapp.com',
    '1024tera.com',
    'terasharelink.com',
    '4funbox.com',
    'mirrobox.com',
    'momerybox.com',
    'tibibox.com',
    'nephobox.com',
    '1024terabox.com',
    'freeterabox.com',
  ];

  /// Checks if a URL is handled by the TeraBox resolver.
  static bool canHandle(String url) {
    final lower = url.trim().toLowerCase();
    return supportedDomains.any((d) => lower.contains(d));
  }

  /// Extracts the TeraBox shorturl key from various sharing URL patterns.
  static String? extractShortUrl(String url) {
    // Pattern 1: .../s/1abcdef or .../s/abcdef
    final m1 = RegExp(r'/s/(?:1)?([a-zA-Z0-9_-]+)').firstMatch(url);
    if (m1 != null) return m1.group(1);

    // Pattern 2: ?surl=abcdef or &surl=abcdef
    final m2 = RegExp(r'[?&]surl=([a-zA-Z0-9_-]+)').firstMatch(url);
    if (m2 != null) return m2.group(1);

    // Pattern 3: /sharing/link?surl=abcdef
    final m3 = RegExp(r'/sharing/link\?surl=([a-zA-Z0-9_-]+)').firstMatch(url);
    if (m3 != null) return m3.group(1);

    return null;
  }

  /// Resolves a TeraBox sharing URL into a direct playable CDN video stream URL.
  static Future<TeraBoxResult> resolve(String url, {Duration timeout = const Duration(seconds: 8)}) async {
    final cleanUrl = url.trim();
    final shortKey = extractShortUrl(cleanUrl);
    if (shortKey == null || shortKey.isEmpty) {
      return TeraBoxResult.failed(cleanUrl, 'Could not extract TeraBox shorturl identifier');
    }

    // Public worker endpoints that unpack TeraBox CDN streams
    final endpoints = [
      'https://terabox.hnn.workers.dev/api/get-info?shorturl=$shortKey&pwd=',
      'https://api.terabox.app/api?url=${Uri.encodeComponent(cleanUrl)}',
    ];

    final client = http.Client();
    try {
      for (final ep in endpoints) {
        try {
          final res = await client.get(
            Uri.parse(ep),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
              'Accept': 'application/json',
            },
          ).timeout(timeout);

          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            if (data is Map) {
              // Case A: hnn worker schema (list of files)
              if (data['ok'] == true && data['list'] is List && (data['list'] as List).isNotEmpty) {
                final fileItem = (data['list'] as List).first as Map;
                final filename = fileItem['filename']?.toString() ?? 'TeraBox Video';
                final dlink = fileItem['dlink']?.toString() ??
                    fileItem['fast_download_link']?.toString() ??
                    fileItem['download_link']?.toString();
                final size = int.tryParse(fileItem['size']?.toString() ?? '0') ?? 0;

                if (dlink != null && dlink.startsWith('http')) {
                  return TeraBoxResult.success(
                    originalUrl: cleanUrl,
                    streamUrl: dlink,
                    filename: filename,
                    fileSize: size,
                  );
                }
              }

              // Case B: direct download_url or url schema
              final dl = data['download_url']?.toString() ?? data['url']?.toString() ?? data['dlink']?.toString();
              if (dl != null && dl.startsWith('http')) {
                return TeraBoxResult.success(
                  originalUrl: cleanUrl,
                  streamUrl: dl,
                  filename: data['filename']?.toString() ?? 'TeraBox Video',
                  fileSize: int.tryParse(data['size']?.toString() ?? '0') ?? 0,
                );
              }
            }
          }
        } catch (_) {
          continue;
        }
      }
    } finally {
      client.close();
    }

    return TeraBoxResult.failed(cleanUrl, 'TeraBox public resolvers could not extract direct stream');
  }
}

class TeraBoxResult {
  final bool success;
  final String originalUrl;
  final String? streamUrl;
  final String? filename;
  final int fileSize;
  final String? error;

  String get fileSizeFormatted {
    if (fileSize <= 0) return '';
    if (fileSize >= 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
    return '${(fileSize / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  TeraBoxResult.success({
    required this.originalUrl,
    required this.streamUrl,
    required this.filename,
    required this.fileSize,
  })  : success = true,
        error = null;

  TeraBoxResult.failed(this.originalUrl, this.error)
      : success = false,
        streamUrl = null,
        filename = null,
        fileSize = 0;
}
