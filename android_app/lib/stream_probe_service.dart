import 'dart:async';
import 'dart:io';

/// StreamProbeService inspired by CNCVerse-Bridge's SeekProbe.
/// Lightweight HTTP byte-range & content probing that:
/// 1. Drops unplayable archive files (.zip, .rar, .7z) and HTML landing/error pages.
/// 2. Performs a fast `Range: bytes=0-0` probe with ExoPlayer user agent.
/// 3. Extracts exact Content-Length (true file size) from `Content-Range: bytes 0-0/<total_bytes>`.
/// 4. Validates byte-range seekability (HTTP 206 vs HTTP 200).
/// 5. Automatically detects container formats (MKV, MP4, HLS, DASH).
/// 6. Caches verdicts in memory with TTL to ensure near-zero latency on subsequent requests.
class StreamProbeResult {
  final bool isPlayable;
  final bool isSeekable;
  final int? totalSizeBytes;
  final String? fileSizeFormatted;
  final String? detectedFileType;
  final String? contentType;
  final int statusCode;

  const StreamProbeResult({
    required this.isPlayable,
    required this.isSeekable,
    this.totalSizeBytes,
    this.fileSizeFormatted,
    this.detectedFileType,
    this.contentType,
    required this.statusCode,
  });

  static const unverified = StreamProbeResult(
    isPlayable: true,
    isSeekable: true,
    statusCode: 0,
  );
}

class StreamProbeService {
  static final StreamProbeService instance = StreamProbeService._();
  StreamProbeService._();

  static const _archivePattern = r'\.(zip|rar|7z|tar|gz|tgz|r[0-9]{2}|z[0-9]{2})(\?|#|$)';
  static final _archiveRegex = RegExp(_archivePattern, caseSensitive: false);

  static final _archiveTypes = {
    'zip',
    'x-rar',
    'vnd.rar',
    'x-7z',
    'x-tar',
    'gzip',
    'x-compressed',
  };

  /// In-memory cache: URL -> (result, timestampMs)
  final Map<String, _CachedProbe> _cache = {};
  static const int _cacheTtlMs = 4 * 60 * 60 * 1000; // 4 hours

  static final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(milliseconds: 1500)
    ..badCertificateCallback = ((_, __, ___) => true);

  /// Quick static check if URL points to an archive file
  static bool isArchiveUrl(String url) {
    if (url.isEmpty) return false;
    try {
      final uri = Uri.parse(url);
      return _archiveRegex.hasMatch(uri.path);
    } catch (_) {
      return false;
    }
  }

  /// Converts bytes to clean human-readable size (e.g. 1.45 GB or 650 MB)
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '';
    const kb = 1024.0;
    const mb = kb * 1024.0;
    const gb = mb * 1024.0;
    const tb = gb * 1024.0;

