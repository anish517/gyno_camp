import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/constants/app_constants.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/core/database/database_tables.dart';
import 'package:gyno_camp/core/services/central_api_service.dart';
import 'package:gyno_camp/core/services/ocr_form_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/lookup_item_model.dart';
import 'package:gyno_camp/models/ocr_scan_result_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/models/sync_payload_model.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/ocr_repository.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';
import 'package:gyno_camp/repositories/sync_repository.dart';

class _RecordingCentralApiService implements ICentralApiService {
  final List<SyncPushPayload> recordedPushes = [];
  List<PatientModel> pullPatients = [];
  List<ClinicalVisitModel> pullVisits = [];
  List<String> pullDeletedPatientIds = [];
  List<String> pullDeletedVisitIds = [];

  @override
  Future<bool> pingServer() async => true;

  @override
  Future<SyncPushResponse> pushDelta(SyncPushPayload payload) async {
    recordedPushes.add(payload);
    return SyncPushResponse(
      success: true,
      serverTimestamp: DateTime.now(),
      syncedPatientIds: payload.patients.map((p) => p.id).toList(),
      syncedVisitIds: payload.clinicalVisits.map((v) => v.id).toList(),
    );
  }

  @override
  Future<SyncPullResponse> pullDelta({DateTime? since, required String deviceId}) async {
    return SyncPullResponse(
      success: true,
      serverTimestamp: DateTime.now(),
      patients: pullPatients,
      clinicalVisits: pullVisits,
      deletedPatientIds: pullDeletedPatientIds,
      deletedVisitIds: pullDeletedVisitIds,
    );
  }

  @override
  List<ClinicalVisitModel> get serverStoredVisits => pullVisits;

  @override
  List<PatientModel> get serverStoredPatients => pullPatients;

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

