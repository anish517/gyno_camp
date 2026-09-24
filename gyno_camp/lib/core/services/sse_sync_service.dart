import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'http_central_api_service.dart';

/// Callback type for SSE sync events
typedef SseSyncCallback = void Function(Map<String, dynamic> eventData);

/// Service that connects to the central server's SSE endpoint
/// for real-time sync notifications. When the server pushes a
/// `sync_update` event, the callback fires immediately so the
/// SyncViewModel can trigger an instant pull.
class SseSyncService {
  final HttpCentralApiService _apiService;
  final SseSyncCallback? onSyncEvent;
  final String deviceId;

  http.Client? _client;
  StreamSubscription<String>? _subscription;
  Timer? _reconnectTimer;
  bool _isConnected = false;
  bool _isDisposed = false;
  int _reconnectAttempts = 0;
  static const int _maxReconnectDelaySec = 15;
  final http.Client Function()? _clientFactory;

  SseSyncService({
    HttpCentralApiService? apiService,
    this.onSyncEvent,
    this.deviceId = 'dev-field',
    this._clientFactory,
  }) : _apiService = apiService ?? HttpCentralApiService();

  bool get isConnected => _isConnected;

  /// Start listening for SSE events from the central server
  Future<void> connect() async {
    if (_isDisposed) return;
    if (_isConnected) return;

    final baseUrl = _apiService.baseUrl;
    final url = '$baseUrl/api/events?deviceId=${Uri.encodeComponent(deviceId)}';

    if (kDebugMode && (_reconnectAttempts <= 2 || _reconnectAttempts % 10 == 0)) {
      debugPrint('[SSE] Connecting to $url ...');
    }

    try {
      _client = _clientFactory != null ? _clientFactory() : http.Client();
      final request = http.Request('GET', Uri.parse(url));
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';

      final response = await _client!.send(request).timeout(
        const Duration(seconds: 5),
      );

      if (response.statusCode != 200) {
        if (kDebugMode && (_reconnectAttempts <= 2 || _reconnectAttempts % 10 == 0)) {
          debugPrint('[SSE] Server returned ${response.statusCode}, will retry');
        }
        _scheduleReconnect();
        return;
      }

      _isConnected = true;
      _reconnectAttempts = 0;

      if (kDebugMode) {
        debugPrint('[SSE] \u2713 Connected to real-time event stream');
      }

      // Parse SSE stream line-by-line
      String? currentEvent;
      String? currentData;

      _subscription = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (line.startsWith('event: ')) {
            currentEvent = line.substring(7).trim();
          } else if (line.startsWith('data: ')) {
            currentData = line.substring(6).trim();
          } else if (line.isEmpty && currentEvent != null && currentData != null) {
            // End of SSE message block
            _handleEvent(currentEvent!, currentData!);
            currentEvent = null;
            currentData = null;
          }
        },
        onError: (error) {
          if (kDebugMode) {
            debugPrint('[SSE] Stream error: $error');
          }
          _isConnected = false;
          if (!_isDisposed) _scheduleReconnect();
        },
        onDone: () {
          if (kDebugMode) {
            debugPrint('[SSE] Stream closed by server');
          }
          _isConnected = false;
          if (!_isDisposed) _scheduleReconnect();
        },
        cancelOnError: false,
      );
    } catch (e) {
      if (kDebugMode && (_reconnectAttempts <= 2 || _reconnectAttempts % 10 == 0)) {
        debugPrint('[SSE] Connection failed: $e');
      }
      _isConnected = false;
      if (!_isDisposed) _scheduleReconnect();
    }
  }

  void _handleEvent(String eventType, String data) {
    if (eventType == 'heartbeat') {
      // Server keepalive — ignore silently
      return;
    }

    if (eventType == 'connected') {
      if (kDebugMode) {
        debugPrint('[SSE] Server confirmed connection: $data');
      }
      return;
    }

    if (eventType == 'sync_update') {
      if (kDebugMode) {
        debugPrint('[SSE] 📡 Received sync_update: $data');
      }
      try {
        final parsed = jsonDecode(data) as Map<String, dynamic>;
        onSyncEvent?.call(parsed);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[SSE] Failed to parse event data: $e');
        }
      }
      return;
    }

    if (kDebugMode) {
      debugPrint('[SSE] Unknown event type: $eventType');
    }
  }

  /// Exponential backoff: 1s, 2s, 4s, 8s, 15s (capped)
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _cleanup();

    final delaySec = _reconnectAttempts < 4
        ? (1 << _reconnectAttempts) // 1, 2, 4, 8
        : _maxReconnectDelaySec;
    _reconnectAttempts++;

    if (kDebugMode && (_reconnectAttempts <= 2 || _reconnectAttempts % 10 == 0)) {
      debugPrint('[SSE] Reconnecting in ${delaySec}s (attempt $_reconnectAttempts)...');
    }

    _reconnectTimer = Timer(Duration(seconds: delaySec), () {
      if (!_isDisposed) connect();
    });
  }

  void _cleanup() {
    _subscription?.cancel();
    _subscription = null;
    _client?.close();
    _client = null;
    _isConnected = false;
  }

  /// Disconnect and stop reconnecting
  void dispose() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _cleanup();
    if (kDebugMode) {
      debugPrint('[SSE] Disposed');
    }
  }
}