    if (bytes >= tb) {
      return '${(bytes / tb).toStringAsFixed(2)} TB';
    } else if (bytes >= gb) {
      return '${(bytes / gb).toStringAsFixed(2)} GB';
    } else if (bytes >= mb) {
      return '${(bytes / mb).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / kb).toStringAsFixed(0)} KB';
    }
  }

  /// Probes a direct streaming URL with `Range: bytes=0-0`
  Future<StreamProbeResult> probeStream(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    if (url.isEmpty || !url.startsWith('http')) {
      return StreamProbeResult.unverified;
    }

    // 1. Skip HLS/DASH manifests from byte probing (they don't use range requests)
    final lower = url.toLowerCase();
    if (lower.contains('.m3u8') || lower.contains('/hls/') || lower.contains('master.m3u8')) {
      return const StreamProbeResult(
        isPlayable: true,
        isSeekable: true,
        detectedFileType: 'HLS / M3U8',
        statusCode: 200,
      );
    }
    if (lower.contains('.mpd') || lower.contains('/dash/')) {
      return const StreamProbeResult(
        isPlayable: true,
        isSeekable: true,
        detectedFileType: 'DASH',
        statusCode: 200,
      );
    }

    // 2. Reject obvious archive downloads immediately without network
    if (isArchiveUrl(url)) {
      return const StreamProbeResult(
        isPlayable: false,
        isSeekable: false,
        statusCode: 415,
      );
    }

    // 3. Check cached probe result
    final now = DateTime.now().millisecondsSinceEpoch;
    final cached = _cache[url];
    if (cached != null && (now - cached.timestampMs) < _cacheTtlMs) {
      return cached.result;
    }

    try {
      final uri = Uri.parse(url);
      final req = await _client.getUrl(uri).timeout(timeout);

      // ExoPlayer range probe headers
      req.headers.set('Range', 'bytes=0-0');
      req.headers.set('User-Agent', 'ExoPlayerLib/2.19.1 (Hostreamio)');
      req.headers.set('Accept', '*/*');
      req.headers.set('Connection', 'close');

      // Forward any custom scraper headers (Referer, Origin, etc.)
      if (headers != null && headers.isNotEmpty) {
        headers.forEach((k, v) {
          if (k.toLowerCase() != 'range' && k.toLowerCase() != 'user-agent') {
            req.headers.set(k, v);
          }
        });
      }

      final res = await req.close().timeout(timeout);
      final status = res.statusCode;
      final cType = res.headers.contentType?.value.toLowerCase() ?? 
                    res.headers.value('content-type')?.toLowerCase() ?? '';

      // Clean drain without buffering large response
      await res.drain<void>();

      // Check for HTML download errors / landing pages
      if (cType.startsWith('text/html')) {
        final result = StreamProbeResult(
          isPlayable: false,
          isSeekable: false,
          contentType: cType,
          statusCode: status,
        );
        _cache[url] = _CachedProbe(result, now);
        return result;
      }

      // Check for application archive Content-Types
      for (final arch in _archiveTypes) {
        if (cType.contains('application/$arch')) {
          final result = StreamProbeResult(
            isPlayable: false,
            isSeekable: false,
            contentType: cType,
            statusCode: status,
          );
          _cache[url] = _CachedProbe(result, now);
          return result;
        }
      }

      // 404 Not Found or 410 Gone means dead link
      if (status == 404 || status == 410) {
        final result = StreamProbeResult(
          isPlayable: false,
          isSeekable: false,
          statusCode: status,
        );
        _cache[url] = _CachedProbe(result, now);
        return result;
      }

      // Extract total size from Content-Range: bytes 0-0/12345678
      int? totalBytes;
      final cRange = res.headers.value('content-range');
      if (cRange != null && cRange.isNotEmpty) {
        final match = RegExp(r'bytes\s+\d+-\d+/(\d+)').firstMatch(cRange);
        if (match != null) {
          totalBytes = int.tryParse(match.group(1) ?? '');
        }
      }

      // If Content-Range not present, check Content-Length if status == 200
      if (totalBytes == null && status == 200) {
        final cLen = res.headers.contentLength;
        if (cLen > 0) totalBytes = cLen;
      }

      final isSeekable = status == 206;
      final sizeFormatted = totalBytes != null && totalBytes > 0 ? formatBytes(totalBytes) : null;

      // Detect container file type
      String? fileType;
      if (cType.contains('matroska') || lower.contains('.mkv')) {
        fileType = 'MKV';
      } else if (cType.contains('mp4') || lower.contains('.mp4') || lower.contains('.m4v')) {
        fileType = 'MP4';
      } else if (cType.contains('webm') || lower.contains('.webm')) {
        fileType = 'WEBM';
      } else if (cType.contains('mpegurl') || lower.contains('.m3u8')) {
        fileType = 'HLS / M3U8';
      } else if (lower.contains('.avi')) {
        fileType = 'AVI';
      }

      final result = StreamProbeResult(
        isPlayable: true,
        isSeekable: isSeekable,
        totalSizeBytes: totalBytes,
        fileSizeFormatted: sizeFormatted,
        detectedFileType: fileType,
        contentType: cType,
        statusCode: status,
      );

      _cache[url] = _CachedProbe(result, now);
      return result;
    } catch (_) {
      // On probe timeout or network block, assume playable to avoid false dropping
      return StreamProbeResult.unverified;
    }
  }
}

class _CachedProbe {
  final StreamProbeResult result;
  final int timestampMs;
  _CachedProbe(this.result, this.timestampMs);
}
