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
  static const Duration _offlineCooldown = Duration(seconds: 30);

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
    if (url != null && url.isNotEmpty) {
      _activeBaseUrl = url;
    }
  }

  HttpCentralApiService({String? baseUrl, http.Client? client})
    : _customBaseUrl = baseUrl,
      _client = client ?? http.Client();

  String get baseUrl {
    final customUrl = _customBaseUrl;
    if (customUrl != null && customUrl.isNotEmpty) {
      return customUrl;
    }

    // 1. Explicit runtime environment flag (--dart-define=CENTRAL_SERVER_URL=...) MUST take top priority
    const envUrl = String.fromEnvironment(
      'CENTRAL_SERVER_URL',
      defaultValue: '',
    );
    if (envUrl.isNotEmpty) {
      return envUrl;
    }

    // 2. Verified active URL from dynamic candidate probing
    final activeUrl = _activeBaseUrl;
    if (activeUrl != null && activeUrl.isNotEmpty) {
      return activeUrl;
    }

    // 3. User-configured saved URL from preferences (ignore obsolete 192.168.1.4 if present)
    try {
      final savedUrl = SessionService.current?.getCentralServerUrl();
      if (savedUrl != null &&
          savedUrl.isNotEmpty &&
          savedUrl != 'http://192.168.1.3:8080') {
        return savedUrl;
      }
    } catch (_) {}

    try {
      final configuredHost = SessionService.current?.getPostgresConfig().host;
      if (configuredHost != null &&
          configuredHost.isNotEmpty &&
          configuredHost != 'localhost' &&
          configuredHost != '127.0.0.1' &&
          configuredHost != '192.168.1.4') {
        return configuredHost.startsWith('http')
            ? configuredHost
            : 'http://$configuredHost:8080';
      }
    } catch (_) {}

    return 'http://192.168.1.13:8080';
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

  /// Ensures the service has discovered and verified a live connection to the Central Server.
  Future<bool> ensureServerConnected() async {
    if (_activeBaseUrl != null && _isServerReachable) return true;
    return await pingServer();
  }

  @override
  Future<bool> pingServer() async {
    // 1. Quick test on activeBaseUrl if already resolved
    final active = _activeBaseUrl;
    if (active != null && await _testEndpoint(active)) {
      markServerOnline(active);
      return true;
    }

    // 2. Parallel probe candidate endpoints for immediate LAN discovery (<1.5s)
    final candidateSet = <String>{
      baseUrl,
      'http://192.168.1.13:8080', // Active Wi-Fi host IP
      'http://192.168.16.113:8080', // Home Wi-Fi host IP
      'http://localhost:8080', // Web / desktop localhost
      'http://127.0.0.1:8080', // ADB reverse USB loopback
      'http://192.168.1.4:8080', // Office Wi-Fi host IP
      'http://192.168.1.110:8080', // Alternative Wi-Fi host IP
      'http://10.0.2.2:8080', // Android emulator host bridge
    };

    final saved = SessionService.current?.getCentralServerUrl();
    if (saved != null && saved.isNotEmpty) {
      candidateSet.add(saved);
    }

    final probeFutures = candidateSet.map((candidate) async {
      final ok = await _testEndpoint(candidate);
      return (candidate: candidate, ok: ok);
    });

    final results = await Future.wait(probeFutures);
    for (final res in results) {
      if (res.ok) {
        markServerOnline(res.candidate);
        try {
          SessionService.current?.saveCentralServerUrl(res.candidate);
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
      final res = await _client.get(uri).timeout(const Duration(milliseconds: 1500));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<SyncPushResponse> pushDelta(SyncPushPayload payload) async {
    if (_activeBaseUrl == null || !_isServerReachable) {
      await pingServer();
    }
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
        markServerOnline();
        final data =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return SyncPushResponse.fromMap(data);
      } else {
        throw Exception(
          'Central server returned HTTP ${res.statusCode}: ${res.body}',
        );
      }
    } catch (e) {
      markServerOffline();
      debugPrint('HttpCentralApiService pushDelta error: $e');
      rethrow;
    }
  }

  @override
  Future<SyncPullResponse> pullDelta({
    DateTime? since,
    required String deviceId,
  }) async {
    if (_activeBaseUrl == null || !_isServerReachable) {
      await pingServer();
    }
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
        markServerOnline();
        final data =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return SyncPullResponse.fromMap(data);
      } else {
        throw Exception(
          'Central server returned HTTP ${res.statusCode}: ${res.body}',
        );
      }
    } catch (e) {
      markServerOffline();
      debugPrint('HttpCentralApiService pullDelta error: $e');
      rethrow;
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
      if (ok) markServerOnline();
      return ok;
    } catch (e) {
      markServerOffline();
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
      if (ok) markServerOnline();
      return ok;
    } catch (e) {
      markServerOffline();
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
      if (ok) markServerOnline();
      return ok;
    } catch (e) {
      markServerOffline();
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
      if (ok) markServerOnline();
      return ok;
    } catch (e) {
      markServerOffline();
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
      if (ok) markServerOnline();
      return ok;
    } catch (e) {
      markServerOffline();
      return false;
    }
  }

  /// Fetches all active camps from the Central Cloud API
  Future<List<CampModel>> fetchCentralCamps({bool bypassCooldown = false}) async {
    if (!isConfigured) return [];
    if (!bypassCooldown && isServerCooldownActive) return [];
    await ensureServerConnected();
    try {
      final uri = Uri.parse('$baseUrl/api/camps');
      final res = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        markServerOnline();
        final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
        return list
            .map((item) => CampModel.fromMap(item as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      if (!bypassCooldown) markServerOffline();
    }
    return [];
  }

  /// Fetches all staff users from the Central Cloud API
  Future<List<UserModel>> fetchCentralUsers({bool bypassCooldown = false}) async {
    if (!isConfigured) return [];
    if (!bypassCooldown && isServerCooldownActive) return [];
    await ensureServerConnected();
    try {
      final uri = Uri.parse('$baseUrl/api/users');
      final res = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        markServerOnline();
        final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
        return list
            .map((item) => UserModel.fromMap(item as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      if (!bypassCooldown) markServerOffline();
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
        markServerOnline();
        return true;
      }
    } catch (e) {
      markServerOffline();
    }
    return false;
  }

  /// Fetches all devices known to the Central Cloud Server
  Future<List<DeviceModel>> fetchCentralDevices({bool bypassCooldown = false}) async {
    if (!isConfigured) return [];
    if (!bypassCooldown && isServerCooldownActive) return [];
    await ensureServerConnected();
    try {
      final uri = Uri.parse('$baseUrl/api/devices');
      final res = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        markServerOnline();
        final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
        return list
            .map((item) => DeviceModel.fromMap(item as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      if (!bypassCooldown) markServerOffline();
    }
    return [];
  }

  /// Checks device status by hardware fingerprint from Central Cloud Server
  Future<DeviceModel?> checkCentralDeviceStatus(String fingerprint, {bool bypassCooldown = false}) async {
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
        markServerOnline();
        final map =
            jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return DeviceModel.fromMap(map);
      }
    } catch (e) {
      if (!bypassCooldown) markServerOffline();
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
        markServerOnline();
        return true;
      }
    } catch (e) {
      markServerOffline();
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
        markServerOnline();
        return true;
      }
    } catch (e) {
      markServerOffline();
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
        markServerOnline();
        return body;
      } else {
        return {
          'success': false,
          'error':
              body['error'] ?? 'Failed to send reset code (${res.statusCode})',
        };
      }
    } catch (e) {
      markServerOffline();
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
        markServerOnline();
        return body;
      } else {
        return {
          'success': false,
          'error': body['error'] ?? 'Invalid code (${res.statusCode})',
        };
      }
    } catch (e) {
      markServerOffline();
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
        markServerOnline();
        return body;
      } else {
        return {
          'success': false,
          'error':
              body['error'] ?? 'Failed to reset password (${res.statusCode})',
        };
      }
    } catch (e) {
      markServerOffline();
      return {
        'success': false,
        'error': 'Network error: $e',
        'is_offline': true,
      };
    }
  }
}
