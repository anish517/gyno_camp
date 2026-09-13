import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/constants/app_constants.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/core/database/database_tables.dart';
import 'package:gyno_camp/core/services/central_api_service.dart';
import 'package:gyno_camp/core/services/pdf_report_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/models/sync_payload_model.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/auth_repository.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';
import 'package:gyno_camp/repositories/sync_repository.dart';

class _MockCentralApiService implements ICentralApiService {
  final List<PatientModel> mockPatients;
  final List<ClinicalVisitModel> mockVisits;

  _MockCentralApiService({
    this.mockPatients = const [],
    this.mockVisits = const [],
  });

  @override
  Future<SyncPullResponse> pullDelta({DateTime? since, required String deviceId}) async {
    return SyncPullResponse(
      success: true,
      serverTimestamp: DateTime.now(),
      camps: [],
      lookupItems: [],
      users: [],
      patients: mockPatients,
      clinicalVisits: mockVisits,
    );
  }

  @override
  Future<SyncPushResponse> pushDelta(SyncPushPayload payload) async {
    return SyncPushResponse(
      success: true,
      serverTimestamp: DateTime.now(),
      syncedPatientIds: payload.patients.map((p) => p.id).toList(),
      syncedVisitIds: payload.clinicalVisits.map((v) => v.id).toList(),
    );
  }

  @override
  Future<bool> pingServer() async => true;

  @override
  List<ClinicalVisitModel> get serverStoredVisits => mockVisits;

  @override
  List<PatientModel> get serverStoredPatients => mockPatients;

  @override
  void setMockServerCamps(List<CampModel> camps) {}

