import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/camp_model.dart';
import '../../models/clinical_visit_model.dart';
import '../../models/lookup_item_model.dart';
import '../../models/patient_model.dart';
import '../../models/sync_payload_model.dart';
import '../../models/user_model.dart';
import '../../models/device_model.dart';
import 'central_api_service.dart';
import '../security/security_service.dart';

import 'session_service.dart';

class HttpCentralApiService implements ICentralApiService {
  final String? _customBaseUrl;
  final http.Client _client;
  static String? _activeBaseUrl;
  static bool _isServerReachable = true;
  static DateTime? _lastOfflineCheck;
  static int _inFlightRequests = 0;
  static const Duration _offlineCooldown = Duration(seconds: 30);

  /// Obsolete hardcoded LAN/hotspot IPs from legacy dev builds that may still
  /// be persisted in SharedPreferences / browser localStorage.
  static const Set<String> _legacyObsoleteHosts = {
    '192.168.1.4',
    '192.168.1.13',
    '192.168.1.110',
    '192.168.16.113',
  };

  /// Returns true if [rawUrl] points to one of the retired hardcoded dev IPs.
  static bool isLegacyObsoleteUrl(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) return false;
    final trimmed = rawUrl.trim();
    if (_legacyObsoleteHosts.contains(trimmed)) return true;
    final uri = Uri.tryParse(trimmed);
    return uri != null && _legacyObsoleteHosts.contains(uri.host);
  }

  static String _normalizeUrl(String raw) {
    final trimmed = raw.trim();
    return trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
  }

  /// Platform- and deployment-aware single default Central Server URL.
  ///
  /// - Production builds (`--dart-define=CENTRAL_SERVER_URL=...`): uses that exact URL.
  /// - Web (`kIsWeb`):
  ///   - Local dev (`localhost` / `127.0.0.1`): `http://localhost:8080`.
  ///   - Reverse-proxied deployment (HTTPS or ports 80/443): same origin (`Uri.base.origin`).
  ///   - LAN dev host (`http://<lan-ip>:<dev-port>`): `http://<lan-ip>:8080`.
  /// - Native (Desktop / Android via `adb reverse`): `http://localhost:8080`.
  static String get defaultServerUrl {
    const envUrl = String.fromEnvironment(
      'CENTRAL_SERVER_URL',
      defaultValue: '',
    );
    if (envUrl.isNotEmpty) {
      return _normalizeUrl(envUrl);
    }

    if (kIsWeb) {
      final host = Uri.base.host;
      if (host.isEmpty || host == 'localhost' || host == '127.0.0.1') {
        return 'http://localhost:8080';
      }
      if (Uri.base.scheme == 'https' ||
          Uri.base.port == 80 ||
          Uri.base.port == 443) {
        return _normalizeUrl(Uri.base.origin);
      }
      return '${Uri.base.scheme}://$host:8080';
    }

    return 'http://localhost:8080';
  }

  /// True while an active API or Cloud OCR request is communicating with the server.
  static bool get hasActiveRequest => _inFlightRequests > 0;

  static void beginActiveRequest() {
    _inFlightRequests++;
  }

  static void endActiveRequest() {
    if (_inFlightRequests > 0) {
      _inFlightRequests--;
    }
  }

  @visibleForTesting
  static void resetStaticStateForTest() {
    _activeBaseUrl = null;
    _isServerReachable = true;
    _lastOfflineCheck = null;
    _inFlightRequests = 0;
  }

  /// Checks whether a central cloud server is configured or enabled
  static bool get isServerConfigured {
    final active = _activeBaseUrl;
    if (active != null && active.isNotEmpty) return true;
    const envUrl = String.fromEnvironment(
      'CENTRAL_SERVER_URL',
      defaultValue: '',
    );
    if (envUrl.isNotEmpty) return true;
    try {
      final config = SessionService.current?.getPostgresConfig();
      if (config != null &&
          (config.isDirectModeEnabled || config.host.isNotEmpty)) {
        return true;
      }
    } catch (_) {}
    return true;
  }

  /// True if this instance has a custom URL or a central server is configured
  bool get isConfigured {
    final custom = _customBaseUrl;
    if (custom != null && custom.isNotEmpty) return true;
    return isServerConfigured;
  }

  /// Checks if the circuit breaker is currently open (server was recently unreachable)
  static bool get isServerCooldownActive {
    if (_isServerReachable) return false;
    final last = _lastOfflineCheck;
    if (last == null) return false;
    if (DateTime.now().difference(last) < _offlineCooldown) {
      return true;
    }
    return false;
  }

  static void markServerOffline() {
    _isServerReachable = false;
    _lastOfflineCheck = DateTime.now();
  }

  static void markServerOnline([String? url]) {
    _isServerReachable = true;
    _lastOfflineCheck = null;
    if (url != null && url.isNotEmpty && !isLegacyObsoleteUrl(url)) {
      _activeBaseUrl = _normalizeUrl(url);
    }
  }

  HttpCentralApiService({String? baseUrl, http.Client? client})
    : _customBaseUrl = baseUrl,
      _client = client ?? http.Client();

  String get baseUrl {
    final customUrl = _customBaseUrl;
    if (customUrl != null && customUrl.trim().isNotEmpty) {
      return _normalizeUrl(customUrl);
    }

    // 1. Explicit compile-time deployment flag (--dart-define=CENTRAL_SERVER_URL=...)
    //    is ALWAYS the single authoritative endpoint in deployed builds.
    const envUrl = String.fromEnvironment(
      'CENTRAL_SERVER_URL',
      defaultValue: '',
    );
    if (envUrl.isNotEmpty) {
      return _normalizeUrl(envUrl);
    }

    // 2. Verified active URL (ignoring retired hardcoded dev IPs)
    final activeUrl = _activeBaseUrl;
    if (activeUrl != null &&
        activeUrl.isNotEmpty &&
        !isLegacyObsoleteUrl(activeUrl)) {
      return _normalizeUrl(activeUrl);
    }

    // 3. User-configured saved URL from preferences (self-heal obsolete legacy IPs)
    try {
      final savedUrl = SessionService.current?.getCentralServerUrl();
      if (savedUrl != null && savedUrl.trim().isNotEmpty) {
        if (isLegacyObsoleteUrl(savedUrl)) {
          SessionService.current?.saveCentralServerUrl(defaultServerUrl);
        } else {
          return _normalizeUrl(savedUrl);
        }
      }
    } catch (_) {}

    // 4. Native PostgreSQL host fallback (for tablets configured via PG host)
    if (!kIsWeb) {
      try {
        final configuredHost = SessionService.current?.getPostgresConfig().host;
        if (configuredHost != null &&
            configuredHost.trim().isNotEmpty &&
            configuredHost != 'localhost' &&
            configuredHost != '127.0.0.1' &&
            !isLegacyObsoleteUrl(configuredHost)) {
          final host = configuredHost.trim();
          return _normalizeUrl(
            host.startsWith('http') ? host : 'http://$host:8080',
          );
        }
      } catch (_) {}
    }

    return defaultServerUrl;
  }

  bool simulateNetworkFailure = false;

  @override
  List<ClinicalVisitModel> get serverStoredVisits => const [];

  @override
  List<PatientModel> get serverStoredPatients => const [];

  @override
  void setMockServerCamps(List<CampModel> camps) {}

  @override
  void setMockServerLookupItems(List<LookupItemModel> items) {}

  /// Ensures the service has verified a live connection to the Central Server.
  Future<bool> ensureServerConnected() async {
    if (_customBaseUrl != null) return true;
    if (_activeBaseUrl != null && _isServerReachable) return true;
    return await pingServer();
  }

  @override
  Future<bool> pingServer() async {
    if (simulateNetworkFailure) {
      if (_customBaseUrl == null) markServerOffline();
      return false;
    }

    // Instance with explicit custom baseUrl (e.g. unit tests): test ONLY that endpoint.
    final custom = _customBaseUrl;
    if (custom != null && custom.trim().isNotEmpty) {
      return _testEndpoint(_normalizeUrl(custom));
    }

    // If an active API / Cloud OCR request is currently communicating with the server,
    // skip redundant health-check probing so we don't cause contention or false timeouts.
    if (_inFlightRequests > 0 && _isServerReachable) {
      return true;
    }

    // Test ONLY the single authoritative resolved server URL (never spray multiple LAN IPs).
    final target = baseUrl;
    if (target.isEmpty) {
      markServerOffline();
      return false;
    }

    if (await _testEndpoint(target)) {
      markServerOnline(target);
      return true;
    }

    // Local dev self-healing ONLY when CENTRAL_SERVER_URL is not compiled in:
    // If a manually saved LAN IP in Settings became stale after a router DHCP change,
    // check the platform default (e.g. http://localhost:8080) once before marking offline.
    const envUrl = String.fromEnvironment(
      'CENTRAL_SERVER_URL',
      defaultValue: '',
    );
    if (envUrl.isEmpty) {
      final fallbackDefault = defaultServerUrl;
      if (fallbackDefault != target && await _testEndpoint(fallbackDefault)) {
        markServerOnline(fallbackDefault);
        try {
          SessionService.current?.saveCentralServerUrl(fallbackDefault);
        } catch (_) {}
        return true;
      }
    }

    markServerOffline();
    return false;
  }

  Future<bool> _testEndpoint(String targetUrl) async {
    try {
      final uri = Uri.parse('$targetUrl/health');
      final res = await _client
          .get(uri)
          .timeout(const Duration(milliseconds: 4000));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<SyncPushResponse> pushDelta(SyncPushPayload payload) async {
    if (_customBaseUrl == null && (_activeBaseUrl == null || !_isServerReachable)) {
      await pingServer();
    }
    beginActiveRequest();
    try {
      final uri = Uri.parse('$baseUrl/api/sync/push');
      final body = jsonEncode(payload.toMap());
      final res = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: body,
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200 || res.statusCode == 201) {
        if (_customBaseUrl == null) markServerOnline(baseUrl);
        final data =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return SyncPushResponse.fromMap(data);
      } else {
        throw Exception(
          'Central server returned HTTP ${res.statusCode}: ${res.body}',
        );
      }
    } catch (e) {
      if (_customBaseUrl == null) markServerOffline();
      debugPrint('HttpCentralApiService pushDelta error: $e');
      rethrow;
    } finally {
      endActiveRequest();
    }
  }

  @override
  Future<SyncPullResponse> pullDelta({
    DateTime? since,
    required String deviceId,
  }) async {
    if (_customBaseUrl == null && (_activeBaseUrl == null || !_isServerReachable)) {
      await pingServer();
    }
    beginActiveRequest();
    try {
      var urlStr = '$baseUrl/api/sync/pull?deviceId=$deviceId';
      if (since != null) {
        urlStr += '&since=${Uri.encodeComponent(since.toIso8601String())}';
      }
      final uri = Uri.parse(urlStr);
      final res = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        if (_customBaseUrl == null) markServerOnline(baseUrl);
        final data =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return SyncPullResponse.fromMap(data);
      } else {
        throw Exception(
          'Central server returned HTTP ${res.statusCode}: ${res.body}',
        );
      }
    } catch (e) {
      if (_customBaseUrl == null) markServerOffline();
      debugPrint('HttpCentralApiService pullDelta error: $e');
      rethrow;
    } finally {
      endActiveRequest();
    }
  }

  /// Sends a newly created or updated Camp directly to the Central Cloud
  Future<bool> broadcastCamp(CampModel camp) async {
    if (!isConfigured || isServerCooldownActive) return false;
    try {
      final uri = Uri.parse('$baseUrl/api/camps');
      final res = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(camp.toMap()),
          )
          .timeout(const Duration(seconds: 3));
      final ok = res.statusCode == 200 || res.statusCode == 201;
      if (ok && _customBaseUrl == null) markServerOnline(baseUrl);
      return ok;
    } catch (e) {
      if (_customBaseUrl == null) markServerOffline();
      return false;
    }
  }

  /// Deletes a Camp from the Central Cloud API
  Future<bool> deleteCentralCamp(String campId) async {
    if (!isConfigured || isServerCooldownActive) return false;
    try {
      final uri = Uri.parse('$baseUrl/api/camps?id=$campId');
      final res = await _client.delete(uri).timeout(const Duration(seconds: 3));
      final ok = res.statusCode == 200 || res.statusCode == 204;
      if (ok && _customBaseUrl == null) markServerOnline(baseUrl);
      return ok;
    } catch (e) {
      if (_customBaseUrl == null) markServerOffline();
      return false;
    }
  }

  /// Sends a newly created or updated User directly to the Central Cloud
  Future<bool> broadcastUser(UserModel user) async {
    if (!isConfigured || isServerCooldownActive) return false;
    try {
      final uri = Uri.parse('$baseUrl/api/users');
      final res = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(user.toMap()),
          )
          .timeout(const Duration(seconds: 3));
      final ok = res.statusCode == 200 || res.statusCode == 201;
      if (ok && _customBaseUrl == null) markServerOnline(baseUrl);
      return ok;
    } catch (e) {
      if (_customBaseUrl == null) markServerOffline();
      return false;
    }
  }

  /// Deletes a User directly from the Central Cloud Server
  Future<bool> deleteCentralUser(String userId) async {
    if (!isConfigured || isServerCooldownActive) return false;
    try {
      final uri = Uri.parse('$baseUrl/api/users?id=$userId');
      final res = await _client.delete(uri).timeout(const Duration(seconds: 3));
      final ok = res.statusCode == 200 || res.statusCode == 204;
      if (ok && _customBaseUrl == null) markServerOnline(baseUrl);
      return ok;
    } catch (e) {
      if (_customBaseUrl == null) markServerOffline();
      return false;
    }
  }

  /// Atomically updates the organization / tenant name across all camps and users on the Central Cloud Server
  Future<bool> renameTenant({
    required String tenantId,
    required String newOrgName,
  }) async {
    if (!isConfigured || isServerCooldownActive) return false;
    try {
      final uri = Uri.parse('$baseUrl/api/tenant/rename');
      final res = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'tenant_id': tenantId,
              'organization_name': newOrgName,
            }),
          )
          .timeout(const Duration(seconds: 4));
      final ok = res.statusCode == 200 || res.statusCode == 201;
      if (ok && _customBaseUrl == null) markServerOnline(baseUrl);
      return ok;
    } catch (e) {
      if (_customBaseUrl == null) markServerOffline();
      return false;
    }
  }

  /// Fetches all active camps from the Central Cloud API
  Future<List<CampModel>> fetchCentralCamps({
    bool bypassCooldown = false,
  }) async {
    if (!isConfigured) return [];
    if (!bypassCooldown && isServerCooldownActive) return [];
    await ensureServerConnected();
    try {
      final uri = Uri.parse('$baseUrl/api/camps');
      final res = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        if (_customBaseUrl == null) markServerOnline(baseUrl);
        final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
        return list
            .map((item) => CampModel.fromMap(item as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      if (!bypassCooldown && _customBaseUrl == null) markServerOffline();
    }
    return [];
  }

  /// Fetches all staff users from the Central Cloud API
  Future<List<UserModel>> fetchCentralUsers({
    bool bypassCooldown = false,
  }) async {
    if (!isConfigured) return [];
    if (!bypassCooldown && isServerCooldownActive) return [];
    await ensureServerConnected();
    try {
      final uri = Uri.parse('$baseUrl/api/users');
      final res = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        if (_customBaseUrl == null) markServerOnline(baseUrl);
        final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
        return list
            .map((item) => UserModel.fromMap(item as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      if (!bypassCooldown && _customBaseUrl == null) markServerOffline();
    }
    return [];
  }

  /// Broadcasts device registration/update to the Central Cloud Server
  Future<bool> broadcastDevice(DeviceModel device) async {
    if (!isConfigured || isServerCooldownActive) return false;
    await ensureServerConnected();
    try {
      final uri = Uri.parse('$baseUrl/api/devices');
      final headers = <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
      };
      // Bind this device's secret server-side ONLY when registering our own device.
      // (Admins re-broadcast other devices' records; never attach our secret to those.)
      try {
        if (device.hardwareFingerprint ==
            SecurityService.generateDeviceFingerprint()) {
          final secret =
              SessionService.current?.getOrCreateDeviceSecret() ?? '';
          if (secret.length >= 32) headers['X-Device-Secret'] = secret;
        }
      } catch (_) {}
      final res = await _client
          .post(uri, headers: headers, body: jsonEncode(device.toMap()))
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200 || res.statusCode == 201) {
        if (_customBaseUrl == null) markServerOnline(baseUrl);
        return true;
      }
    } catch (e) {
      if (_customBaseUrl == null) markServerOffline();
    }
    return false;
  }

  /// Fetches all devices known to the Central Cloud Server
  Future<List<DeviceModel>> fetchCentralDevices({
    bool bypassCooldown = false,
  }) async {
    if (!isConfigured) return [];
    if (!bypassCooldown && isServerCooldownActive) return [];
    await ensureServerConnected();
    try {
      final uri = Uri.parse('$baseUrl/api/devices');
      final res = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        if (_customBaseUrl == null) markServerOnline(baseUrl);
        final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
        return list
            .map((item) => DeviceModel.fromMap(item as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      if (!bypassCooldown && _customBaseUrl == null) markServerOffline();
    }
    return [];
  }

  /// Checks device status by hardware fingerprint from Central Cloud Server
  Future<DeviceModel?> checkCentralDeviceStatus(
    String fingerprint, {
    bool bypassCooldown = false,
  }) async {
    if (!isConfigured) return null;
    if (!bypassCooldown && isServerCooldownActive) return null;
    await ensureServerConnected();
    try {
      final uri = Uri.parse(
        '$baseUrl/api/devices/check?fingerprint=${Uri.encodeComponent(fingerprint)}',
      );
      final res = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        if (_customBaseUrl == null) markServerOnline(baseUrl);
        final map =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return DeviceModel.fromMap(map);
      }
    } catch (e) {
      if (!bypassCooldown && _customBaseUrl == null) markServerOffline();
    }
    return null;
  }

  /// Approves a device on the Central Cloud Server
  Future<bool> approveCentralDevice(String deviceId, String adminUserId) async {
    if (!isConfigured || isServerCooldownActive) return false;
    try {
      final uri = Uri.parse('$baseUrl/api/devices/approve');
      final res = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'device_id': deviceId,
              'approved_by_user_id': adminUserId,
            }),
          )
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        if (_customBaseUrl == null) markServerOnline(baseUrl);
        return true;
      }
    } catch (e) {
      if (_customBaseUrl == null) markServerOffline();
    }
    return false;
  }

  /// Revokes a device on the Central Cloud Server
  Future<bool> revokeCentralDevice(String deviceId, String adminUserId) async {
    if (!isConfigured || isServerCooldownActive) return false;
    try {
      final uri = Uri.parse('$baseUrl/api/devices/revoke');
      final res = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'device_id': deviceId,
              'revoked_by_user_id': adminUserId,
            }),
          )
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        if (_customBaseUrl == null) markServerOnline(baseUrl);
        return true;
      }
    } catch (e) {
      if (_customBaseUrl == null) markServerOffline();
    }
    return false;
  }

  /// Requests a password reset OTP code sent via SMTP to the registered staff email
  Future<Map<String, dynamic>> sendForgotPasswordOtp(String email) async {
    if (!isConfigured || isServerCooldownActive) {
      return {
        'success': false,
        'error': 'Central server is unreachable or offline. Password reset requires server connection.',
        'is_offline': true,
      };
    }
    try {
      final uri = Uri.parse('$baseUrl/api/auth/forgot-password');
      final res = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({'email': email.trim()}),
          )
          .timeout(const Duration(seconds: 15));
      final body =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (res.statusCode == 200 || res.statusCode == 201) {
        if (_customBaseUrl == null) markServerOnline(baseUrl);
        return body;
      } else {
        return {
          'success': false,
          'error':
              body['error'] ?? 'Failed to send reset code (${res.statusCode})',
        };
      }
    } catch (e) {
      if (_customBaseUrl == null) markServerOffline();
      return {
        'success': false,
        'error': 'Network connection error: $e',
        'is_offline': true,
      };
    }
  }

  /// Verifies a 6-digit reset code
  Future<Map<String, dynamic>> verifyResetCode(
    String email,
    String code,
  ) async {
    if (!isConfigured || isServerCooldownActive) {
      return {
        'success': false,
        'error': 'Central server is unreachable. Please check connection.',
        'is_offline': true,
      };
    }
    try {
      final uri = Uri.parse('$baseUrl/api/auth/verify-reset-code');
      final res = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({'email': email.trim(), 'code': code.trim()}),
          )
          .timeout(const Duration(seconds: 6));
      final body =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (res.statusCode == 200) {
        if (_customBaseUrl == null) markServerOnline(baseUrl);
        return body;
      } else {
        return {
          'success': false,
          'error': body['error'] ?? 'Invalid code (${res.statusCode})',
        };
      }
    } catch (e) {
      if (_customBaseUrl == null) markServerOffline();
      return {
        'success': false,
        'error': 'Network connection error: $e',
        'is_offline': true,
      };
    }
  }

  /// Resets user password using the verified code
  Future<Map<String, dynamic>> resetPasswordWithCode(
    String email,
    String code,
    String newPassword, {
    String? newPin,
  }) async {
    if (!isConfigured || isServerCooldownActive) {
      return {
        'success': false,
        'error': 'Central server is unreachable. Please check connection.',
        'is_offline': true,
      };
    }
    try {
      final uri = Uri.parse('$baseUrl/api/auth/reset-password');
      final payload = <String, dynamic>{
        'email': email.trim(),
        'code': code.trim(),
        'new_password': newPassword.trim(),
      };
      if (newPin != null && newPin.trim().isNotEmpty) {
        payload['new_pin'] = newPin.trim();
      }
      final res = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));
      final body =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (res.statusCode == 200) {
        if (_customBaseUrl == null) markServerOnline(baseUrl);
        return body;
      } else {
        return {
          'success': false,
          'error':
              body['error'] ?? 'Failed to reset password (${res.statusCode})',
        };
      }
    } catch (e) {
      if (_customBaseUrl == null) markServerOffline();
      return {
        'success': false,
        'error': 'Network error: $e',
        'is_offline': true,
      };
    }
  }
}
