import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/core/services/nepali_localization_service.dart';
import 'package:gyno_camp/core/services/ocr_form_service.dart';
import 'package:gyno_camp/core/services/report_aggregation_service.dart';
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
      expect(patient.patientId, '00001');
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

      // Normalize patient ID with Devanagari digits -> 5-digit '00015'
      const expectedNormId = '00015';
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
        medications: const ['estradiol crème', 'Calcium + Vit D3'],
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
      expect(reloadedVisit.medications, equals(['estradiol crème']));
      expect(reloadedVisit.customMedication, equals('Calcium + Vit D3'));
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

    test('Retains Page 1 & Page 2 scan photos after commit/auto-sync, supports in-place review & correction, and deletes photos without deleting patient record', () async {
      final dummyPage1 = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 10, 20, 30, 40]);
      final dummyPage2 = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 50, 60, 70, 80]);

      // 1. Enqueue an offline dual-page scan
      final queued = await ocrRepo.enqueueOfflineScan(
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        page1Bytes: dummyPage1,
        page2Bytes: dummyPage2,
        patientIdHint: 'KTM01-0099',
        intakeDateHint: '2083-08-01',
        userId: 'usr-datataker-01',
        userName: 'Sita Sharma',
        userRole: 'DataTaker',
        deviceId: 'dev-tab-01',
      );
      expect(await ocrRepo.getPendingOfflineScanCount(), 1);

      // 2. Simulate auto-sync commit (status -> completed, reviewStatus -> needs_review, photos retained)
      final initialScan = await ocrRepo.processTextScan(OcrFormService.sampleFullFormText);
      final autoCommittedPatient = await ocrRepo.commitVerifiedScan(
        verifiedScan: initialScan.copyWith(
          demographics: {
            ...initialScan.demographics,
            'patientId': 'KTM01-0099',
            'firstName': 'Saraswati',
            'surname': 'Adhikari',
          },
        ),
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        userId: 'usr-datataker-01',
        userName: 'Sita Sharma',
        userRole: 'DataTaker',
        deviceId: 'dev-tab-01',
        archiveItemId: queued.id,
        reviewStatus: 'needs_review',
      );

      // Pending offline scan count drops to 0 because status is now 'completed'
      expect(await ocrRepo.getPendingOfflineScanCount(), 0);

      // However, the scan photo archive is retained for review & correction!
      final patientPhotos = await ocrRepo.getScanPhotoArchiveForPatient(
        patientUuid: autoCommittedPatient.id,
        patientId: autoCommittedPatient.patientId,
      );
      expect(patientPhotos.length, 1);
      final archivedItem = patientPhotos.first;
      expect(archivedItem.id, queued.id);
      expect(archivedItem.isCompleted, isTrue);
      expect(archivedItem.needsReview, isTrue);
      expect(archivedItem.hasPage1, isTrue);
      expect(archivedItem.hasPage2, isTrue);
      expect(archivedItem.committedPatientUuid, autoCommittedPatient.id);
      expect(archivedItem.committedVisitId, isNotNull);
      expect(archivedItem.parsedExtractedResult, isNotNull);
      expect(archivedItem.parsedExtractedResult!.demographics['firstName'], 'Saraswati');

      // 3. Staff reviews & corrects the auto-saved record in split-screen mode
      final correctedScan = archivedItem.parsedExtractedResult!.copyWith(
        demographics: {
          ...archivedItem.parsedExtractedResult!.demographics,
          'firstName': 'Saraswati Devi',
          'age': 49,
        },
        vitals: {
          ...archivedItem.parsedExtractedResult!.vitals,
          'systolicBp': 142,
        },
      );
      final updatedPatient = await ocrRepo.commitVerifiedScan(
        verifiedScan: correctedScan,
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        userId: 'usr-datataker-01',
        userName: 'Sita Sharma',
        userRole: 'DataTaker',
        deviceId: 'dev-tab-01',
        existingPatientUuid: archivedItem.committedPatientUuid,
        existingVisitId: archivedItem.committedVisitId,
        archiveItemId: archivedItem.id,
        reviewStatus: 'verified',
      );

      // Verify existing patient & clinical visit were updated in-place (no duplicate visit created!)
      expect(updatedPatient.id, autoCommittedPatient.id);
      expect(updatedPatient.firstName, 'Saraswati Devi');
      expect(updatedPatient.age, 49);

      final visits = await patientRepo.getClinicalVisits(
        updatedPatient.patientId,
        patientUuid: updatedPatient.id,
      );
      expect(visits.length, 1);
      expect(visits.first.id, archivedItem.committedVisitId);
      expect(visits.first.systolicBp, 142);

      final verifiedPhotos = await ocrRepo.getScanPhotoArchiveForPatient(
        patientUuid: updatedPatient.id,
      );
      expect(verifiedPhotos.first.isVerified, isTrue);

      // 4. Delete Page 1 photo only -> Page 2 photo remains, patient & visit remain intact
      await ocrRepo.deleteScanPhoto(archivedItem.id, pageNumber: 1);
      final afterP1Delete = await ocrRepo.getScanPhotoArchiveForPatient(
        patientUuid: updatedPatient.id,
      );
      expect(afterP1Delete.length, 1);
      expect(afterP1Delete.first.hasPage1, isFalse);
      expect(afterP1Delete.first.hasPage2, isTrue);

      // 5. Delete remaining photos -> archive removed, patient & visit STILL remain intact in SQLite
      await ocrRepo.deleteScanPhoto(archivedItem.id);
      final afterAllPhotosDelete = await ocrRepo.getScanPhotoArchiveForPatient(
        patientUuid: updatedPatient.id,
      );
      expect(afterAllPhotosDelete, isEmpty);

      final intactPatient = await patientRepo.getPatientByPatientId(updatedPatient.patientId);
      final intactVisits = await patientRepo.getClinicalVisits(
        updatedPatient.patientId,
        patientUuid: updatedPatient.id,
      );
      expect(intactPatient, isNotNull);
      expect(intactPatient!.firstName, 'Saraswati Devi');
      expect(intactVisits.length, 1);
      expect(intactVisits.first.systolicBp, 142);
    });

    test('getOfflineScanQueue reads multi-megabyte legacy Base64 images in SUBSTR chunks without CursorWindow overflow', () async {
      // Insert a legacy > 2.2 MB Base64 row directly into SQLite to simulate an existing oversized row on Android
      final hugeP1Base64 = 'A' * 1200000;
      final hugeP2Base64 = 'B' * 1200000;
      final nowIso = DateTime.now().toIso8601String();
      await testDb.insert('offline_scan_queue', {
        'id': 'legacy-huge-row',
        'camp_id': 'camp-ktm-01',
        'camp_code': 'KTM01',
        'page1_image_base64': hugeP1Base64,
        'page2_image_base64': hugeP2Base64,
        'status': 'completed',
        'review_status': 'needs_review',
        'committed_patient_uuid': 'pat-huge',
        'committed_patient_id': 'GC-KTM01-2026-00999',
        'committed_patient_name': 'Oversized Photo Patient',
        'created_by_user_id': 'usr-1',
        'created_by_user_name': 'Staff',
        'created_by_user_role': 'DataTaker',
        'device_id': 'dev-1',
        'tenant_id': 'tenant_default',
        'created_at': nowIso,
        'updated_at': nowIso,
      });

      final queue = await ocrRepo.getOfflineScanQueue(campId: 'camp-ktm-01');
      expect(queue.length, 1);
      expect(queue.first.page1ImageBase64?.length, 1200000);
      expect(queue.first.page2ImageBase64?.length, 1200000);
      expect(queue.first.page1ImageBase64, hugeP1Base64);
      expect(queue.first.page2ImageBase64, hugeP2Base64);
    });

    test('commitVerifiedScan preserves null vitals when not recorded instead of injecting 120/80/78/98/110', () async {
      final scanWithoutVitals = OcrScanResultModel(
        pageNumber: 1,
        isDualPage: false,
        rawText: 'Page 1 only scan with no vitals',
        demographics: const {
          'firstName': 'Bina',
          'surname': 'Gurung',
          'age': 39,
          'ward': '02',
          'district': 'Kathmandu',
          'municipality': 'Budhanilkantha',
        },
        obstetrics: const {'deliveries': 2, 'livingChildren': 2, 'abortions': 0},
        popStaging: const {},
        vitals: const {},
        diagnoses: const [],
        medications: const [],
        fieldConfidences: const {'firstName': 0.95},
        overallConfidence: 0.95,
        scannedAt: DateTime.now(),
      );

      final savedPatient = await ocrRepo.commitVerifiedScan(
        verifiedScan: scanWithoutVitals,
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        userId: 'usr-1',
        userName: 'Staff',
        userRole: 'DataTaker',
        deviceId: 'dev-1',
      );

      final visit = await patientRepo.getLatestClinicalVisit(
        savedPatient.patientId,
        patientUuid: savedPatient.id,
      );
      expect(visit, isNotNull);
      expect(visit!.systolicBp, isNull);
      expect(visit.diastolicBp, isNull);
      expect(visit.pulse, isNull);
      expect(visit.spo2, isNull);
      expect(visit.glucose, isNull);
      expect(visit.surgicalReferral, isNull);
      expect(visit.uterusInside, isNull);
      expect(visit.pelvicFloorTone, isNull);
      expect(visit.popAnteriorStage, isNull);
      expect(visit.popMiddleStage, isNull);
      expect(visit.popPosteriorStage, isNull);
      expect(visit.highestPopStage, isNull);
      expect(visit.urineTest, isNull);
      expect(visit.pregnancyTest, isNull);

      // Verify null POP stages do NOT inflate Stage 0 prevalence counts in analytics
      final report = ReportAggregationService().aggregate(
        patients: [savedPatient],
        visits: [visit],
      );
      expect(report.highestPopStages[0], 0);
      expect(report.anteriorStages[0], 0);
      expect(report.middleStages[0], 0);
      expect(report.posteriorStages[0], 0);
      expect(report.significantPopCount, 0);
    });

    test('deleteAllScanPhotos clears completed archive photos in target camp while preserving pending offline queue, other camps, and patient records', () async {
      final dummyPage1 = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
      final sampleScan = await ocrRepo.processTextScan(OcrFormService.sampleFullFormText);

      // 1. Two completed archive entries in camp-ktm-01
      final q1 = await ocrRepo.enqueueOfflineScan(
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        page1Bytes: dummyPage1,
        patientIdHint: '00091',
        userId: 'usr-1',
        userName: 'Staff',
        userRole: 'DataTaker',
        deviceId: 'dev-1',
      );
      final pat1 = await ocrRepo.commitVerifiedScan(
        verifiedScan: sampleScan.copyWith(
          demographics: {
            ...sampleScan.demographics,
            'patientId': '00091',
            'firstName': 'Asha',
            'surname': 'Thapa',
          },
        ),
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        userId: 'usr-1',
        userName: 'Staff',
        deviceId: 'dev-1',
        archiveItemId: q1.id,
        reviewStatus: 'verified',
      );

      final q2 = await ocrRepo.enqueueOfflineScan(
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        page1Bytes: dummyPage1,
        patientIdHint: '00092',
        userId: 'usr-1',
        userName: 'Staff',
        userRole: 'DataTaker',
        deviceId: 'dev-1',
      );
      final pat2 = await ocrRepo.commitVerifiedScan(
        verifiedScan: sampleScan.copyWith(
          demographics: {
            ...sampleScan.demographics,
            'patientId': '00092',
            'firstName': 'Rita',
            'surname': 'Gurung',
          },
        ),
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        userId: 'usr-1',
        userName: 'Staff',
        deviceId: 'dev-1',
        archiveItemId: q2.id,
        reviewStatus: 'verified',
      );

      // 2. Unsynced pending scan in camp-ktm-01 (MUST NOT be deleted)
      final pendingItem = await ocrRepo.enqueueOfflineScan(
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        page1Bytes: dummyPage1,
        patientIdHint: '00093',
        userId: 'usr-1',
        userName: 'Staff',
        userRole: 'DataTaker',
        deviceId: 'dev-1',
      );

      // 3. Completed archive entry in a DIFFERENT camp (MUST NOT be deleted when scoped to camp-ktm-01)
      final qOtherCamp = await ocrRepo.enqueueOfflineScan(
        campId: 'camp-pok-02',
        campCode: 'POK02',
        page1Bytes: dummyPage1,
        patientIdHint: '00094',
        userId: 'usr-1',
        userName: 'Staff',
        userRole: 'DataTaker',
        deviceId: 'dev-1',
      );
      await ocrRepo.commitVerifiedScan(
        verifiedScan: sampleScan.copyWith(
          demographics: {
            ...sampleScan.demographics,
            'patientId': '00094',
            'firstName': 'Sita',
            'surname': 'Karki',
          },
        ),
        campId: 'camp-pok-02',
        campCode: 'POK02',
        userId: 'usr-1',
        userName: 'Staff',
        deviceId: 'dev-1',
        archiveItemId: qOtherCamp.id,
        reviewStatus: 'verified',
      );

      // Delete all completed scan photos for camp-ktm-01
      final deletedCount = await ocrRepo.deleteAllScanPhotos(campId: 'camp-ktm-01');
      expect(deletedCount, 2);

      final remainingKtmQueue = await ocrRepo.getOfflineScanQueue(campId: 'camp-ktm-01');
      expect(remainingKtmQueue.length, 1);
      expect(remainingKtmQueue.first.id, pendingItem.id);
      expect(remainingKtmQueue.first.isPendingOrFailed, isTrue);

      // Both committed patients' dossiers show zero photos, yet patients & visits stay intact
      expect(
        await ocrRepo.getScanPhotoArchiveForPatient(
          patientUuid: pat1.id,
          patientId: pat1.patientId,
          campId: pat1.campId,
        ),
        isEmpty,
      );
      expect(
        await ocrRepo.getScanPhotoArchiveForPatient(
          patientUuid: pat2.id,
          patientId: pat2.patientId,
          campId: pat2.campId,
        ),
        isEmpty,
      );
      expect(await patientRepo.getPatientByPatientId(pat1.patientId), isNotNull);
      expect(await patientRepo.getPatientByPatientId(pat2.patientId), isNotNull);
      expect(await patientRepo.getClinicalVisits(pat1.patientId, patientUuid: pat1.id), hasLength(1));

      // Other camp's archive item remains intact
      final pokQueue = await ocrRepo.getOfflineScanQueue(campId: 'camp-pok-02');
      expect(pokQueue.length, 1);
      expect(pokQueue.first.isCompleted, isTrue);
    });

    test('getScanPhotoArchiveForPatient scopes by camp and patient UUID, and deletePatient/deleteScanPhoto leave zero stale photos', () async {
      final dummyPage1 = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 5, 6, 7]);
      final sampleScan = await ocrRepo.processTextScan(OcrFormService.sampleFullFormText);

      // Patient 00099 in camp-ktm-01 committed with photo + duplicate completed row
      final saved = await ocrRepo.commitVerifiedScan(
        verifiedScan: sampleScan.copyWith(
          demographics: {
            ...sampleScan.demographics,
            'patientId': '00099',
            'firstName': 'Anish',
            'surname': 'Tiwari',
          },
        ),
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        userId: 'usr-1',
        userName: 'Staff',
        deviceId: 'dev-1',
        page1ImageBytes: dummyPage1,
      );

      // Pending item + other camp completed item sharing token '00099' must NOT bleed into camp-ktm-01 dossier
      await ocrRepo.enqueueOfflineScan(
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        page1Bytes: dummyPage1,
        patientIdHint: '00099',
        userId: 'usr-1',
        userName: 'Staff',
        userRole: 'DataTaker',
        deviceId: 'dev-1',
      );
      final nowIso = DateTime.now().toIso8601String();
      await testDb.insert('offline_scan_queue', {
        'id': 'other-camp-00099',
        'camp_id': 'camp-other-99',
        'camp_code': 'OTH99',
        'page1_image_path': '/tmp/other.jpg',
        'patient_token_hint': '00099',
        'status': 'completed',
        'review_status': 'verified',
        'committed_patient_uuid': 'different-uuid',
        'committed_patient_id': '00099',
        'committed_patient_name': 'Other Camp Patient',
        'created_by_user_id': 'usr-1',
        'created_by_user_name': 'Staff',
        'created_by_user_role': 'DataTaker',
        'device_id': 'dev-1',
        'tenant_id': 'tenant_default',
        'created_at': nowIso,
        'updated_at': nowIso,
      });

      final dossierPhotos = await ocrRepo.getScanPhotoArchiveForPatient(
        patientUuid: saved.id,
        patientId: saved.patientId,
        campId: saved.campId,
      );
      expect(dossierPhotos.length, 1);
      expect(dossierPhotos.first.committedPatientUuid, saved.id);

      // Simulate an extra legacy duplicate completed row for the exact same patient UUID
      await testDb.insert('offline_scan_queue', {
        'id': 'dup-row-for-same-patient',
        'camp_id': 'camp-ktm-01',
        'camp_code': 'KTM01',
        'page1_image_path': '/tmp/dup.jpg',
        'patient_token_hint': '00099',
        'status': 'completed',
        'review_status': 'verified',
        'committed_patient_uuid': saved.id,
        'committed_patient_id': '00099',
        'committed_patient_name': 'Anish Tiwari',
        'created_by_user_id': 'usr-1',
        'created_by_user_name': 'Staff',
        'created_by_user_role': 'DataTaker',
        'device_id': 'dev-1',
        'tenant_id': 'tenant_default',
        'created_at': nowIso,
        'updated_at': nowIso,
      });

      // Deleting from archive clears all completed rows for this patient -> dossier is empty
      await ocrRepo.deleteScanPhoto(dossierPhotos.first.id);
      expect(
        await ocrRepo.getScanPhotoArchiveForPatient(
          patientUuid: saved.id,
          patientId: saved.patientId,
          campId: saved.campId,
        ),
        isEmpty,
      );

      // Re-commit another patient with reused token after deletePatient -> old archive cleaned up too
      final patToDelete = await ocrRepo.commitVerifiedScan(
        verifiedScan: sampleScan.copyWith(
          demographics: {
            ...sampleScan.demographics,
            'patientId': '00105',
            'firstName': 'Maya',
            'surname': 'Lama',
          },
        ),
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        userId: 'usr-1',
        userName: 'Staff',
        deviceId: 'dev-1',
        page1ImageBytes: dummyPage1,
      );
      expect(
        await ocrRepo.getScanPhotoArchiveForPatient(
          patientUuid: patToDelete.id,
          patientId: patToDelete.patientId,
          campId: patToDelete.campId,
        ),
        hasLength(1),
      );
      await patientRepo.deletePatient(patToDelete.id);
      expect(
        await ocrRepo.getScanPhotoArchiveForPatient(
          patientUuid: patToDelete.id,
          patientId: patToDelete.patientId,
          campId: patToDelete.campId,
        ),
        isEmpty,
      );
    });
  });
}
