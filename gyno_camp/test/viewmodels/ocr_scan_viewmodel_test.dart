import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/core/services/gemini_ocr_service.dart';
import 'package:gyno_camp/core/services/ocr_form_service.dart';
import 'package:gyno_camp/models/ocr_scan_result_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/ocr_repository.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';
import 'package:gyno_camp/viewmodels/ocr_scan_viewmodel.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('OcrScanViewModel Tests', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late PatientRepository patientRepo;
    late OcrRepository ocrRepo;
    late OcrScanViewModel vm;

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
      vm = OcrScanViewModel(repository: ocrRepo);
    });

    tearDown(() async {
      await testDb.close();
    });

    test('Initial state has no scan result and is not processing', () {
      expect(vm.state.isProcessing, false);
      expect(vm.state.hasScanResult, false);
      expect(vm.state.committedPatient, isNull);
    });

    test('loadSample populates scanResult and successMessage', () async {
      await vm.loadSample('full');

      expect(vm.state.isProcessing, false);
      expect(vm.state.hasScanResult, true);
      expect(vm.state.scanResult!.demographics['firstName'], 'Maya');
      expect(vm.state.successMessage, contains('successfully'));
    });

    test('updateDemographic, updateVital, and updatePopStage mutate scan state', () async {
      await vm.loadSample('full');

      vm.updateDemographic('firstName', 'Aasha');
      expect(vm.state.scanResult!.demographics['firstName'], 'Aasha');

      vm.updateVital('systolicBp', 145);
      expect(vm.state.scanResult!.vitals['systolicBp'], 145);

      vm.updatePopStage('middleStage', 4);
      expect(vm.state.scanResult!.popStaging['middleStage'], 4);
      expect(vm.state.scanResult!.popStaging['highestPopStage'], 4);
    });

    test('toggleDiagnosis and toggleMedication add and remove items', () async {
      await vm.loadSample('full');

      // Add diagnosis
      vm.toggleDiagnosis('cystitis');
      expect(vm.state.scanResult!.diagnoses, contains('cystitis'));

      // Remove diagnosis
      vm.toggleDiagnosis('cystitis');
      expect(vm.state.scanResult!.diagnoses, isNot(contains('cystitis')));

      // Toggle medication
      vm.toggleMedication('Ciprofloxacin');
      expect(vm.state.scanResult!.medications, contains('Ciprofloxacin'));
      vm.toggleMedication('Ciprofloxacin');
      expect(vm.state.scanResult!.medications, isNot(contains('Ciprofloxacin')));
    });

    test('addDiagnosis, removeDiagnosis, addMedication, and removeMedication handle explicit operations', () async {
      await vm.loadSample('full');

      // Add custom diagnosis
      vm.addDiagnosis('Severe Anemia');
      expect(vm.state.scanResult!.diagnoses, contains('Severe Anemia'));
      // Add duplicate should not duplicate
      final countBefore = vm.state.scanResult!.diagnoses.where((d) => d == 'Severe Anemia').length;
      vm.addDiagnosis('Severe Anemia');
      final countAfter = vm.state.scanResult!.diagnoses.where((d) => d == 'Severe Anemia').length;
      expect(countBefore, countAfter);

      // Remove diagnosis
      vm.removeDiagnosis('Severe Anemia');
      expect(vm.state.scanResult!.diagnoses, isNot(contains('Severe Anemia')));

      // Add custom medication
      vm.addMedication('Ring Pessary 65mm');
      expect(vm.state.scanResult!.medications, contains('Ring Pessary 65mm'));

      // Remove medication
      vm.removeMedication('Ring Pessary 65mm');
      expect(vm.state.scanResult!.medications, isNot(contains('Ring Pessary 65mm')));
    });

    test('updateSurgicalReferral and updateFollowUpDestination update referral status', () async {
      await vm.loadSample('full');

      vm.updateSurgicalReferral('Model Hospital');
      expect(vm.state.scanResult!.surgicalReferral, 'Model Hospital');

      vm.updateSurgicalReferral(null);
      expect(vm.state.scanResult!.surgicalReferral, isNull);

      vm.updateFollowUpDestination('Camp Follow-up Day');
      expect(vm.state.scanResult!.followUpDestination, 'Camp Follow-up Day');
    });

    test('updateVital updates all 5 point-of-care vital metrics', () async {
      await vm.loadSample('full');

      vm.updateVital('systolicBp', 135);
      vm.updateVital('diastolicBp', 85);
      vm.updateVital('pulseRate', 82);
      vm.updateVital('spo2', 97);
      vm.updateVital('bloodGlucose', 125);

      expect(vm.state.scanResult!.vitals['systolicBp'], 135);
      expect(vm.state.scanResult!.vitals['diastolicBp'], 85);
      expect(vm.state.scanResult!.vitals['pulseRate'], 82);
      expect(vm.state.scanResult!.vitals['spo2'], 97);
      expect(vm.state.scanResult!.vitals['bloodGlucose'], 125);
    });

    test('loadSample with page1 and page2 manages slots and auto-merges when both ready', () async {
      await vm.loadSample('page1');
      expect(vm.state.hasPage1, true);
      expect(vm.state.hasPage2, false);
      expect(vm.state.isDualReady, false);
      expect(vm.state.page1Scan!.demographics['firstName'], 'Maya');

      await vm.loadSample('page2');
      expect(vm.state.hasPage1, true);
      expect(vm.state.hasPage2, true);
      expect(vm.state.isDualReady, true);
      expect(vm.state.scanResult, isNotNull);
      expect(vm.state.scanResult!.isDualPage, true);
      expect(vm.state.scanResult!.demographics['firstName'], 'Maya');
      expect(vm.state.scanResult!.popStaging['highestPopStage'], 3);
      expect(vm.state.scanResult!.vitals['systolicBp'], 130);

      // Switch inspection page
      vm.switchInspectionPage(2);
      expect(vm.state.activeInspectionPage, 2);

      // Clear slot 1
      vm.clearSlot(1);
      expect(vm.state.hasPage1, false);
      expect(vm.state.hasPage2, true);
    });

    test('confirmAndCommit saves patient and sets committedPatient state', () async {
      await vm.loadSample('full');

      final committed = await vm.confirmAndCommit(
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        userId: 'usr-1',
        userName: 'Sita Sharma',
        deviceId: 'dev-1',
        primaryNurseName: 'Nurse Rita',
        attendingNurseNames: ['Nurse Rita', 'Nurse Gita'],
      );

      expect(committed, isNotNull);
      expect(vm.state.committedPatient, isNotNull);
      expect(vm.state.committedPatient!.fullName, 'Maya Tamang');
      expect(vm.state.successMessage, contains('verified & saved'));

      // Reset restores clean state
      vm.resetScan();
      expect(vm.state.hasScanResult, false);
      expect(vm.state.committedPatient, isNull);
    });

    test('setExaminingNurse and toggleAttendingNurse update nurse assignment state', () async {
      await vm.loadSample('full');

      vm.setExaminingNurse('Sita Thapa');
      expect(vm.state.scanResult!.examiningNurse, 'Sita Thapa');
      expect(vm.state.scanResult!.attendingNurses, ['Sita Thapa']);

      // Toggle additional nurse
      vm.toggleAttendingNurse('Gita Rai');
      expect(vm.state.scanResult!.attendingNurses, ['Sita Thapa', 'Gita Rai']);

      // Untoggle first nurse
      vm.toggleAttendingNurse('Sita Thapa');
      expect(vm.state.scanResult!.attendingNurses, ['Gita Rai']);
      expect(vm.state.scanResult!.examiningNurse, 'Gita Rai');

      // Clear nurse
      vm.setExaminingNurse(null);
      expect(vm.state.scanResult!.examiningNurse, isNull);
      expect(vm.state.scanResult!.attendingNurses, isEmpty);
    });

    test('runLiveDuplicateCheck ignores reviewingPatientUuid while still flagging other patients', () async {
      await patientRepo.registerPatient(
        PatientModel(
          id: 'pat-other-ocr',
          patientId: '00050',
          campId: 'camp-ktm-01',
          campCode: 'KTM01',
          intakeDate: DateTime(2026, 3, 10),
          firstName: 'Kamala',
          surname: 'Rai',
          age: 40,
          mobile: '9800000111',
          ward: '02',
          createdAt: DateTime(2026, 3, 10),
          createdByUserId: 'usr-1',
          createdByDeviceId: 'dev-1',
        ),
        createdByUserId: 'usr-1',
        createdByUserName: 'Nurse',
        createdByUserRole: 'DATA_TAKER',
        deviceId: 'dev-1',
      );

      final reviewVm = OcrScanViewModel(
        repository: ocrRepo,
        patientRepository: patientRepo,
      );
      await reviewVm.loadSample('full');
      final committed = await reviewVm.confirmAndCommit(
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        userId: 'usr-1',
        userName: 'Sita Sharma',
        deviceId: 'dev-1',
      );
      expect(committed, isNotNull);
      expect(reviewVm.state.reviewingPatientUuid, committed!.id);

      // Same patient currently under review must not flag duplicate against herself
      await reviewVm.runLiveDuplicateCheck('camp-ktm-01');
      expect(reviewVm.state.duplicateResult.hasDuplicate, isFalse);

      // Changing mobile to match another registered patient must still flag duplicate
      reviewVm.updateDemographic('mobile', '9800000111');
      await reviewVm.runLiveDuplicateCheck('camp-ktm-01');
      expect(reviewVm.state.duplicateResult.hasDuplicate, isTrue);
      expect(reviewVm.state.duplicateResult.matchedPatient?.id, 'pat-other-ocr');
    });

    test('validateExtractedScan auto-detects Token ID conflict and blocks fresh duplicate commit until cleared or changed', () async {
      await patientRepo.registerPatient(
        PatientModel(
          id: 'pat-existing-99',
          patientId: '00099',
          campId: 'camp-ktm-01',
          campCode: 'KTM01',
          intakeDate: DateTime(2026, 11, 25),
          firstName: 'Sunita',
          surname: 'Tamang',
          age: 52,
          mobile: '9800000099',
          ward: '04',
          createdAt: DateTime(2026, 11, 25),
          createdByUserId: 'usr-1',
          createdByDeviceId: 'dev-1',
        ),
        createdByUserId: 'usr-1',
        createdByUserName: 'Nurse',
        createdByUserRole: 'DATA_TAKER',
        deviceId: 'dev-1',
      );

      final scanVm = OcrScanViewModel(
        repository: ocrRepo,
        patientRepository: patientRepo,
      );
      await scanVm.loadSample('full');
      scanVm.updateDemographic('patientId', '00099', campId: 'camp-ktm-01', campCode: 'KTM01');

      await scanVm.validateExtractedScan(campId: 'camp-ktm-01', campCode: 'KTM01');
      expect(scanVm.state.isPatientIdConflict, isTrue);
      expect(scanVm.state.patientIdConflictReason, contains('Sunita Tamang'));

      // Fresh commit with conflicting Token ID must fail and never overwrite Sunita or create a second patient row
      final blocked = await scanVm.confirmAndCommit(
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        userId: 'usr-1',
        userName: 'Nurse',
        deviceId: 'dev-1',
      );
      expect(blocked, isNull);
      expect(scanVm.state.isPatientIdConflict, isTrue);
      expect((await patientRepo.getPatientByPatientId('00099'))?.firstName, 'Sunita');

      // Clearing Token ID (Auto-Generate) resolves conflict and commits under next free 5-digit ID ('00100')
      scanVm.updateDemographic('patientId', '', campId: 'camp-ktm-01', campCode: 'KTM01');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(scanVm.state.isPatientIdConflict, isFalse);

      final autoGenerated = await scanVm.confirmAndCommit(
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
        userId: 'usr-1',
        userName: 'Nurse',
        deviceId: 'dev-1',
      );
      expect(autoGenerated, isNotNull);
      expect(autoGenerated!.patientId, '00100');
      expect((await patientRepo.getPatientsByCamp('camp-ktm-01')).length, 2);
    });

    test('stageCapturedImages queues Page 1 + Page 2 without calling OCR, and supports manual 1-by-1 and bulk background sync', () async {
      final scriptedGemini = _ScriptedQueueGeminiService([
        '00201',
        '00202',
        '00201', // Collides with first item to verify 2d6bf85 conflict protection during bulk sync
      ]);
      final queueRepo = OcrRepository(
        databaseService: dbService,
        ocrService: const OcrFormService(),
        patientRepository: patientRepo,
        auditRepository: auditRepo,
        geminiService: scriptedGemini,
      );
      final queueVm = OcrScanViewModel(
        repository: queueRepo,
        patientRepository: patientRepo,
      );
      await queueVm.loadOfflineQueue(campId: 'camp-ktm-01');

      final p1 = Uint8List.fromList([1, 2, 3]);
      final p2 = Uint8List.fromList([4, 5, 6]);

      // 1. Scan Page 1 -> staged instantly, 0 OCR calls, waiting for Page 2
      final qAfterP1 = await queueVm.stageCapturedImages(
        page1Bytes: p1,
        page1Path: 'p1_a.jpg',
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
      );
      expect(qAfterP1, isNull);
      expect(queueVm.state.isProcessing, isFalse);
      expect(queueVm.state.hasPage1Image, isTrue);
      expect(queueVm.state.hasPage2Image, isFalse);
      expect(scriptedGemini.extractCalls, 0);

      // 2. Scan Page 2 -> auto-queues pair in background, clears slots immediately, STILL 0 OCR calls
      final queued1 = await queueVm.stageCapturedImages(
        page2Bytes: p2,
        page2Path: 'p2_a.jpg',
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
      );
      expect(queued1, isNotNull);
      expect(queueVm.state.hasPage1Image, isFalse);
      expect(queueVm.state.hasPage2Image, isFalse);
      expect(queueVm.state.isProcessing, isFalse);
      expect(scriptedGemini.extractCalls, 0);
      expect(queueVm.state.pendingOfflineQueue.length, 1);

      // Queue two more dual-page forms rapidly (still 0 OCR calls!)
      final queued2 = await queueVm.stageCapturedImages(
        page1Bytes: p1,
        page2Bytes: p2,
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
      );
      final queued3 = await queueVm.stageCapturedImages(
        page1Bytes: p1,
        page2Bytes: p2,
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
      );
      expect(queued2, isNotNull);
      expect(queued3, isNotNull);
      expect(scriptedGemini.extractCalls, 0);
      expect(queueVm.state.pendingOfflineQueue.length, 3);

      // 3. Manual Mode (autoQueueDualPage = false) holds both pages in slots until explicit save
      queueVm.setAutoQueueDualPage(false);
      final held = await queueVm.stageCapturedImages(
        page1Bytes: p1,
        page2Bytes: p2,
        campId: 'camp-ktm-01',
        campCode: 'KTM01',
      );
      expect(held, isNull);
      expect(queueVm.state.hasPage1Image, isTrue);
      expect(queueVm.state.hasPage2Image, isTrue);
      queueVm.resetScan();
      queueVm.setAutoQueueDualPage(true);

      // 4. Manual One-by-One Background Sync on queued1 -> commits 00201 without setting isProcessing
      final firstItem = queueVm.state.pendingOfflineQueue.firstWhere((i) => i.id == queued1!.id);
      final singleOk = await queueVm.syncSingleOfflineQueueItem(firstItem);
      expect(singleOk, isTrue);
      expect(queueVm.state.isProcessing, isFalse);
      expect(scriptedGemini.extractCalls, 2);
      expect(queueVm.state.completedScanArchive.length, 1);
      expect(queueVm.state.pendingOfflineQueue.length, 2);

      // 5. Manual Bulk Background Sync on remaining 2 items -> queued2 commits ('00202'), queued3 pauses as 'conflict' ('00201')
      final bulkCount = await queueVm.syncAllOfflineScans();
      expect(bulkCount, 1);
      expect(scriptedGemini.extractCalls, 6);
      expect(queueVm.state.isProcessing, isFalse);
      expect(queueVm.state.isQueueSyncing, isFalse);
      expect(queueVm.state.completedScanArchive.length, 2);
      expect(queueVm.state.pendingOfflineQueue.length, 1);
      expect(queueVm.state.pendingOfflineQueue.single.isConflict, isTrue);
      expect((await patientRepo.getPatientsByCamp('camp-ktm-01')).length, 2);
    });
  });
}

