import 'dart:async';
import 'package:flutter/foundation.dart';
import 'http_central_api_service.dart';

abstract class INetworkConnectivityService {
  bool get isOnline;
  Stream<bool> get onConnectivityChanged;
  Future<bool> checkConnection();
  void setOnline(bool online);
  void dispose();
}

/// Real network connectivity service that auto-detects server reachability
/// by periodically pinging the single configured central server.
///
/// • Fires [onConnectivityChanged] automatically when the server comes back
///   online or goes offline — no manual calls needed.
/// • Skips background health-check pings while an active API or Cloud OCR
///   request is already in flight, and requires 2 consecutive failed polls
///   before switching online -> offline to prevent transient flapping during
///   heavy image uploads.
/// • When a reconnect is detected, it clears the HttpCentralApiService
///   offline cooldown so syncs are not blocked by the 30-second circuit breaker.
class NetworkConnectivityService implements INetworkConnectivityService {
  bool _isOnline;
  bool _isChecking = false;
  int _consecutiveFailures = 0;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  Timer? _pollTimer;

  /// Background reachability poll interval (SSE handles instant real-time pushes).
  static const Duration _pollInterval = Duration(seconds: 10);

  /// Consecutive failed background pings required before transitioning online -> offline.
  static const int _failuresBeforeOffline = 2;

  NetworkConnectivityService({
    bool initialOnline = true,
    bool autoStartPolling = true,
  }) : _isOnline = initialOnline {
    if (autoStartPolling) {
      _startPolling();
    }
  }

  void _startPolling() {
    // Run an immediate check, then poll on a fixed interval
    _checkAndUpdate();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _checkAndUpdate());
  }

  Future<void> _checkAndUpdate() async {
    if (_isChecking || _controller.isClosed) return;

    // Do not interrupt or flap connectivity while an active API / Gemini OCR
    // request is currently communicating with the central server.
    if (HttpCentralApiService.hasActiveRequest && _isOnline) {
      _consecutiveFailures = 0;
      return;
    }

    _isChecking = true;
    try {
      final reachable = await HttpCentralApiService().pingServer();
      if (_controller.isClosed) return;

      if (reachable) {
        _consecutiveFailures = 0;
        if (!_isOnline) {
          _isOnline = true;
          _controller.add(true);
          HttpCentralApiService.markServerOnline();
          debugPrint('[Connectivity] 🟢 Server reachable — cooldown cleared, auto-sync will fire.');
        }
      } else {
        _consecutiveFailures++;
        if (_isOnline && _consecutiveFailures >= _failuresBeforeOffline) {
          _isOnline = false;
          _controller.add(false);
          debugPrint('[Connectivity] 🔴 Server unreachable — app switched to offline mode.');
        }
      }
    } catch (e) {
      _consecutiveFailures++;
      if (_isOnline &&
          _consecutiveFailures >= _failuresBeforeOffline &&
          !_controller.isClosed) {
        _isOnline = false;
        _controller.add(false);
        debugPrint('[Connectivity] ⚠️ Ping threw: $e — switching to offline mode.');
      }
    } finally {
      _isChecking = false;
    }
  }

  @override
  bool get isOnline => _isOnline;

  @override
  Stream<bool> get onConnectivityChanged => _controller.stream;

  @override
  Future<bool> checkConnection() => HttpCentralApiService().pingServer();

  /// Manual override — used by tests and the settings toggle simulation
  @override
  void setOnline(bool online) {
    _consecutiveFailures = 0;
    if (_isOnline != online) {
      _isOnline = online;
      if (online) HttpCentralApiService.markServerOnline();
      if (!_controller.isClosed) {
        _controller.add(_isOnline);
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.close();
  }
}
