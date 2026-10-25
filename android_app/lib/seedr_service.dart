import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'config.dart';

/// SeedrService: Integrates Seedr.cc Free Tier Cloud Torrents (up to 2GB)
/// for instant streaming of anime, TV episodes, and small web releases
/// without consuming paid debrid bandwidth.
class SeedrService {
  static final SeedrService instance = SeedrService._();

  SeedrService._();

  static const String _apiBase = 'https://www.seedr.cc/api';

  Map<String, String> _headers(String token, {String username = '', String password = ''}) {
    final h = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    };
    if (token.isNotEmpty) {
      h['Authorization'] = 'Bearer $token';
    } else if (username.isNotEmpty && password.isNotEmpty) {
      final creds = base64Encode(utf8.encode('$username:$password'));
      h['Authorization'] = 'Basic $creds';
    }
    return h;
  }

  /// Checks if Seedr credentials are configured in AddonConfig.
  bool get isConfigured {
    final cfg = AddonConfig.instance;
    return cfg.seedrToken.trim().isNotEmpty ||
        (cfg.seedrUsername.trim().isNotEmpty && cfg.seedrPassword.trim().isNotEmpty);
  }

  /// Resolves a torrent magnet on Seedr.cc cloud.
  Future<SeedrResolveResult> resolveMagnet(
    String magnetUri, {
    int? maxSizeBytes,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final cfg = AddonConfig.instance;
    final token = cfg.seedrToken.trim();
    final username = cfg.seedrUsername.trim();
    final password = cfg.seedrPassword.trim();

    if (!isConfigured) {
      return SeedrResolveResult.failed(magnetUri, 'Seedr.cc credentials not configured');
    }

    // Free tier max file size is 2GB (2 * 1024 * 1024 * 1024 bytes)
    const maxFreeBytes = 2 * 1024 * 1024 * 1024;
    if (maxSizeBytes != null && maxSizeBytes > maxFreeBytes) {
      return SeedrResolveResult.failed(magnetUri, 'Torrent exceeds Seedr 2GB free cloud limit');
    }

    final client = http.Client();
    try {
      final headers = _headers(token, username: username, password: password);

      // 1. Post magnet to Seedr
      final addRes = await client.post(
        Uri.parse('$_apiBase/torrent/magnet'),
        headers: headers,
        body: {'magnet': magnetUri},
      ).timeout(timeout);

      if (addRes.statusCode != 200 && addRes.statusCode != 201) {
        return SeedrResolveResult.failed(magnetUri, 'Failed to add magnet to Seedr');
      }

      // 2. Poll briefly for instant cached folder
      String? folderId;
      for (int i = 0; i < 4; i++) {
        await Future.delayed(const Duration(milliseconds: 800));
        final folderRes = await client.get(
          Uri.parse('$_apiBase/folder'),
          headers: headers,
        ).timeout(const Duration(seconds: 4));

        if (folderRes.statusCode == 200) {
          final data = jsonDecode(folderRes.body);
          if (data is Map && data['folders'] is List && (data['folders'] as List).isNotEmpty) {
            folderId = (data['folders'] as List).first['id']?.toString();
            break;
          }
        }
      }

      if (folderId == null) {
        return SeedrResolveResult.failed(magnetUri, 'Torrent not instantly cached on Seedr');
      }

      // 3. Inspect folder files to retrieve direct streamable media file
      final filesRes = await client.get(
        Uri.parse('$_apiBase/folder/$folderId'),
        headers: headers,
      ).timeout(const Duration(seconds: 4));

      if (filesRes.statusCode == 200) {
        final data = jsonDecode(filesRes.body);
        if (data is Map && data['files'] is List && (data['files'] as List).isNotEmpty) {
          final files = data['files'] as List;
          // Pick largest video file
          files.sort((a, b) => (b['size'] ?? 0).compareTo(a['size'] ?? 0));
          final best = files.first;
          final fileId = best['id']?.toString();

          if (fileId != null) {
            final urlRes = await client.get(
              Uri.parse('$_apiBase/file/$fileId/url'),
              headers: headers,
            ).timeout(const Duration(seconds: 4));

            if (urlRes.statusCode == 200) {
              final urlData = jsonDecode(urlRes.body);
              final streamUrl = urlData['url']?.toString();
              if (streamUrl != null && streamUrl.isNotEmpty) {
                return SeedrResolveResult.success(
                  originalUrl: magnetUri,
                  streamUrl: streamUrl,
                  filename: best['name']?.toString() ?? 'Seedr Video',
                  fileSize: int.tryParse(best['size']?.toString() ?? '0') ?? 0,
                );
              }
            }
          }
        }
      }
    } catch (e) {
      return SeedrResolveResult.failed(magnetUri, 'Seedr error: $e');
    } finally {
      client.close();
    }

    return SeedrResolveResult.failed(magnetUri, 'Could not retrieve Seedr stream URL');
  }
}

class SeedrResolveResult {
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

  SeedrResolveResult.success({
    required this.originalUrl,
    required this.streamUrl,
    required this.filename,
    required this.fileSize,
  })  : success = true,
        error = null;

  SeedrResolveResult.failed(this.originalUrl, this.error)
      : success = false,
        streamUrl = null,
        filename = null,
        fileSize = 0;
}