class _ScriptedQueueGeminiService extends GeminiOcrService {
  final List<String> tokensByForm;
  int extractCalls = 0;

  _ScriptedQueueGeminiService(this.tokensByForm);

  @override
  Future<OcrScanResultModel> extractFromBytes(
    Uint8List rawBytes, {
    String imagePath = '',
    int pageNumber = 0,
  }) async {
    // Each dual-page form extracts Page 1 then Page 2 (2 calls per form)
    final formIdx = (extractCalls ~/ 2).clamp(0, tokensByForm.length - 1);
    extractCalls++;
    final token = tokensByForm[formIdx];
    if (pageNumber == 2) {
      return OcrScanResultModel(
        pageNumber: 2,
        rawText: 'Page 2',
        demographics: const {},
        obstetrics: const {},
        popStaging: const {'anteriorStage': 1, 'middleStage': 0, 'posteriorStage': 0, 'highestPopStage': 1},
        vitals: const {'systolicBp': 118, 'diastolicBp': 76},
        diagnoses: const ['UTI'],
        medications: const ['Ciprofloxacin'],
        fieldConfidences: const {'popStaging': 0.94},
        overallConfidence: 0.94,
        scannedAt: DateTime(2026, 11, 26),
      );
    }
    return OcrScanResultModel(
      pageNumber: 1,
      rawText: 'Page 1',
      demographics: {
        'patientId': token,
        'firstName': 'Patient$formIdx',
        'surname': 'Test',
        'age': 35 + formIdx,
        'ward': '04',
        'intakeDate': '2083-08-09',
      },
      obstetrics: const {'deliveries': 2, 'livingChildren': 2, 'abortions': 0},
      popStaging: const {},
      vitals: const {},
      diagnoses: const [],
      medications: const [],
      fieldConfidences: const {'firstName': 0.95},
      overallConfidence: 0.95,
      intakeDate: '2083-08-09',
      scannedAt: DateTime(2026, 11, 26),
    );
  }
}
