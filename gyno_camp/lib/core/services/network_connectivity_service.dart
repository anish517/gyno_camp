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
/// by periodically pinging the central server.
///
/// • Fires [onConnectivityChanged] automatically when the server comes back
///   online or goes offline — no manual calls needed.
/// • When a reconnect is detected, it also clears the HttpCentralApiService
///   offline cooldown so syncs are not blocked by the 30-second circuit breaker.
/// • Poll interval is short (5 s) so the UI updates within seconds of a
///   network change, giving a professional "just works" UX.
class NetworkConnectivityService implements INetworkConnectivityService {
  bool _isOnline;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  Timer? _pollTimer;

  /// How often to check reachability (5 seconds is fast enough to feel instant)
  static const Duration _pollInterval = Duration(seconds: 5);

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
    try {
      final reachable = await HttpCentralApiService().pingServer();

      final wasOffline = !_isOnline;
      if (reachable != _isOnline) {
        _isOnline = reachable;
        if (!_controller.isClosed) {
          _controller.add(_isOnline);
        }

        if (wasOffline && reachable) {
          // Server is back — immediately clear the circuit-breaker cooldown so
          // SyncViewModel.syncNow() is not blocked by the 30-second wait.
          HttpCentralApiService.markServerOnline();
          debugPrint('[Connectivity] 🟢 Server reachable — cooldown cleared, auto-sync will fire.');
        } else {
          debugPrint('[Connectivity] 🔴 Server unreachable — app switched to offline mode.');
        }
      }
    } catch (e) {
      // If the ping itself throws (e.g. no network at all), mark offline
      if (_isOnline) {
        _isOnline = false;
        if (!_controller.isClosed) {
          _controller.add(false);
        }
        debugPrint('[Connectivity] ⚠️ Ping threw: $e — switching to offline mode.');
      }
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
    if (_isOnline != online) {
      _isOnline = online;
      if (online) HttpCentralApiService.markServerOnline();
      _controller.add(_isOnline);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.close();
  }
}
