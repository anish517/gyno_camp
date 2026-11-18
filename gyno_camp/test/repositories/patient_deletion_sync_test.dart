import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:gyno_camp/core/constants/app_constants.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/core/database/database_tables.dart';
import 'package:gyno_camp/core/services/central_api_service.dart';
import 'package:gyno_camp/core/services/http_central_api_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/lookup_item_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/models/sync_payload_model.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';
import 'package:gyno_camp/repositories/sync_repository.dart';

import '../../bin/server.dart';

class _UnconfirmedDeleteCentralApiService implements ICentralApiService {
  final List<PatientModel> serverPatients;
  final List<ClinicalVisitModel> serverVisits;
  int pushCallCount = 0;

  _UnconfirmedDeleteCentralApiService({
    required this.serverPatients,
    required this.serverVisits,
  });

  @override
  Future<bool> pingServer() async => true;

  @override
  Future<SyncPushResponse> pushDelta(SyncPushPayload payload) async {
    pushCallCount++;
    // Simulate a server that returns success: true, synced items ok,
    // but failed to confirm deletion of any patient/visit IDs.
    return SyncPushResponse(
      success: true,
      serverTimestamp: DateTime.now(),
      syncedPatientIds: payload.patients.map((p) => p.id).toList(),
      syncedVisitIds: payload.clinicalVisits.map((v) => v.id).toList(),
      deletedPatientIds: const [],
      deletedVisitIds: const [],
    );
  }

  @override
  Future<SyncPullResponse> pullDelta({DateTime? since, required String deviceId}) async {
    return SyncPullResponse(
      success: true,
      serverTimestamp: DateTime.now(),
      patients: serverPatients,
      clinicalVisits: serverVisits,
    );
  }

  @override
  List<ClinicalVisitModel> get serverStoredVisits => serverVisits;

  @override
  List<PatientModel> get serverStoredPatients => serverPatients;

  @override
  void setMockServerCamps(List<CampModel> camps) {}

  @override
  void setMockServerLookupItems(List<LookupItemModel> items) {}
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  PatientModel makePatient({
    String id = 'pat-uuid-001',
    String tokenId = 'GC-0007-2026-00012',
    String campId = 'camp-test-01',
  }) {
    final now = DateTime.now();
    return PatientModel(
      id: id,
      patientId: tokenId,
      campId: campId,
      campCode: '123',
      intakeDate: now,
      firstName: 'Kamala',
      surname: 'Rai',
      age: 58,
      mobile: '9842167305',
      district: 'Dhankuta',
      municipality: 'DHANKUTA MUN',
      ward: '05',
      createdAt: now,
      createdByUserId: 'usr-01',
      createdByDeviceId: 'dev-web-01',
    );
  }

  ClinicalVisitModel makeVisit({
    String id = 'vis-uuid-001',
    required PatientModel patient,
  }) {
    return ClinicalVisitModel(
      id: id,
      patientId: patient.id,
      campId: patient.campId,
      visitDate: DateTime.now(),
      createdByUserId: 'usr-01',
      highestPopStage: 3,
      createdAt: DateTime.now(),
    );
  }

