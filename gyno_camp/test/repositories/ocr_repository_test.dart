import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/core/services/nepali_localization_service.dart';
import 'package:gyno_camp/core/services/ocr_form_service.dart';
import 'package:gyno_camp/core/utils/nepali_date_helper.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/ocr_scan_result_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/ocr_repository.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('OcrRepository SQLite Tests', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late PatientRepository patientRepo;
    late OcrRepository ocrRepo;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      auditRepo = AuditRepository(databaseService: dbService);
      patientRepo = PatientRepository(databaseService: dbService, auditRepository: auditRepo);
      ocrRepo = OcrRepository(
        ocrService: const OcrFormService(),
        patientRepository: patientRepo,
        auditRepository: auditRepo,
      );
    });

    tearDown(() async {
      await testDb.close();
    });

    test('processTextScan returns parsed scan result model with confidence', () async {
      final result = await ocrRepo.processTextScan(OcrFormService.sampleFullFormText);

      expect(result.demographics['firstName'], 'Maya');
      expect(result.demographics['surname'], 'Tamang');
      expect(result.vitals['systolicBp'], 130);
      expect(result.popStaging['highestPopStage'], 3);
      expect(result.overallConfidence, greaterThanOrEqualTo(0.80));
    });

    test('processDualPageScan processes Page 1 and Page 2 and merges results', () async {
      final page1File = XFile('test_samples/yellow_form_sample_page1.jpg');
      final page2File = XFile('test_samples/yellow_form_sample_page2.jpg');

      final result = await ocrRepo.processDualPageScan(page1File: page1File, page2File: page2File);

      expect(result.isDualPage, true);
      expect(result.demographics['firstName'], isNotNull);
      expect(result.demographics['surname'], isNotNull);
      expect(result.popStaging['highestPopStage'], isNotNull);
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('commitVerifiedScan saves patient, clinical visit and cryptographic audit log', () async {
      final scan = await ocrRepo.processTextScan(OcrFormService.sampleFullFormText);

      final patient = await ocrRepo.commitVerifiedScan(
        verifiedScan: scan,
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        userId: 'usr-datataker-01',
        userName: 'Sita Sharma',
        userRole: 'DataTaker',
        deviceId: 'dev-tab-01',
      );

      // Verify Patient in SQLite
      expect(patient.patientId, startsWith('GC-KTM01-2026-'));
      expect(patient.fullName, 'Maya Tamang');
      expect(patient.ward, '04');

      // Verify Clinical Visit in SQLite
      final visits = await patientRepo.getClinicalVisits(patient.id);
      expect(visits.length, 1);
      final visit = visits.first;
      expect(visit.systolicBp, 130);
      expect(visit.diastolicBp, 85);
      expect(visit.highestPopStage, 3);
      expect(visit.diagnoses, contains('POP'));
      expect(visit.medications, contains('metronidazol'));
      expect(visit.surgicalReferral, 'Scheer Memorial Hospital');

      // Verify Audit Log in SQLite
      final auditLogs = await auditRepo.getRecentLogs();
      final ocrAudit = auditLogs.firstWhere((log) => log.action == 'PATIENT_REGISTERED_VIA_OCR');
      expect(ocrAudit.userName, 'Sita Sharma');
      expect(ocrAudit.logHash, isNotEmpty);
    });

    test('Offline scan queue stores images locally in SQLite and manages queue lifecycle', () async {
      final dummyPage1 = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4]);
      final dummyPage2 = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 5, 6, 7, 8]);

      final queued = await ocrRepo.enqueueOfflineScan(
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        page1Bytes: dummyPage1,
        page2Bytes: dummyPage2,
        patientIdHint: 'KTM01-0012',
        intakeDateHint: '2083-08-01',
        userId: 'usr-datataker-01',
        userName: 'Sita Sharma',
        userRole: 'DataTaker',
        deviceId: 'dev-tab-01',
      );

      expect(queued.id, isNotEmpty);
      expect(queued.hasAnyImage, isTrue);
      expect(queued.patientIdHint, 'KTM01-0012');
      expect(queued.intakeDateHint, '2083-08-01');

      final pendingCount = await ocrRepo.getPendingOfflineScanCount();
      expect(pendingCount, 1);

      final items = await ocrRepo.getOfflineScanQueue(campId: 'camp-ktm-01');
      expect(items.length, 1);
      expect(items.first.page1Bytes, isNotEmpty);
      expect(items.first.page2Bytes, isNotEmpty);

      await ocrRepo.deleteOfflineScanQueueItem(queued.id);
      expect(await ocrRepo.getPendingOfflineScanCount(), 0);
    });

    test('Dual-page merge and commitVerifiedScan preserve Page 1 patientId, BS date, and update existing patientId without UNIQUE error', () async {
      final page1 = OcrScanResultModel(
        pageNumber: 1,
        rawText: 'Page 1 text',
        demographics: {
          'firstName': 'Gita',
          'surname': 'Karki',
          'age': 42,
          'patientId': 'KTM01-०१५',
          'intakeDate': '२०८३/०८/०१',
        },
        obstetrics: const {'deliveries': 3, 'livingChildren': 2, 'abortions': 1},
        popStaging: const {},
        vitals: const {},
        diagnoses: const [],
        medications: const [],
        fieldConfidences: const {'firstName': 0.95},
        overallConfidence: 0.95,
        intakeDate: '२०८३/०८/०१',
        scannedAt: DateTime.now(),
      );
      final page2 = OcrScanResultModel(
        pageNumber: 2,
        rawText: 'Page 2 text',
        demographics: {
          'firstName': null,
          'surname': null,
          'patientId': null,
        },
        obstetrics: const {},
        popStaging: const {'anteriorStage': 2, 'middleStage': 1, 'posteriorStage': 0, 'highestPopStage': 2},
        vitals: const {'systolicBp': 120, 'diastolicBp': 80},
        diagnoses: const ['cystitis'],
        medications: const ['Ciprofloxacin'],
        fieldConfidences: const {'popStaging': 0.92},
        overallConfidence: 0.92,
        scannedAt: DateTime.now(),
      );

      final merged = OcrScanResultModel.merge(page1, page2);
      expect(merged.demographics['firstName'], 'Gita');
      expect(merged.patientId, 'KTM01-०१५');
      expect(merged.intakeDate, '२०८३/०८/०१');

      // Normalize patient ID with Devanagari digits
      final expectedNormId = 'GC-KTM01-${DateTime.now().year}-00015';
      final normId = PatientModel.normalizePatientId(
        rawInput: merged.patientId!,
        campCode: 'KTM01',
      );
      expect(normId, expectedNormId);

      final saved1 = await ocrRepo.commitVerifiedScan(
        verifiedScan: merged,
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        userId: 'usr-1',
        userName: 'Staff',
        userRole: 'DataTaker',
        deviceId: 'dev-1',
      );
      expect(saved1.patientId, expectedNormId);
      // 2083-08-01 BS converts to ~Nov 2026 AD (never year 2083 AD!)
      expect(saved1.intakeDate.year, lessThan(2035));

      // Re-committing same patientId updates existing patient instead of throwing UNIQUE constraint error
      final updatedScan = merged.copyWith(
        demographics: {...merged.demographics, 'firstName': 'Gita Devi'},
      );
      final saved2 = await ocrRepo.commitVerifiedScan(
        verifiedScan: updatedScan,
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        userId: 'usr-1',
        userName: 'Staff',
        userRole: 'DataTaker',
        deviceId: 'dev-1',
      );
      expect(saved2.id, saved1.id);
      expect(saved2.firstName, 'Gita Devi');

      // Test quick Nurse Seen and deletion of clinical visit and patient
      final nurseVisit = await patientRepo.recordNurseSeenQuickVisit(
        patient: saved2,
        nurseName: 'Nurse Anita',
        userId: 'usr-1',
        deviceId: 'dev-1',
      );
      expect(nurseVisit.primaryNurseName, 'Nurse Anita');

      await patientRepo.deleteClinicalVisit(
        nurseVisit.id,
        deletedByUserId: 'usr-1',
        deletedByUserName: 'Staff',
        deletedByUserRole: 'DataTaker',
        deviceId: 'dev-1',
      );
      await patientRepo.deletePatient(
        saved2.id,
        deletedByUserId: 'usr-1',
        deletedByUserName: 'Staff',
        deletedByUserRole: 'DataTaker',
        deviceId: 'dev-1',
      );
      final afterDelete = await patientRepo.getPatientByPatientId(saved2.patientId);
      expect(afterDelete, isNull);
    });

    test('commitVerifiedScan preserves distinct BS days 10..16 across Intake and all 6 station dates', () async {
      // Verify helper directly across BS days 1..27, 28..32, Devanagari, and clamping.
      expect(NepaliLocalizationService.formatBsDateOnly(OcrRepository.parseFormDateOrNull('2083-04-10')!), '2083-04-10 BS');
      expect(NepaliLocalizationService.formatBsDateOnly(OcrRepository.parseFormDateOrNull('2083-04-11 BS')!), '2083-04-11 BS');
      expect(NepaliLocalizationService.formatBsDateOnly(OcrRepository.parseFormDateOrNull('२०८३-०४-१६')!), '2083-04-16 BS');
      final maxChaitraDays = NepaliDateHelper.getDaysInBsMonth(2083, 12).toString().padLeft(2, '0');
      expect(NepaliLocalizationService.formatBsDateOnly(OcrRepository.parseFormDateOrNull('2083-12-32 BS')!), '2083-12-$maxChaitraDays BS');

      final scan = OcrScanResultModel(
        pageNumber: 0,
        isDualPage: true,
        rawText: 'Kamala Rai',
        demographics: const {
          'firstName': 'KAMALA',
          'surname': 'RAI',
          'age': 58,
          'patientId': 'GC-0007-2026-00112',
          'ward': '05',
          'district': 'Dhankuta',
          'municipality': 'Dhankuta Mun',
          'province': 'Koshi',
          'intakeDate': '2083-04-10',
          'anamnesisDate': '2083-04-11',
        },
        obstetrics: const {'deliveries': 6, 'livingChildren': 5, 'abortions': 1},
        popStaging: const {'anteriorStage': 2, 'middleStage': 3, 'posteriorStage': 1, 'highestPopStage': 3},
        vitals: const {'systolicBp': 138, 'diastolicBp': 86, 'pulseRate': 78, 'spo2': 97, 'bloodGlucose': 112},
        diagnoses: const ['stress incontinence', 'weak pelvic floor muscle'],
        medications: const ['estradiol crème'],
        intakeDate: '2083-04-10',
        anamnesisDate: '2083-04-11',
        examDate: '2083-04-12',
        labTestDate: '2083-04-13',
        conclusionDate: '2083-04-14',
        treatmentDate: '2083-04-15',
        outtakeDate: '2083-04-16',
        fieldConfidences: const {'firstName': 0.99},
        overallConfidence: 0.99,
        scannedAt: DateTime(2026, 11, 17),
      );

      final savedPatient = await ocrRepo.commitVerifiedScan(
        verifiedScan: scan,
        campId: 'camp-dhk-01',
        campCode: '0007',
        userId: 'usr-1',
        userName: 'Staff',
        userRole: 'DataTaker',
        deviceId: 'dev-1',
      );

      final reloadedPatient = await patientRepo.getPatientByPatientId(savedPatient.patientId);
      final reloadedVisit = await patientRepo.getLatestClinicalVisit(savedPatient.patientId);

      expect(reloadedPatient, isNotNull);
      expect(reloadedVisit, isNotNull);
      expect(NepaliLocalizationService.formatBsDateOnly(reloadedPatient!.intakeDate), '2083-04-10 BS');
      expect(NepaliLocalizationService.formatBsDateOnly(reloadedVisit!.anamnesisDate!), '2083-04-11 BS');
      expect(NepaliLocalizationService.formatBsDateOnly(reloadedVisit.examDate!), '2083-04-12 BS');
      expect(NepaliLocalizationService.formatBsDateOnly(reloadedVisit.labTestDate!), '2083-04-13 BS');
      expect(NepaliLocalizationService.formatBsDateOnly(reloadedVisit.conclusionDate!), '2083-04-14 BS');
      expect(NepaliLocalizationService.formatBsDateOnly(reloadedVisit.treatmentDate!), '2083-04-15 BS');
      expect(NepaliLocalizationService.formatBsDateOnly(reloadedVisit.outtakeDate!), '2083-04-16 BS');
    });

    test('UTC TIMESTAMPTZ strings preserve Nepal calendar day across model fromMap and toNepali', () {
      // 2083-04-10 BS = 2026-07-26 AD; Nepal midnight serialized as UTC is 2026-07-25T18:15:00.000Z.
      final p = PatientModel.fromMap({
        'id': 'pat-utc',
        'patient_id': 'GC-0007-2026-00112',
        'camp_id': 'camp-1',
        'camp_code': '0007',
        'intake_date': '2026-07-25T18:15:00.000Z',
        'first_name': 'KAMALA',
        'surname': 'RAI',
        'age': 58,
        'ward': '05',
        'created_at': '2026-07-25T18:15:00.000Z',
      });
      final v = ClinicalVisitModel.fromMap({
        'id': 'vis-utc',
        'patient_id': 'GC-0007-2026-00112',
        'camp_id': 'camp-1',
        'visit_date': '2026-07-30T18:15:00.000Z',
        'anamnesis_date': '2026-07-26T18:15:00.000Z',
        'exam_date': '2026-07-27T18:15:00.000Z',
        'lab_test_date': '2026-07-29T00:00:00.000Z',
        'created_at': '2026-07-25T18:15:00.000Z',
      });

      expect(NepaliLocalizationService.formatBsDateOnly(p.intakeDate), '2083-04-10 BS');
      expect(NepaliLocalizationService.formatBsDateOnly(v.anamnesisDate!), '2083-04-11 BS');
      expect(NepaliLocalizationService.formatBsDateOnly(v.examDate!), '2083-04-12 BS');
      expect(NepaliLocalizationService.formatBsDateOnly(v.labTestDate!), '2083-04-13 BS');
      expect(NepaliLocalizationService.formatBsDateOnly(v.visitDate), '2083-04-15 BS');
    });
  });
}
