import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'config.dart';

/// Cloudflare Tunnel Manager for Hostreamio (Desktop & Android).
/// Inspired by CNCVerse-Bridge's CloudflaredManager.
/// Provides one-click public HTTPS Stremio & Nuvio addon endpoints
/// (e.g. https://my-hostreamio.domain.com/manifest.json) without port forwarding.
class CloudflareTunnelService {
  static final CloudflareTunnelService instance = CloudflareTunnelService._();
  CloudflareTunnelService._();

  Process? _process;
  String? _activeTunnelUrl;
  bool _isStarting = false;
  final _logController = StreamController<String>.broadcast();

  String? get activeTunnelUrl => _activeTunnelUrl;
  bool get isRunning => _process != null;
  bool get isStarting => _isStarting;
  Stream<String> get logStream => _logController.stream;

  /// Checks if cloudflared binary is installed on PATH or in current directory
  Future<bool> isInstalled() async {
    try {
      final res = await Process.run('cloudflared', ['--version']);
      return res.exitCode == 0;
    } catch (_) {
      final local = File(Platform.isWindows ? 'cloudflared.exe' : 'cloudflared');
      return local.existsSync();
    }
  }

  /// Starts the Cloudflare Tunnel
  Future<bool> startTunnel({int port = 7000}) async {
    if (_process != null) {
      print('[CloudflareTunnel] Tunnel already running at $_activeTunnelUrl');
      return true;
    }

    _isStarting = true;
    final cfg = AddonConfig.instance;
    final token = cfg.cloudflareTunnelToken.trim();

    final List<String> args = [];
    if (token.isNotEmpty) {
      // User's own Zero Trust tunnel
      args.addAll(['tunnel', 'run', '--token', token]);
    } else {
      // Free quick tunnel
      args.addAll(['tunnel', '--url', 'http://127.0.0.1:$port', '--no-autoupdate']);
    }

    try {
      String exec = 'cloudflared';
      final local = File(Platform.isWindows ? 'cloudflared.exe' : 'cloudflared');
      if (local.existsSync()) {
        exec = local.absolute.path;
      }

      print('[CloudflareTunnel] Starting cloudflared tunnel for local port $port...');
      _process = await Process.start(exec, args);

      _process!.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _handleOutput(line));

      _process!.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => _handleOutput(line));

      _process!.exitCode.then((code) {
        print('[CloudflareTunnel] cloudflared exited with code $code');
        _process = null;
        _activeTunnelUrl = null;
        _isStarting = false;
      });

      _isStarting = false;
      return true;
    } catch (e) {
      print('[CloudflareTunnel] Failed to start cloudflared: $e');
      _isStarting = false;
      _process = null;
      _activeTunnelUrl = null;
      return false;
    }
  }

  void _handleOutput(String line) {
    if (line.trim().isEmpty) return;
    _logController.add(line);

    // Extract quick tunnel URL: e.g. https://random-name.trycloudflare.com
    final match = RegExp(r'https://[a-zA-Z0-9-]+\.trycloudflare\.com').firstMatch(line);
    if (match != null) {
      _activeTunnelUrl = match.group(0);
      print('[CloudflareTunnel] 🚀 Public Cloudflare Tunnel Ready: $_activeTunnelUrl');
    }

    if (line.contains('Registered tunnel connection')) {
      print('[CloudflareTunnel] 🚀 Tunnel connected successfully to Cloudflare Edge.');
    }
  }

  /// Stops the running tunnel
  void stopTunnel() {
    if (_process != null) {
      try {
        _process!.kill();
      } catch (_) {}
      _process = null;
      _activeTunnelUrl = null;
      _isStarting = false;
      print('[CloudflareTunnel] Tunnel stopped.');
    }
  }
}