  Future<DatabaseService> createInMemoryDbService(List<Database> openedDbs) async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    openedDbs.add(db);
    final service = DatabaseService();
    await service.initializeTestDb(db);
    return service;
  }

  group('Patient & Visit Deletion Sync Regression Tests', () {
    final openedDbs = <Database>[];

    tearDown(() async {
      for (final db in openedDbs) {
        if (db.isOpen) await db.close();
      }
      openedDbs.clear();
    });

    test(
      'preserves local tombstones when server returns success:true with empty deletedPatientIds/deletedVisitIds and blocks resurrection on pullDelta',
      () async {
        final dbService = await createInMemoryDbService(openedDbs);
        final auditRepo = AuditRepository(databaseService: dbService);

        final patient = makePatient();
        final visit = makeVisit(patient: patient);

        final unconfirmedApi = _UnconfirmedDeleteCentralApiService(
          serverPatients: [patient.copyWith(isSynced: true)],
          serverVisits: [visit],
        );

        final patientRepo = PatientRepository(
          databaseService: dbService,
          auditRepository: auditRepo,
          centralApiService: unconfirmedApi,
        );
        final syncRepo = SyncRepository(
          databaseService: dbService,
          centralApiService: unconfirmedApi,
          auditRepository: auditRepo,
        );

        final db = await dbService.database;
        await db.insert(DatabaseTables.tablePatients, patient.copyWith(isSynced: true).toMap());
        await db.insert(DatabaseTables.tableClinicalVisits, visit.toMap());

        // Delete patient (awaited push returns success:true, deletedPatientIds: [], deletedVisitIds: [])
        await patientRepo.deletePatient(patient.id, deviceId: 'dev-web-01');
        expect(unconfirmedApi.pushCallCount, 1);

        // Local tombstones MUST remain queued because server did not confirm deletion
        final queueAfterDelete = await db.query(DatabaseTables.tableDeletedEntitiesQueue);
        expect(
          queueAfterDelete.map((r) => r['entity_id']).toSet(),
          containsAll([patient.id, visit.id]),
        );

        // Even after a full sync cycle where server still returns the patient,
        // the preserved tombstones keep the patient suppressed and queued for retry.
        await syncRepo.executeFullSyncCycle(deviceId: 'dev-web-01', userId: 'usr-01');
        final roll = await patientRepo.getPatientsByCamp(patient.campId);
        expect(roll, isEmpty);

        final queueAfterSync = await db.query(DatabaseTables.tableDeletedEntitiesQueue);
        expect(
          queueAfterSync.map((r) => r['entity_id']).toSet(),
          containsAll([patient.id, visit.id]),
        );
      },
    );

    test(
      'awaiting deletePatient clears CentralApiService server state immediately and purges local tombstones on confirmation',
      () async {
        final dbService = await createInMemoryDbService(openedDbs);
        final auditRepo = AuditRepository(databaseService: dbService);
        final centralApi = CentralApiService();

        final patient = makePatient();
        final visit = makeVisit(patient: patient);

        final patientRepo = PatientRepository(
          databaseService: dbService,
          auditRepository: auditRepo,
          centralApiService: centralApi,
        );

        await patientRepo.registerPatient(
          patient,
          createdByUserId: 'usr-01',
          createdByUserName: 'Test Staff',
          createdByUserRole: AppConstants.roleDataTaker,
          deviceId: 'dev-web-01',
        );
        await patientRepo.saveClinicalVisit(
          visit,
          createdByUserId: 'usr-01',
          deviceId: 'dev-web-01',
        );
        expect(centralApi.serverStoredPatients.length, 1);
        expect(centralApi.serverStoredVisits.length, 1);

        // Awaited delete synchronously removes from mock server without any Future.delayed
        await patientRepo.deletePatient(patient.id, deviceId: 'dev-web-01');

        expect(centralApi.serverStoredPatients, isEmpty);
        expect(centralApi.serverStoredVisits, isEmpty);

        final db = await dbService.database;
        final queueRows = await db.query(DatabaseTables.tableDeletedEntitiesQueue);
        expect(queueRows, isEmpty);
      },
    );

    test(
      'offline deletePatient keeps tombstones across pullDelta, then syncRepo.pushDelta confirms deletion and clears queue',
      () async {
        final dbService = await createInMemoryDbService(openedDbs);
        final auditRepo = AuditRepository(databaseService: dbService);
        final centralApi = CentralApiService();

        final patient = makePatient();
        final visit = makeVisit(patient: patient);

        final onlinePatientRepo = PatientRepository(
          databaseService: dbService,
          auditRepository: auditRepo,
          centralApiService: centralApi,
        );
        await onlinePatientRepo.registerPatient(
          patient,
          createdByUserId: 'usr-01',
          createdByUserName: 'Test Staff',
          createdByUserRole: AppConstants.roleDataTaker,
          deviceId: 'dev-01',
        );
        await onlinePatientRepo.saveClinicalVisit(
          visit,
          createdByUserId: 'usr-01',
          deviceId: 'dev-01',
        );
        expect(centralApi.serverStoredPatients.length, 1);

        final offlinePatientRepo = PatientRepository(
          databaseService: dbService,
          auditRepository: auditRepo,
          enableCentralSync: false,
        );
        await offlinePatientRepo.deletePatient(
          patient.id,
          deletedByUserId: 'usr-01',
          deletedByUserRole: AppConstants.roleDataTaker,
          deviceId: 'dev-01',
        );

        final db = await dbService.database;
        final pendingBeforeSync = await db.query(DatabaseTables.tableDeletedEntitiesQueue);
        expect(
          pendingBeforeSync.map((r) => r['entity_id']).toSet(),
          containsAll([patient.id, visit.id]),
        );

        // Full sync cycle confirms deletion on CentralApiService and drains queue
        final syncRepo = SyncRepository(
          databaseService: dbService,
          centralApiService: centralApi,
          auditRepository: auditRepo,
        );
        await syncRepo.executeFullSyncCycle(deviceId: 'dev-01', userId: 'usr-01');

        expect(centralApi.serverStoredPatients, isEmpty);
        expect(centralApi.serverStoredVisits, isEmpty);
        expect(await db.query(DatabaseTables.tableDeletedEntitiesQueue), isEmpty);
        expect(await onlinePatientRepo.getPatientsByCamp(patient.campId), isEmpty);
      },
    );

    test(
      'end-to-end HTTP server: deletePatient persists deletion on GynoCampSyncServer so clean DB sync does not resurrect patients',
      () async {
        final server = GynoCampSyncServer(
          pgHost: '127.0.0.1',
          pgPort: 5432,
          pgDatabase: 'test',
          pgUsername: 'test',
          pgPassword: '',
        );
        final httpServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async => httpServer.close(force: true));

        httpServer.listen((request) async {
          await server.handleRequest(request);
        });

        final baseUrl = 'http://127.0.0.1:${httpServer.port}';
        final api = HttpCentralApiService(baseUrl: baseUrl);

        // Device 1: register patient + visit, push to server, then delete permanently
        final dbService1 = await createInMemoryDbService(openedDbs);
        final auditRepo1 = AuditRepository(databaseService: dbService1);
        final patientRepo1 = PatientRepository(
          databaseService: dbService1,
          auditRepository: auditRepo1,
          centralApiService: api,
        );
        final syncRepo1 = SyncRepository(
          databaseService: dbService1,
          centralApiService: api,
          auditRepository: auditRepo1,
        );

        final camp = CampModel(
          id: 'camp-e2e-01',
          campCode: '123',
          name: '1st testing camp',
          district: 'Dhankuta',
          municipality: 'Dhankuta',
          ward: '05',
          venue: 'Health Post',
          startDate: DateTime(2026, 4, 1),
          endDate: DateTime(2026, 4, 2),
          status: CampStatus.open,
          createdAt: DateTime.now(),
        );
        final db1 = await dbService1.database;
        await db1.insert(DatabaseTables.tableCamps, camp.toMap());

        final patient = makePatient(campId: camp.id);
        final visit = makeVisit(patient: patient);
        await patientRepo1.registerPatient(
          patient,
          createdByUserId: 'usr-01',
          createdByUserName: 'Test Staff',
          createdByUserRole: AppConstants.roleDataTaker,
          deviceId: 'dev-web-01',
        );
        await patientRepo1.saveClinicalVisit(
          visit,
          createdByUserId: 'usr-01',
          deviceId: 'dev-web-01',
        );
        await syncRepo1.executeFullSyncCycle(deviceId: 'dev-web-01', userId: 'usr-01');

        // Confirm server actually holds the patient before deletion
        final preDeletePull = await api.pullDelta(deviceId: 'dev-check');
        expect(preDeletePull.patients.map((p) => p.id), contains(patient.id));

        // Delete permanently via repository (awaited directly)
        await patientRepo1.deletePatient(patient.id, deviceId: 'dev-web-01');
        expect(await db1.query(DatabaseTables.tableDeletedEntitiesQueue), isEmpty);

        // Fresh clean client DB (simulates flutter clean / cleared storage + rerun)
        final dbServiceClean = await createInMemoryDbService(openedDbs);
        final auditRepoClean = AuditRepository(databaseService: dbServiceClean);
        final syncRepoClean = SyncRepository(
          databaseService: dbServiceClean,
          centralApiService: api,
          auditRepository: auditRepoClean,
        );
        final patientRepoClean = PatientRepository(
          databaseService: dbServiceClean,
          auditRepository: auditRepoClean,
          centralApiService: api,
        );

        await syncRepoClean.executeFullSyncCycle(deviceId: 'dev-web-02', userId: 'usr-01');
        final cleanPatients = await patientRepoClean.getPatientsByCamp(camp.id);
        expect(cleanPatients, isEmpty, reason: 'Deleted patient must not reappear after clean rerun');

        // Direct REST DELETE /api/patients and DELETE /api/clinical_visits verification
        final p2 = makePatient(id: 'pat-rest-002', tokenId: 'GC-0123-2026-00002', campId: camp.id);
        final v2 = makeVisit(id: 'vis-rest-002', patient: p2);
        final pushRes = await api.pushDelta(
          SyncPushPayload(
            deviceId: 'dev-rest',
            generatedAt: DateTime.now(),
            patients: [p2],
            clinicalVisits: [v2],
          ),
        );
        expect(pushRes.success, isTrue);

        final missingIdRes = await http.delete(Uri.parse('$baseUrl/api/patients'));
        expect(missingIdRes.statusCode, 400);

        final delVisitRes = await http.delete(Uri.parse('$baseUrl/api/clinical_visits?id=${v2.id}'));
        expect(delVisitRes.statusCode, 200);
        expect((jsonDecode(delVisitRes.body) as Map)['success'], isTrue);

        final delPatRes = await http.delete(Uri.parse('$baseUrl/api/patients?id=${p2.id}'));
        expect(delPatRes.statusCode, 200);
        expect((jsonDecode(delPatRes.body) as Map)['deleted_patient_id'], p2.id);

        final postRestPull = await api.pullDelta(deviceId: 'dev-check-2');
        expect(postRestPull.patients, isEmpty);
        expect(postRestPull.clinicalVisits, isEmpty);
        expect(postRestPull.deletedPatientIds, containsAll([patient.id, p2.id]));
        expect(postRestPull.deletedVisitIds, containsAll([visit.id, v2.id]));
      },
    );

    test(
      'deleteClinicalVisit preserves tombstone when unconfirmed and SyncPushResponse.fromMap distinguishes omitted vs explicit empty deleted IDs',
      () async {
        final legacyParsed = SyncPushResponse.fromMap({
          'success': true,
          'server_timestamp': DateTime.now().toIso8601String(),
        });
        expect(legacyParsed.deletedPatientIds, isNull);
        expect(legacyParsed.deletedVisitIds, isNull);

        final explicitEmptyParsed = SyncPushResponse.fromMap({
          'success': true,
          'server_timestamp': DateTime.now().toIso8601String(),
          'deleted_patient_ids': <String>[],
          'deleted_visit_ids': ['vis-confirmed'],
        });
        expect(explicitEmptyParsed.deletedPatientIds, isEmpty);
        expect(explicitEmptyParsed.deletedVisitIds, ['vis-confirmed']);

        final dbService = await createInMemoryDbService(openedDbs);
        final auditRepo = AuditRepository(databaseService: dbService);
        final patient = makePatient();
        final visit = makeVisit(patient: patient);
        final unconfirmedApi = _UnconfirmedDeleteCentralApiService(
          serverPatients: [patient.copyWith(isSynced: true)],
          serverVisits: [visit],
        );

        final patientRepo = PatientRepository(
          databaseService: dbService,
          auditRepository: auditRepo,
          centralApiService: unconfirmedApi,
        );
        final db = await dbService.database;
        await db.insert(DatabaseTables.tablePatients, patient.copyWith(isSynced: true).toMap());
        await db.insert(DatabaseTables.tableClinicalVisits, visit.toMap());

        await patientRepo.deleteClinicalVisit(visit.id, deviceId: 'dev-web-01');
        final queueRows = await db.query(DatabaseTables.tableDeletedEntitiesQueue);
        expect(queueRows.map((r) => r['entity_id']).toList(), [visit.id]);

        // Now confirm against CentralApiService via SyncRepository.pushDelta
        final centralApi = CentralApiService();
        final syncRepo = SyncRepository(
          databaseService: dbService,
          centralApiService: centralApi,
          auditRepository: auditRepo,
        );
        final res = await syncRepo.pushDelta(deviceId: 'dev-web-01', userId: 'usr-01');
        expect(res.deletedVisitIds, contains(visit.id));
        expect(await db.query(DatabaseTables.tableDeletedEntitiesQueue), isEmpty);
      },
    );
  });
}
