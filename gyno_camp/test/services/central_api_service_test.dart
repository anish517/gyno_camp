import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/central_api_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/lookup_item_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/models/sync_payload_model.dart';

void main() {
  group('CentralApiService Tests', () {
    late CentralApiService apiService;

    setUp(() {
      apiService = CentralApiService();
    });

    PatientModel createTestPatient({
      required String id,
      required String patientId,
      required String firstName,
      required String surname,
      required DateTime createdAt,
      DateTime? updatedAt,
    }) {
      return PatientModel(
        id: id,
        patientId: patientId,
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        intakeDate: DateTime(2026, 3, 15),
        firstName: firstName,
        surname: surname,
        age: 35,
        ward: '03',
        maritalStatus: 'married',
        mobile: '9841234567',
        createdByUserId: 'usr-datataker-01',
        createdByDeviceId: 'dev-001',
        isSynced: false,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    }

    ClinicalVisitModel createTestVisit({
      required String id,
      required String patientId,
      required DateTime createdAt,
      DateTime? updatedAt,
    }) {
      return ClinicalVisitModel(
        id: id,
        patientId: patientId,
        campId: 'camp-ktm-01',
        visitDate: DateTime(2026, 3, 15),
        createdByUserId: 'usr-datataker-01',
        isSynced: false,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    }

    test('pingServer responds true under normal network, false on failure', () async {
      expect(await apiService.pingServer(), isTrue);

      apiService.simulateNetworkFailure = true;
      expect(await apiService.pingServer(), isFalse);
    });

    test('pullDelta returns seeded camps and users when since is null', () async {
      final pull = await apiService.pullDelta(deviceId: 'dev-001');

      expect(pull.success, isTrue);
      expect(pull.camps, isNotEmpty);
      expect(pull.users, isNotEmpty);
      expect(pull.camps.first.campCode, equals('KTM01'));
    });

    test('pushDelta stores patients and visits on server and returns synced IDs', () async {
      final now = DateTime.now();
      final patient = createTestPatient(
        id: 'pat-test-01',
        patientId: 'GC-KTM01-2026-0001',
        firstName: 'Sita',
        surname: 'Devi',
        createdAt: now,
      );

      final visit = createTestVisit(
        id: 'vis-test-01',
        patientId: 'GC-KTM01-2026-0001',
        createdAt: now,
      );

      final payload = SyncPushPayload(
        deviceId: 'dev-001',
        generatedAt: now,
        patients: [patient],
        clinicalVisits: [visit],
      );

      final response = await apiService.pushDelta(payload);

      expect(response.success, isTrue);
      expect(response.syncedPatientIds, contains('pat-test-01'));
      expect(response.syncedVisitIds, contains('vis-test-01'));
      expect(response.conflictEntityIds, isEmpty);

      // Verify stored on simulated server
      expect(apiService.serverStoredPatients.length, 1);
      expect(apiService.serverStoredPatients.first.id, 'pat-test-01');
      expect(apiService.serverStoredVisits.length, 1);
      expect(apiService.serverStoredVisits.first.id, 'vis-test-01');
    });

    test('pushDelta resolves conflicts using Last-Write-Wins (LWW)', () async {
      final baseTime = DateTime.now().subtract(const Duration(hours: 2));

      // Initial push
      final patientV1 = createTestPatient(
        id: 'pat-conflict-01',
        patientId: 'GC-KTM01-2026-0002',
        firstName: 'Gita',
        surname: 'Sharma',
        createdAt: baseTime,
        updatedAt: baseTime.add(const Duration(minutes: 30)),
      );

      await apiService.pushDelta(
        SyncPushPayload(
          deviceId: 'dev-001',
          generatedAt: DateTime.now(),
          patients: [patientV1],
        ),
      );

      // Newer update wins
      final patientV2 = patientV1.copyWith(
        firstName: 'Gita Updated',
        updatedAt: baseTime.add(const Duration(minutes: 45)),
      );

      final response2 = await apiService.pushDelta(
        SyncPushPayload(
          deviceId: 'dev-001',
          generatedAt: DateTime.now(),
          patients: [patientV2],
        ),
      );

      expect(response2.syncedPatientIds, contains('pat-conflict-01'));
      expect(response2.conflictEntityIds, isEmpty);
      expect(apiService.serverStoredPatients.first.firstName, 'Gita Updated');

      // Stale update loses (is before current server version)
      final stalePatient = patientV1.copyWith(
        firstName: 'Stale Version',
        updatedAt: baseTime.add(const Duration(minutes: 10)),
      );

      final response3 = await apiService.pushDelta(
        SyncPushPayload(
          deviceId: 'dev-002',
          generatedAt: DateTime.now(),
          patients: [stalePatient],
        ),
      );

      expect(response3.conflictEntityIds, contains('pat-conflict-01'));
      expect(response3.syncedPatientIds, isNot(contains('pat-conflict-01')));
      // The server still keeps the newer version
      expect(apiService.serverStoredPatients.first.firstName, 'Gita Updated');
    });

    test('pullDelta respects since timestamp and mock setters', () async {
      final oldCamp = CampModel(
        id: 'camp-old',
        campCode: 'OLD01',
        name: 'Old Camp',
        district: 'Kaski',
        municipality: 'Pokhara',
        ward: '01',
        venue: 'Old Hall',
        startDate: DateTime(2025, 1, 1),
        endDate: DateTime(2025, 1, 3),
        createdAt: DateTime(2025, 1, 1),
      );

      final newCamp = CampModel(
        id: 'camp-new',
        campCode: 'NEW01',
        name: 'New Camp',
        district: 'Lalitpur',
        municipality: 'Patan',
        ward: '05',
        venue: 'Health Post',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2026, 6, 3),
        createdAt: DateTime(2026, 6, 1),
      );

      apiService.setMockServerCamps([oldCamp, newCamp]);
      apiService.setMockServerLookupItems([
        const LookupItemModel(
          id: 'look-01',
          category: 'symptom',
          code: 'white_discharge',
          labelEn: 'White Discharge',
          labelNe: 'सेतो पानी बग्ने',
        ),
      ]);

      // Pull since Jan 2026
      final delta = await apiService.pullDelta(
        since: DateTime(2026, 1, 1),
        deviceId: 'dev-001',
      );

      expect(delta.camps.length, 1);
      expect(delta.camps.first.campCode, 'NEW01');
      expect(delta.lookupItems.length, 1);
    });

    test('network failure simulation throws exception', () async {
      apiService.simulateNetworkFailure = true;

      expect(
        () => apiService.pushDelta(
          SyncPushPayload(deviceId: 'dev-001', generatedAt: DateTime.now()),
        ),
        throwsA(isA<Exception>()),
      );

      expect(
        () => apiService.pullDelta(deviceId: 'dev-001'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
