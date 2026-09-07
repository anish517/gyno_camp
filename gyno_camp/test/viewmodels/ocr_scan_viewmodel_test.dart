import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/core/services/ocr_form_service.dart';
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
  });
}
