import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/core/database/database_tables.dart';
import 'package:gyno_camp/core/services/central_api_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/sync_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('SyncRepository SQLite Tests', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late CentralApiService centralApiService;
    late SyncRepository syncRepo;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      auditRepo = AuditRepository(databaseService: dbService);
      centralApiService = CentralApiService();
      syncRepo = SyncRepository(
        databaseService: dbService,
        centralApiService: centralApiService,
        auditRepository: auditRepo,
      );
    });

    tearDown(() async {
      await testDb.close();
    });

    PatientModel makeTestPatient({
      required String id,
      required String patientId,
      required String firstName,
      required String surname,
      bool isSynced = false,
    }) {
      return PatientModel(
        id: id,
        patientId: patientId,
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        intakeDate: DateTime(2026, 3, 15),
        firstName: firstName,
        surname: surname,
        age: 32,
        ward: '03',
        maritalStatus: 'married',
        mobile: '9841112233',
        createdByUserId: 'usr-01',
        createdByDeviceId: 'dev-001',
        isSynced: isSynced,
        createdAt: DateTime.now(),
      );
    }

    ClinicalVisitModel makeTestVisit({
      required String id,
      required String patientId,
      bool isSynced = false,
    }) {
      return ClinicalVisitModel(
        id: id,
        patientId: patientId,
        campId: 'camp-ktm-01',
        visitDate: DateTime(2026, 3, 15),
        createdByUserId: 'usr-01',
        isSynced: isSynced,
        createdAt: DateTime.now(),
      );
    }

    test('getPendingCounts correctly tallies unsynced patients and visits', () async {
      final initialCounts = await syncRepo.getPendingCounts();
      expect(initialCounts['patients'], 0);
      expect(initialCounts['visits'], 0);
      expect(initialCounts['total'], 0);

      // Insert unsynced patient
      final patient = makeTestPatient(
        id: 'pat-sync-01',
        patientId: 'GC-KTM01-2026-0001',
        firstName: 'Anjali',
        surname: 'Tamang',
      );
      await testDb.insert(DatabaseTables.tablePatients, patient.toMap());

      // Insert unsynced visit
      final visit = makeTestVisit(
        id: 'vis-sync-01',
        patientId: 'GC-KTM01-2026-0001',
      );
      await testDb.insert(DatabaseTables.tableClinicalVisits, visit.toMap());

      final counts = await syncRepo.getPendingCounts();
      expect(counts['patients'], 1);
      expect(counts['visits'], 1);
      expect(counts['total'], 2);
    });

    test('pushDelta uploads unsynced records and marks is_synced=1 in SQLite', () async {
      final patient = makeTestPatient(
        id: 'pat-upload-01',
        patientId: 'GC-KTM01-2026-0002',
        firstName: 'Bimala',
        surname: 'Rai',
      );
      await testDb.insert(DatabaseTables.tablePatients, patient.toMap());

      final res = await syncRepo.pushDelta(deviceId: 'dev-001', userId: 'usr-01');

      expect(res.success, isTrue);
      expect(res.syncedPatientIds, contains('pat-upload-01'));

      // Check SQLite table directly: is_synced must now be 1
      final rows = await testDb.query(
        DatabaseTables.tablePatients,
        where: 'id = ?',
        whereArgs: ['pat-upload-01'],
      );
      expect(rows.first['is_synced'], 1);
      expect(rows.first['synced_at'], isNotNull);

      // Pending counts must now be 0
      final updatedCounts = await syncRepo.getPendingCounts();
      expect(updatedCounts['total'], 0);
    });

    test('pullDelta downloads cloud camps and updates local SQLite store', () async {
      final remoteCamp = CampModel(
        id: 'camp-pokhara-02',
        campCode: 'PKR02',
        name: 'Pokhara Regional Women Health Camp',
        district: 'Kaski',
        municipality: 'Pokhara',
        ward: '08',
        venue: 'Western Regional Hospital',
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 7, 3),
        createdAt: DateTime(2026, 7, 1),
      );

      centralApiService.setMockServerCamps([remoteCamp]);

      final pullRes = await syncRepo.pullDelta(deviceId: 'dev-001', userId: 'usr-01');

      expect(pullRes.success, isTrue);
      expect(pullRes.camps.length, 1);
      expect(pullRes.camps.first.campCode, 'PKR02');

      // Check SQLite table directly: new camp must be stored
      final campRows = await testDb.query(
        DatabaseTables.tableCamps,
        where: 'id = ?',
        whereArgs: ['camp-pokhara-02'],
      );
      expect(campRows.length, 1);
      expect(campRows.first['name'], 'Pokhara Regional Women Health Camp');
    });

    test('executeFullSyncCycle performs bidirectional sync and tracks history', () async {
      final patient = makeTestPatient(
        id: 'pat-full-01',
        patientId: 'GC-KTM01-2026-0003',
        firstName: 'Kamala',
        surname: 'Poudel',
      );
      await testDb.insert(DatabaseTables.tablePatients, patient.toMap());

      final historyItem = await syncRepo.executeFullSyncCycle(
        deviceId: 'dev-001',
        userId: 'usr-01',
      );

      expect(historyItem.isSuccess, isTrue);
      expect(historyItem.patientsPushed, 1);
      expect(historyItem.campsPulled, greaterThanOrEqualTo(1));

      final history = await syncRepo.getSyncHistory();
      expect(history.length, 1);
      expect(history.first.id, historyItem.id);

      final lastSynced = await syncRepo.getLastSyncedAt();
      expect(lastSynced, isNotNull);
      expect(lastSynced, equals(historyItem.timestamp));
    });

    test('executeFullSyncCycle tracks failure when network fails', () async {
      centralApiService.simulateNetworkFailure = true;

      await expectLater(
        syncRepo.executeFullSyncCycle(deviceId: 'dev-001', userId: 'usr-01'),
        throwsA(isA<Exception>()),
      );

      final history = await syncRepo.getSyncHistory();
      expect(history.length, 1);
      expect(history.first.isSuccess, isFalse);
      expect(history.first.errorMessage, contains('Network timeout'));
    });
  });
}
