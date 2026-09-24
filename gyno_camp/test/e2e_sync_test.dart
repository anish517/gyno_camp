import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  const baseUrl = 'http://localhost:8080';

  group('Live E2E Central Server & PostgreSQL Sync Verification', () {
    final createdCampIds = <String>[];

    tearDownAll(() async {
      for (final cid in createdCampIds) {
        try {
          await http.delete(Uri.parse('$baseUrl/api/camps?id=$cid'));
        } catch (_) {}
      }
    });

    test('1. Server status is online and connected to PostgreSQL', () async {
      final res = await http.get(Uri.parse('$baseUrl/api/status'));
      expect(res.statusCode, 200);
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      expect(data['status'], 'online');
      expect(data['postgres_connected'], true);
      expect(data['database'], 'gynocamp_db');
    });

    test('2. Web simulates registering a patient & medicine, pushing via /api/sync/push', () async {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final testPatientId = 'pat-e2e-$timestamp';
      final testCampId = 'camp-e2e-$timestamp';
      createdCampIds.add(testCampId);

      // 2a. Broadcast camp
      final campRes = await http.post(
        Uri.parse('$baseUrl/api/camps'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': testCampId,
          'camp_code': 'E2E$timestamp',
          'name': 'E2E Validation Camp',
          'district': 'Kathmandu',
          'start_date': '2026-03-21',
          'end_date': '2026-03-25',
          'status': 'OPEN',
        }),
      );
      expect(campRes.statusCode, anyOf(200, 201));

      // 2b. Push patient and medicine
      final pushRes = await http.post(
        Uri.parse('$baseUrl/api/sync/push'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_id': 'web-browser-device',
          'generated_at': DateTime.now().toIso8601String(),
          'patients': [
            {
              'id': testPatientId,
              'patient_id': 'GC-E2E-$timestamp',
              'camp_id': testCampId,
              'camp_code': 'E2E$timestamp',
              'intake_date': DateTime.now().toIso8601String(),
              'first_name': 'Sita',
              'surname': 'Shrestha',
              'age': 29,
              'ward': '05',
              'mobile': '9800000000',
              'created_by_user_id': 'usr-web',
              'created_by_device_id': 'web-browser-device',
              'is_synced': 1,
              'created_at': DateTime.now().toIso8601String(),
            }
          ],
          'lookup_items': [
            {
              'id': 'med-e2e-$timestamp',
              'category': 'medicine',
              'sub_category': 'Antibiotics',
              'code': 'e2e_amox_$timestamp',
              'label_en': 'Amoxicillin 500mg E2E',
              'label_ne': 'एमोक्सिसिलिन ५००',
              'is_active': 1,
              'sort_order': 1,
              'tenant_id': 'tenant_default',
              'is_deleted': 0,
            }
          ],
        }),
      );

      expect(pushRes.statusCode, 200);
      final pushData = jsonDecode(pushRes.body) as Map<String, dynamic>;
      expect(pushData['success'], true);
      expect(List<String>.from(pushData['synced_patient_ids'] ?? []), contains(testPatientId));

      // 2c. Android pulls and verifies patient, camp, and medicine
      final pullRes = await http.get(
        Uri.parse('$baseUrl/api/sync/pull?device_id=android-tablet-device'),
      );
      expect(pullRes.statusCode, 200);
      final pullData = jsonDecode(pullRes.body) as Map<String, dynamic>;

      final pulledPatients = (pullData['patients'] as List<dynamic>?) ?? [];
      final matchingPatient = pulledPatients.firstWhere(
        (p) => p['id'] == testPatientId,
        orElse: () => null,
      );
      expect(matchingPatient, isNotNull);
      expect(matchingPatient['first_name'], 'Sita');

      final pulledLookups = (pullData['lookup_items'] as List<dynamic>?) ?? [];
      final matchingLookup = pulledLookups.firstWhere(
        (l) => l['id'] == 'med-e2e-$timestamp',
        orElse: () => null,
      );
      expect(matchingLookup, isNotNull);
      expect(matchingLookup['label_en'], 'Amoxicillin 500mg E2E');
    });

    test('3. Android records clinical visit & updates patient, Web pulls the updates', () async {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final testPatientId = 'pat-visit-$timestamp';
      final testVisitId = 'visit-e2e-$timestamp';

      final testCampId = 'camp-v-$timestamp';
      createdCampIds.add(testCampId);

      // 3a-0. Broadcast valid camp first
      final campRes = await http.post(
        Uri.parse('$baseUrl/api/camps'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': testCampId,
          'camp_code': 'CAMP$timestamp',
          'name': 'Clinical Camp $timestamp',
          'district': 'Lalitpur',
          'start_date': '2026-03-21',
          'end_date': '2026-03-25',
          'status': 'OPEN',
        }),
      );
      expect(campRes.statusCode, anyOf(200, 201));

      // 3a. Register base patient
      final patPushRes = await http.post(
        Uri.parse('$baseUrl/api/sync/push'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_id': 'web-device',
          'generated_at': DateTime.now().toIso8601String(),
          'patients': [
            {
              'id': testPatientId,
              'patient_id': 'GC-V-$timestamp',
              'camp_id': testCampId,
              'camp_code': 'CAMP$timestamp',
              'intake_date': DateTime.now().toIso8601String(),
              'first_name': 'Gita',
              'surname': 'Adhikari',
              'age': 35,
              'ward': '02',
              'mobile': '9841223344',
              'created_by_user_id': 'usr-01',
              'created_by_device_id': 'web-device',
              'is_synced': 1,
              'created_at': DateTime.now().toIso8601String(),
            }
          ],
        }),
      );
      expect(patPushRes.statusCode, 200);

      // 3b. Android records a clinical visit for this patient and pushes
      final visitPushRes = await http.post(
        Uri.parse('$baseUrl/api/sync/push'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'device_id': 'android-device',
          'generated_at': DateTime.now().toIso8601String(),
          'clinical_visits': [
            {
              'id': testVisitId,
              'patient_id': 'GC-V-$timestamp',
              'camp_id': testCampId,
              'visit_date': DateTime.now().toIso8601String(),
              'systolic_bp': 120,
              'diastolic_bp': 80,
              'pulse': 72,
              'spo2': 98,
              'highest_pop_stage': 2,
              'diagnoses': 'Uterine Prolapse Stage II',
              'medications': 'Pelvic floor exercises, Follow-up in 1 month',
              'created_by_user_id': 'dr-sharma',
              'is_synced': 1,
              'created_at': DateTime.now().toIso8601String(),
            }
          ],
        }),
      );

      expect(visitPushRes.statusCode, 200);
      final visitPushData = jsonDecode(visitPushRes.body) as Map<String, dynamic>;
      expect(visitPushData['success'], true);
      expect(List<String>.from(visitPushData['synced_visit_ids'] ?? []), contains(testVisitId));

      // 3c. Web pulls deltas and verifies clinical visit is received
      final webPullRes = await http.get(
        Uri.parse('$baseUrl/api/sync/pull?device_id=web-device'),
      );
      expect(webPullRes.statusCode, 200);
      final webPullData = jsonDecode(webPullRes.body) as Map<String, dynamic>;

      final visits = (webPullData['clinical_visits'] as List<dynamic>?) ?? [];
      final matchingVisit = visits.firstWhere(
        (v) => v['id'] == testVisitId,
        orElse: () => null,
      );
      expect(matchingVisit, isNotNull, reason: 'Web must receive clinical visit saved on Android');
      expect(matchingVisit['systolic_bp'], 120);
      expect(matchingVisit['diastolic_bp'], 80);
      expect(matchingVisit['diagnoses'], 'Uterine Prolapse Stage II');
    });
  });
}
