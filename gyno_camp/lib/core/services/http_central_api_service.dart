import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../models/camp_model.dart';
import '../../models/clinical_visit_model.dart';
import '../../models/lookup_item_model.dart';
import '../../models/patient_model.dart';
import '../../models/sync_payload_model.dart';
import '../../models/user_model.dart';
import 'central_api_service.dart';

import 'session_service.dart';

class HttpCentralApiService implements ICentralApiService {
  final String? _customBaseUrl;
  final http.Client _client;
  static String? _activeBaseUrl;

  HttpCentralApiService({
    String? baseUrl,
    http.Client? client,
  })  : _customBaseUrl = baseUrl,
        _client = client ?? http.Client();

  String get baseUrl {
    final customUrl = _customBaseUrl;
    if (customUrl != null && customUrl.isNotEmpty) {
      return customUrl;
    }
    final activeUrl = _activeBaseUrl;
    if (activeUrl != null && activeUrl.isNotEmpty) {
      return activeUrl;
    }

    try {
      final configuredHost = SessionService.current?.getPostgresConfig().host;
      if (configuredHost != null &&
          configuredHost.isNotEmpty &&
          configuredHost != 'localhost' &&
          configuredHost != '127.0.0.1') {
        return configuredHost.startsWith('http')
            ? configuredHost
            : 'http://$configuredHost:8080';
      }
    } catch (_) {}

    return 'http://localhost:8080';
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

  @override
  Future<bool> pingServer() async {
    // 1. Check current baseUrl
    if (await _testEndpoint(baseUrl)) {
      _activeBaseUrl = baseUrl;
      return true;
    }

    // 2. On Android/native devices, automatically probe standard emulator & local LAN hosts
    if (!kIsWeb) {
      final candidates = [
        'http://10.0.2.2:8080',       // Android Emulator host bridge
        'http://192.168.110.108:8080', // Local development Wi-Fi network host
        'http://localhost:8080',      // Localhost via adb reverse
      ];
      for (final candidate in candidates) {
        if (candidate != baseUrl && await _testEndpoint(candidate)) {
          _activeBaseUrl = candidate;
          return true;
        }
      }
    }

    return false;
  }

  Future<bool> _testEndpoint(String targetUrl) async {
    try {
      final uri = Uri.parse('$targetUrl/health');
      final res = await _client.get(uri).timeout(const Duration(seconds: 2));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<SyncPushResponse> pushDelta(SyncPushPayload payload) async {
    try {
      final uri = Uri.parse('$baseUrl/api/sync/push');
      final body = jsonEncode(payload.toMap());
      final res = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: body,
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200 || res.statusCode == 201) {
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return SyncPushResponse.fromMap(data);
      } else {
        throw Exception('Central server returned HTTP ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      debugPrint('HttpCentralApiService pushDelta error: $e');
      rethrow;
    }
  }

  @override
  Future<SyncPullResponse> pullDelta({DateTime? since, required String deviceId}) async {
    try {
      var urlStr = '$baseUrl/api/sync/pull?deviceId=$deviceId';
      if (since != null) {
        urlStr += '&since=${Uri.encodeComponent(since.toIso8601String())}';
      }
      final uri = Uri.parse(urlStr);
      final res = await _client.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
        return SyncPullResponse.fromMap(data);
      } else {
        throw Exception('Central server returned HTTP ${res.statusCode}: ${res.body}');
      }
    } catch (e) {
      debugPrint('HttpCentralApiService pullDelta error: $e');
      rethrow;
    }
  }

  /// Sends a newly created or updated Camp directly to the Central Cloud
  Future<bool> broadcastCamp(CampModel camp) async {
    try {
      final uri = Uri.parse('$baseUrl/api/camps');
      final res = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode(camp.toMap()),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('broadcastCamp to central cloud skipped (server offline): $e');
      return false;
    }
  }

  /// Sends a newly created or updated User directly to the Central Cloud
  Future<bool> broadcastUser(UserModel user) async {
    try {
      final uri = Uri.parse('$baseUrl/api/users');
      final res = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode(user.toMap()),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (e) {
      debugPrint('broadcastUser to central cloud skipped (server offline): $e');
      return false;
    }
  }

  /// Fetches all active camps from the Central Cloud API
  Future<List<CampModel>> fetchCentralCamps() async {
    try {
      final uri = Uri.parse('$baseUrl/api/camps');
      final res = await _client.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
        return list.map((item) => CampModel.fromMap(item as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('fetchCentralCamps offline or skipped: $e');
    }
    return [];
  }

  /// Fetches all staff users from the Central Cloud API
  Future<List<UserModel>> fetchCentralUsers() async {
    try {
      final uri = Uri.parse('$baseUrl/api/users');
      final res = await _client.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
        return list.map((item) => UserModel.fromMap(item as Map<String, dynamic>)).toList();
      }
    } catch (e) {
      debugPrint('fetchCentralUsers offline or skipped: $e');
    }
    return [];
  }
}

