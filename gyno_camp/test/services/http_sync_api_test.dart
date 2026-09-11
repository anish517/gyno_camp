import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:gyno_camp/core/services/http_central_api_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/models/sync_payload_model.dart';
import 'package:gyno_camp/models/user_model.dart';

void main() {
  group('HttpCentralApiService Cloud Sync Tests', () {
    test('pingServer returns true on HTTP 200 health check', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/health');
        return http.Response(jsonEncode({'status': 'online'}), 200);
      });

      final service = HttpCentralApiService(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );

      final isOnline = await service.pingServer();
      expect(isOnline, isTrue);
    });

    test('pingServer returns false on connection failure or HTTP 500', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Server Error', 500);
      });

      final service = HttpCentralApiService(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );

      final isOnline = await service.pingServer();
      expect(isOnline, isFalse);
    });

    test('pushDelta packages patients and visits and parses successful SyncPushResponse', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/sync/push');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['device_id'], 'dev-test-1');
        expect((body['patients'] as List).length, 1);

        return http.Response(
          jsonEncode({
            'success': true,
            'server_timestamp': DateTime.now().toIso8601String(),
            'synced_patient_ids': ['pat-001'],
            'synced_visit_ids': <String>[],
            'synced_audit_log_ids': <String>[],
            'conflict_entity_ids': <String>[],
            'message': 'Successfully processed 1 patients.',
          }),
          200,
        );
      });

      final service = HttpCentralApiService(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );

      final now = DateTime.now();
      final payload = SyncPushPayload(
        deviceId: 'dev-test-1',
        generatedAt: now,
        patients: [
          PatientModel(
            id: 'pat-001',
            patientId: 'GC-KTM-001',
            campId: 'camp-001',
            campCode: 'KTM01',
            intakeDate: now,
            firstName: 'Sunita',
            surname: 'Magar',
            age: 28,
            mobile: '9841234567',
            district: 'Kathmandu',
            municipality: 'Budhanilkantha',
            ward: '02',
            createdAt: now,
            createdByUserId: 'usr-1',
            createdByDeviceId: 'dev-test-1',
          ),
        ],
      );

      final response = await service.pushDelta(payload);
      expect(response.success, isTrue);
      expect(response.syncedPatientIds, contains('pat-001'));
    });

    test('pullDelta requests deltas with deviceId and timestamp and returns updated camps and users', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/sync/pull');
        expect(request.url.queryParameters['deviceId'], 'dev-test-1');

        return http.Response(
          jsonEncode({
            'success': true,
            'server_timestamp': DateTime.now().toIso8601String(),
            'camps': [
              {
                'id': 'camp-cloud-01',
                'camp_code': 'KTM99',
                'name': 'Cloud Central Outreach',
                'district': 'Kathmandu',
                'municipality': 'Kathmandu Metro',
                'ward': '01',
                'venue': 'Bir Hospital',
                'start_date': DateTime.now().toIso8601String(),
                'end_date': DateTime.now().add(const Duration(days: 2)).toIso8601String(),
                'status': 'open',
                'assigned_staff_ids': 'usr-1',
                'total_patients_registered': 5,
                'created_at': DateTime.now().toIso8601String(),
              }
            ],
            'users': [
              {
                'id': 'usr-cloud-01',
                'name': 'Dr. Sharma',
                'email': 'sharma@gynocamp.org',
                'phone': '9851000001',
                'role': 'super_admin',
                'is_active': 1,
              }
            ],
            'lookup_items': <dynamic>[],
            'message': 'Pulled 1 camps and 1 staff accounts from cloud.',
          }),
          200,
        );
      });

      final service = HttpCentralApiService(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );

      final response = await service.pullDelta(deviceId: 'dev-test-1');
      expect(response.success, isTrue);
      expect(response.camps.length, 1);
      expect(response.camps.first.campCode, 'KTM99');
      expect(response.users.length, 1);
      expect(response.users.first.email, 'sharma@gynocamp.org');
    });

    test('broadcastCamp posts new camp to /api/camps', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/camps');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['camp_code'], 'KTM55');
        return http.Response(request.body, 201);
      });

      final service = HttpCentralApiService(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );

      final now = DateTime.now();
      final camp = CampModel(
        id: 'camp-55',
        campCode: 'KTM55',
        name: 'New Camp',
        district: 'Kathmandu',
        municipality: 'Budhanilkantha',
        ward: '05',
        venue: 'Primary Health Center',
        startDate: now,
        endDate: now,
        status: CampStatus.open,
        createdAt: now,
      );

      final success = await service.broadcastCamp(camp);
      expect(success, isTrue);
    });

    test('broadcastUser posts new staff member to /api/users', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, '/api/users');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['email'], 'nurse@gynocamp.org');
        return http.Response(request.body, 201);
      });

      final service = HttpCentralApiService(
        baseUrl: 'http://localhost:8080',
        client: mockClient,
      );

      const user = UserModel(
        id: 'usr-55',
        name: 'Nurse Priya',
        email: 'nurse@gynocamp.org',
        phone: '9841000055',
        role: UserRole.dataTaker,
      );

      final success = await service.broadcastUser(user);
      expect(success, isTrue);
    });
  });
}