  @override
  void setMockServerLookupItems(List<dynamic> items) {}
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Bug Fixes Verification Suite', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late AuthRepository authRepo;
    late PatientRepository patientRepo;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      auditRepo = AuditRepository(databaseService: dbService);
      authRepo = AuthRepository(databaseService: dbService, auditRepository: auditRepo);
      patientRepo = PatientRepository(databaseService: dbService, auditRepository: auditRepo);
    });

    tearDown(() async {
      await testDb.close();
    });

    test('Fix 1: AuthRepository login strictly rejects null and empty passwords for credentialed users', () async {
      // 1. Check null password rejection
      final nullResult = await authRepo.login(
        email: 'admin@gynocamp.org',
        password: null,
        deviceId: 'dev-test-01',
      );
      expect(nullResult, isNull, reason: 'Null password must be rejected');

      // 2. Check empty password rejection
      final emptyResult = await authRepo.login(
        email: 'admin@gynocamp.org',
        password: '   ',
        deviceId: 'dev-test-01',
      );
      expect(emptyResult, isNull, reason: 'Whitespace-only password must be rejected');

      // 3. Valid password succeeds
      final successResult = await authRepo.login(
        email: 'admin@gynocamp.org',
        password: 'admin123',
        deviceId: 'dev-test-01',
      );
      expect(successResult, isNotNull);
      expect(successResult!.email, 'admin@gynocamp.org');
    });

    test('Fix 2: PatientRepository registerPatient increments sequence on collision and prevents silent overwrite', () async {
      // Register initial patient #1 (will be KTM01-2026-0001)
      final p1 = PatientModel(
        id: 'pat-001',
        patientId: '',
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        intakeDate: DateTime(2026, 3, 1),
        firstName: 'Sita',
        surname: 'Sharma',
        age: 35,
        ward: '01',
        mobile: '9841000001',
        createdAt: DateTime.now(),
        createdByUserId: 'usr-datataker-01',
        createdByDeviceId: 'dev-test-01',
      );
      final registered1 = await patientRepo.registerPatient(
        p1,
        createdByUserId: 'usr-datataker-01',
        createdByUserName: 'Sita Sharma',
        createdByUserRole: AppConstants.roleDataTaker,
        deviceId: 'dev-test-01',
      );
      expect(registered1.patientId, contains('0001'));

      // Manually simulate a collision: insert a pre-existing patient with 0002 directly
      final preExistingId = PatientModel.generatePatientId(
        campCode: 'KTM01',
        sequenceNumber: 2,
        year: 2026,
      );
      await testDb.insert(DatabaseTables.tablePatients, {
        'id': 'pat-pre-existing-002',
        'patient_id': preExistingId,
        'camp_id': 'camp-ktm-01',
        'camp_code': 'KTM01',
        'intake_date': DateTime(2026, 3, 1).toIso8601String(),
        'first_name': 'Existing',
        'surname': 'Patient',
        'age': 40,
        'ward': '02',
        'mobile': '9841000002',
        'created_at': DateTime.now().toIso8601String(),
        'created_by_user_id': 'usr-datataker-01',
        'created_by_device_id': 'dev-test-01',
      });

      // Now register another patient without explicit ID
      // COUNT(*) was 2, so without collision detection it would produce 0002 and overwrite Existing Patient!
      final p2 = PatientModel(
        id: 'pat-new-003',
        patientId: '',
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        intakeDate: DateTime(2026, 3, 1),
        firstName: 'Gita',
        surname: 'Thapa',
        age: 38,
        ward: '03',
        mobile: '9841000003',
        createdAt: DateTime.now(),
        createdByUserId: 'usr-datataker-01',
        createdByDeviceId: 'dev-test-01',
      );
      final registered2 = await patientRepo.registerPatient(
        p2,
        createdByUserId: 'usr-datataker-01',
        createdByUserName: 'Sita Sharma',
        createdByUserRole: AppConstants.roleDataTaker,
        deviceId: 'dev-test-01',
      );

      // Verify that sequence auto-incremented to 0003 to avoid collision
      expect(registered2.patientId, contains('0003'));

      // Verify original Existing Patient record was preserved intact
      final existingPreserved = await testDb.query(
        DatabaseTables.tablePatients,
        where: 'patient_id = ?',
        whereArgs: [preExistingId],
      );
      expect(existingPreserved.length, 1);
      expect(existingPreserved.first['first_name'], 'Existing');
    });

    test('Fix 3: SyncRepository pullDelta marks pulled cloud records as is_synced = 1 to prevent upload loops', () async {
      final cloudPatient = PatientModel(
        id: 'pat-cloud-999',
        patientId: 'KTM01-2026-0999',
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        intakeDate: DateTime(2026, 3, 1),
        firstName: 'Asha',
        surname: 'Rai',
        age: 29,
        ward: '05',
        mobile: '9841999999',
        createdAt: DateTime.now(),
        createdByUserId: 'usr-datataker-01',
        createdByDeviceId: 'dev-remote-01',
        isSynced: false, // Central server JSON might not have is_synced set
      );

      final cloudVisit = ClinicalVisitModel(
        id: 'vis-cloud-888',
        patientId: 'KTM01-2026-0999',
        campId: 'camp-ktm-01',
        tenantId: 'tenant_default',
        visitDate: DateTime.now(),
        createdAt: DateTime.now(),
        createdByUserId: 'usr-datataker-01',
        isSynced: false,
      );

      final mockApi = _MockCentralApiService(
        mockPatients: [cloudPatient],
        mockVisits: [cloudVisit],
      );
      final syncRepo = SyncRepository(
        databaseService: dbService,
        auditRepository: auditRepo,
        centralApiService: mockApi,
      );

      // Pull delta from central server
      final response = await syncRepo.pullDelta(deviceId: 'dev-test-01', userId: 'usr-datataker-01');
      expect(response.patients.length, 1);
      expect(response.clinicalVisits.length, 1);

      // Check SQLite table: is_synced MUST be 1
      final localPatientRows = await testDb.query(
        DatabaseTables.tablePatients,
        where: 'id = ?',
        whereArgs: ['pat-cloud-999'],
      );
      expect(localPatientRows.isNotEmpty, isTrue);
      expect(localPatientRows.first['is_synced'], 1);
      expect(localPatientRows.first['synced_at'], isNotNull);

      final localVisitRows = await testDb.query(
        DatabaseTables.tableClinicalVisits,
        where: 'id = ?',
        whereArgs: ['vis-cloud-888'],
      );
      expect(localVisitRows.isNotEmpty, isTrue);
      expect(localVisitRows.first['is_synced'], 1);

      // Verify getPendingCounts reports 0 pending patients and 0 pending visits (no loop)
      final pending = await syncRepo.getPendingCounts();
      expect(pending['patients'], 0);
      expect(pending['visits'], 0);
    });

    test('Fix 4: Clinical Visit audit log dynamically resolves staff user name and role', () async {
      // Register visit as Super Admin
      final visit = ClinicalVisitModel(
        id: 'vis-test-001',
        patientId: 'KTM01-2026-0001',
        campId: 'camp-ktm-01',
        tenantId: 'tenant_default',
        visitDate: DateTime.now(),
        deliveries: 2,
        livingChildren: 2,
        abortions: 0,
        popAnteriorStage: 1,
        popMiddleStage: 2,
        popPosteriorStage: 1,
        highestPopStage: 2,
        systolicBp: 120,
        diastolicBp: 80,
        pulse: 72,
        spo2: 99,
        diagnoses: ['Pelvic Organ Prolapse Stage 2'],
        medications: ['Pelvic floor muscle training'],
        followUpNeeded: true,
        createdAt: DateTime.now(),
        createdByUserId: 'usr-superadmin-01',
      );

      await patientRepo.saveClinicalVisit(
        visit,
        createdByUserId: 'usr-superadmin-01',
        deviceId: 'dev-test-01',
      );

      final logs = await auditRepo.getRecentLogs();
      final visitLog = logs.firstWhere((l) => l.entityId == 'vis-test-001');

      // Must be real user name and role from database, NOT hardcoded 'Field Doctor / Nurse'
      expect(visitLog.userName, contains('System Administrator'));
      expect(visitLog.userRole, AppConstants.roleSuperAdmin);
    });

    test('Fix 5: PdfReportService.sanitizeText prevents Helvetica Unicode exception on Devanagari characters', () async {
      const nepaliText = 'माया श्रेष्ठ (सुन्तली)';
      final sanitized = PdfReportService.sanitizeText(nepaliText);

      // All characters in sanitized output must be <= 255 (Latin-1 safe)
      expect(sanitized.runes.every((r) => r <= 255), isTrue);

      // Verify standard Helvetica pw.Document saves without exception
      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5,
          build: (ctx) => pw.Column(
            children: [
              pw.Text('Name: $sanitized'),
              pw.Text('Punctuation: ${PdfReportService.sanitizeText("Special quotes: ‘Hello’ — Test…")}'),
            ],
          ),
        ),
      );

      final Uint8List pdfBytes = await doc.save();
      expect(pdfBytes.isNotEmpty, isTrue);
    });
  });
}
