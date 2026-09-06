import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';
import 'package:gyno_camp/viewmodels/clinical_assessment_viewmodel.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ClinicalAssessmentViewModel Tests', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late PatientRepository patientRepo;
    late ClinicalAssessmentViewModel vm;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      auditRepo = AuditRepository(databaseService: dbService);
      patientRepo = PatientRepository(databaseService: dbService, auditRepository: auditRepo);
      vm = ClinicalAssessmentViewModel(patientRepo);
    });

    tearDown(() async {
      await testDb.close();
    });

    test('Station navigation increments, decrements, and clamps bounds', () {
      expect(vm.state.currentStationIndex, 0);

      vm.nextStation();
      expect(vm.state.currentStationIndex, 1);

      vm.nextStation();
      expect(vm.state.currentStationIndex, 2);

      vm.previousStation();
      expect(vm.state.currentStationIndex, 1);

      vm.goToStation(5);
      expect(vm.state.currentStationIndex, 5);

      // Cannot exceed station 5
      vm.nextStation();
      expect(vm.state.currentStationIndex, 5);

      // Cannot go below station 0
      vm.goToStation(0);
      vm.previousStation();
      expect(vm.state.currentStationIndex, 0);
    });

    test('POP staging automatically computes highest POP stage from all 3 compartments', () {
      expect(vm.state.highestPopStage, 0);

      // Anterior = 2
      vm.setPhysicalExam(popAnterior: 2);
      expect(vm.state.highestPopStage, 2);

      // Middle = 3 -> highest should be 3
      vm.setPhysicalExam(popMiddle: 3);
      expect(vm.state.highestPopStage, 3);

      // Posterior = 1 -> highest remains 3
      vm.setPhysicalExam(popPosterior: 1);
      expect(vm.state.highestPopStage, 3);
    });

    test('Numeric vitals update triggers live validation for BP, Pulse, SpO2, and Glucose', () {
      // Normal BP
      vm.setVitals(systolic: 120, diastolic: 80);
      expect(vm.state.systolicValidation.isNormal, isTrue);
      expect(vm.state.diastolicValidation.isNormal, isTrue);

      // Hypertensive warning BP (> 160)
      vm.setVitals(systolic: 175);
      expect(vm.state.systolicValidation.isWarning, isTrue);

      // Low SpO2 Hypoxia warning
      vm.setVitals(spo2: 86);
      expect(vm.state.spo2Validation.isWarning, isTrue);

      // Blood Glucose high warning
      vm.setVitals(glucose: 260);
      expect(vm.state.glucoseValidation.isWarning, isTrue);

      // Bradycardia warning
      vm.setVitals(pulse: 42);
      expect(vm.state.pulseValidation.isWarning, isTrue);
    });

    test('Diagnosis and medication toggling updates selected sets', () {
      expect(vm.state.selectedDiagnoses, isEmpty);
      expect(vm.state.selectedMedications, isEmpty);

      vm.toggleDiagnosis('POP');
      vm.toggleDiagnosis('UTI');
      expect(vm.state.selectedDiagnoses, contains('POP'));
      expect(vm.state.selectedDiagnoses, contains('UTI'));
      expect(vm.state.selectedDiagnoses.length, 2);

      // Toggle off
      vm.toggleDiagnosis('UTI');
      expect(vm.state.selectedDiagnoses.length, 1);

      // Medications
      vm.toggleMedication('Metronidazole');
      vm.toggleMedication('Ciprofloxacin');
      expect(vm.state.selectedMedications, contains('Metronidazole'));
      expect(vm.state.selectedMedications.length, 2);
    });

    test('submitAssessment packages all stations and commits to database', () async {
      vm.setAnamnesis(
        deliveries: 3,
        livingChildren: 3,
        abortions: 0,
      );
      vm.setPhysicalExam(
        uterusInside: false,
        pelvicFloorTone: 'normal',
        popAnterior: 1,
        popMiddle: 2,
        popPosterior: 0,
      );
      vm.setVitals(
        systolic: 120,
        diastolic: 78,
        pulse: 76,
        spo2: 98,
        glucose: 105,
      );
      vm.toggleDiagnosis('POP');
      vm.setPessary(type: 'ring', size: '70');
      vm.setSurgicalReferral('Dhulikhel Hospital');
      vm.setOuttake(
        followUpNeeded: true,
        destination: 'Health Post',
        notes: 'Patient advised to return if discomfort occurs.',
      );

      final saved = await vm.submitAssessment(
        patientId: 'GC-KTM-2026-00001',
        campId: 'camp-ktm-01',
        staffUserId: 'usr-doc',
        deviceId: 'dev-1',
      );

      expect(saved, isNotNull);
      expect(saved!.highestPopStage, 2);
      expect(saved.surgicalReferral, 'Dhulikhel Hospital');
      expect(saved.pessarySize, '70');
      expect(vm.state.isSaving, isFalse);
    });
  });
}