  group('Scan Commit Race Condition & Token-ID Tombstone Regression Tests', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late _RecordingCentralApiService recordingApi;
    late PatientRepository patientRepo;
    late OcrRepository ocrRepo;
    late SyncRepository syncRepo;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      auditRepo = AuditRepository(databaseService: dbService);
      recordingApi = _RecordingCentralApiService();
      patientRepo = PatientRepository(
        databaseService: dbService,
        auditRepository: auditRepo,
        centralApiService: recordingApi,
      );
      ocrRepo = OcrRepository(
        databaseService: dbService,
        ocrService: const OcrFormService(),
        patientRepository: patientRepo,
        auditRepository: auditRepo,
      );
      syncRepo = SyncRepository(
        databaseService: dbService,
        centralApiService: recordingApi,
        auditRepository: auditRepo,
      );
    });

    tearDown(() async {
      await testDb.close();
    });

    OcrScanResultModel buildScannedForm({
      required String tokenId,
      required String firstName,
      required String surname,
    }) {
      return OcrScanResultModel(
        pageNumber: 0,
        rawText: 'Scanned Yellow Form',
        demographics: {
          'patientId': tokenId,
          'firstName': firstName,
          'surname': surname,
          'age': 29,
          'ward': '02',
          'district': 'Morang',
          'municipality': 'Urlabari',
          'mobile': '9779028646',
          'reasonsForVisit': ['discharge / itching'],
        },
        obstetrics: const {
          'deliveries': 2,
          'livingChildren': 2,
          'abortions': 0,
          'clinicalComplaints': ['discharge'],
        },
        popStaging: const {
          'anteriorStage': 1,
          'middleStage': 1,
          'posteriorStage': 0,
          'highestPopStage': 1,
        },
        vitals: const {
          'systolicBp': 118,
          'diastolicBp': 76,
          'pulseRate': 74,
          'spo2': 98,
        },
        diagnoses: const ['bacterial vaginosis'],
        medications: const ['metronidazol'],
        fieldConfidences: const {'firstName': 0.96},
        overallConfidence: 0.95,
        scannedAt: DateTime.now(),
      );
    }

    test('commitVerifiedScan pushes patient and clinical visit together in one payload', () async {
      final scan = buildScannedForm(
        tokenId: '00047',
        firstName: 'Kabita',
        surname: 'Chaudhary',
      );

      final savedPatient = await ocrRepo.commitVerifiedScan(
        verifiedScan: scan,
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        userId: 'usr-datataker-01',
        userName: 'Sita Sharma',
        userRole: AppConstants.roleDataTaker,
        deviceId: 'dev-web-01',
      );

      // Allow unawaited push microtask/future to settle
      await Future.delayed(const Duration(milliseconds: 20));

      expect(savedPatient.patientId, '00047');
      expect(recordingApi.recordedPushes.length, 1);

      final pushedPayload = recordingApi.recordedPushes.single;
      expect(pushedPayload.deviceId, 'dev-web-01');
      expect(pushedPayload.patients.length, 1);
      expect(pushedPayload.patients.single.id, savedPatient.id);
      expect(pushedPayload.clinicalVisits.length, 1);
      expect(pushedPayload.clinicalVisits.single.patientId, savedPatient.patientId);
    });

    test('deletePatient tombstones UUID only (not Token ID) and pushDelta reads entity_id', () async {
      final offlinePatientRepo = PatientRepository(
        databaseService: dbService,
        auditRepository: auditRepo,
        centralApiService: recordingApi,
        enableCentralSync: false,
      );
      final offlineOcrRepo = OcrRepository(
        databaseService: dbService,
        ocrService: const OcrFormService(),
        patientRepository: offlinePatientRepo,
        auditRepository: auditRepo,
      );

      final saved = await offlineOcrRepo.commitVerifiedScan(
        verifiedScan: buildScannedForm(
          tokenId: '00047',
          firstName: 'Kabita',
          surname: 'Chaudhary',
        ),
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        userId: 'usr-datataker-01',
        userName: 'Sita Sharma',
        deviceId: 'dev-web-01',
      );
      final visits = await offlinePatientRepo.getClinicalVisits(saved.patientId);
      expect(visits.length, 1);
      final oldVisitId = visits.single.id;

      await offlinePatientRepo.deletePatient(saved.id, deviceId: 'dev-web-01');

      final queuedRows = await testDb.query(DatabaseTables.tableDeletedEntitiesQueue);
      final queuedPatientIds = queuedRows
          .where((r) => r['entity_type'] == 'patient')
          .map((r) => r['entity_id'])
          .toList();
      final queuedVisitIds = queuedRows
          .where((r) => r['entity_type'] == 'clinical_visit')
          .map((r) => r['entity_id'])
          .toList();

      expect(queuedPatientIds, equals([saved.id]));
      expect(queuedPatientIds, isNot(contains(saved.patientId)));
      expect(queuedVisitIds, equals([oldVisitId]));

      // Now pushDelta when online: must push real entity_id values, not 'del-pat-...'
      await syncRepo.pushDelta(deviceId: 'dev-web-01', userId: 'usr-datataker-01');
      final push = recordingApi.recordedPushes.last;
      expect(push.deletedPatientIds, equals([saved.id]));
      expect(push.deletedVisitIds, equals([oldVisitId]));
      expect(await testDb.query(DatabaseTables.tableDeletedEntitiesQueue), isEmpty);
    });

    test('re-scanning a previously deleted Token ID keeps clinical visit and CLINICAL COMPLETED status after pullDelta', () async {
      // 1. Register and delete an earlier patient who used Token ID 00047
      final oldPatient = await ocrRepo.commitVerifiedScan(
        verifiedScan: buildScannedForm(
          tokenId: '00047',
          firstName: 'Old',
          surname: 'Test',
        ),
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        userId: 'usr-datataker-01',
        userName: 'Sita Sharma',
        deviceId: 'dev-web-01',
      );
      final oldVisit = (await patientRepo.getClinicalVisits(oldPatient.patientId)).single;
      await patientRepo.deletePatient(oldPatient.id, deviceId: 'dev-web-01');
      await Future.delayed(const Duration(milliseconds: 20));

      // 2. Scan, verify, and commit a new patient with the same Token ID 00047
      final newPatient = await ocrRepo.commitVerifiedScan(
        verifiedScan: buildScannedForm(
          tokenId: '00047',
          firstName: 'Kabita',
          surname: 'Chaudhary',
        ),
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        userId: 'usr-datataker-01',
        userName: 'Sita Sharma',
        deviceId: 'dev-web-01',
      );
      await Future.delayed(const Duration(milliseconds: 20));
      final newVisit = (await patientRepo.getClinicalVisits(newPatient.patientId)).single;

      // Simulate a legacy server still returning BOTH old UUID and stale Token ID in deleted_patient_ids
      recordingApi.pullDeletedPatientIds = [oldPatient.id, newPatient.patientId];
      recordingApi.pullDeletedVisitIds = [oldVisit.id];
      recordingApi.pullPatients = [newPatient.copyWith(isSynced: true)];
      recordingApi.pullVisits = [newVisit.copyWith(isSynced: true)];

      // 3. Run pullDelta (as triggered immediately by SSE sync_update)
      await syncRepo.pullDelta(deviceId: 'dev-web-01', userId: 'usr-datataker-01');

      // 4. Verify patient AND clinical visit both survive and status remains CLINICAL COMPLETED
      final roll = await patientRepo.getPatientsByCamp('camp-ktm-01');
      final kabita = roll.firstWhere((p) => p.id == newPatient.id);
      expect(kabita.hasClinicalVisit, isTrue);

      final loadedVisit = await patientRepo.getLatestClinicalVisit(
        kabita.patientId,
        patientUuid: kabita.id,
      );
      expect(loadedVisit, isNotNull);
      expect(loadedVisit!.deliveries, 2);
      expect(loadedVisit.livingChildren, 2);
      expect(loadedVisit.abortions, 0);
      expect(loadedVisit.systolicBp, 118);
    });

    test('pullDelta deletes patient and its clinical visits when matching patient UUID is in deletedPatientIds', () async {
      final patient = await ocrRepo.commitVerifiedScan(
        verifiedScan: buildScannedForm(
          tokenId: '00048',
          firstName: 'Sarita',
          surname: 'Limbu',
        ),
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        userId: 'usr-datataker-01',
        userName: 'Sita Sharma',
        deviceId: 'dev-web-01',
      );
      await Future.delayed(const Duration(milliseconds: 20));

      recordingApi.pullDeletedPatientIds = [patient.id];
      await syncRepo.pullDelta(deviceId: 'dev-other-02', userId: 'usr-datataker-01');

      final remainingPatients = await patientRepo.getPatientsByCamp('camp-ktm-01');
      expect(remainingPatients.where((p) => p.id == patient.id), isEmpty);
      final remainingVisits = await patientRepo.getClinicalVisits(patient.patientId);
      expect(remainingVisits, isEmpty);
    });
  });
}
