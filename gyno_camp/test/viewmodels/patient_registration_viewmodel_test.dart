import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';
import 'package:gyno_camp/viewmodels/patient_registration_viewmodel.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('PatientRegistrationViewModel Tests', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late PatientRepository patientRepo;
    late PatientRegistrationViewModel vm;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      auditRepo = AuditRepository(databaseService: dbService);
      patientRepo = PatientRepository(databaseService: dbService, auditRepository: auditRepo);
      vm = PatientRegistrationViewModel(patientRepo);
    });

    tearDown(() async {
      await testDb.close();
    });

    test('Initial state is invalid until required fields are provided', () {
      expect(vm.state.isValid, isFalse);
      expect(vm.state.isSubmitting, isFalse);
      expect(vm.state.duplicateResult.isDuplicate, isFalse);

      vm.updateField(
        firstName: 'Kamala',
        surname: 'Khadka',
        age: 38,
        ward: '02',
      );

      expect(vm.state.isValid, isTrue);
    });

    test('toggleReason adds and removes reason for visit items', () {
      expect(vm.state.selectedReasons, isEmpty);

      vm.toggleReason('Pelvic Organ Prolapse');
      expect(vm.state.selectedReasons, contains('Pelvic Organ Prolapse'));

      vm.toggleReason('Abnormal Bleeding');
      expect(vm.state.selectedReasons.length, 2);

      // Toggle off
      vm.toggleReason('Pelvic Organ Prolapse');
      expect(vm.state.selectedReasons.length, 1);
      expect(vm.state.selectedReasons, contains('Abnormal Bleeding'));
    });

    test('runLiveDuplicateCheck detects duplicates dynamically', () async {
      // Register existing patient in database first
      vm.updateField(
        firstName: 'Saraswati',
        surname: 'Poudel',
        age: 44,
        mobile: '9841888999',
        ward: '05',
      );
      await vm.submitRegistration(
        campId: 'camp-ktm-01',
        campCode: 'KTM',
        staffUserId: 'usr-1',
        staffUserName: 'Test Nurse',
        staffUserRole: 'DATA_TAKER',
        deviceId: 'dev-1',
      );

      // Now reset and check with matching phone
      vm.reset();
      vm.updateField(
        firstName: 'Different',
        surname: 'Person',
        age: 30,
        mobile: '9841888999',
      );

      await vm.runLiveDuplicateCheck('camp-ktm-01');
      expect(vm.state.duplicateResult.isDuplicate, isTrue);
      expect(vm.state.duplicateResult.reason?.toLowerCase(), contains('mobile number'));
    });

    test('submitRegistration successfully creates patient with auto-generated ID', () async {
      vm.updateField(
        firstName: 'Bina',
        surname: 'Basnet',
        age: 29,
        mobile: '9801122334',
        ward: '03',
        district: 'Kathmandu',
        municipality: 'Budhanilkantha',
        spouseOrFatherName: 'Nabin Basnet',
        relationshipType: 'Husband',
      );

      final registered = await vm.submitRegistration(
        campId: 'camp-ktm-01',
        campCode: 'KTM',
        staffUserId: 'usr-nurse',
        staffUserName: 'Test Nurse',
        staffUserRole: 'DATA_TAKER',
        deviceId: 'dev-tab-1',
      );

      expect(registered, isNotNull);
      expect(registered!.patientId, 'GC-KTM-2026-00001');
      expect(registered.fullName, 'Bina Basnet');
      expect(vm.state.registeredPatient?.patientId, 'GC-KTM-2026-00001');
      expect(vm.state.isSubmitting, isFalse);
    });

    test('Updating maritalStatus to unmarried auto-sets relationship to Father and clears maritalAge', () {
      vm.updateField(
        maritalStatus: 'married',
        maritalAge: 20,
        relationshipType: 'Husband',
      );
      expect(vm.state.maritalStatus, 'married');
      expect(vm.state.relationshipType, 'Husband');
      expect(vm.state.maritalAge, 20);

      // Switch to unmarried
      vm.updateField(maritalStatus: 'unmarried');
      expect(vm.state.maritalStatus, 'unmarried');
      expect(vm.state.relationshipType, 'Father');
      expect(vm.state.maritalAge, isNull);
    });

    test('reset preserves camp location parameters and clears patient details', () {
      vm.updateField(
        firstName: 'Sita',
        surname: 'Sharma',
        ward: '08',
        district: 'Dhading',
        municipality: 'Nilkantha',
      );
      expect(vm.state.firstName, 'Sita');

      vm.reset(ward: '04', district: 'Kaski', municipality: 'Pokhara');
      expect(vm.state.firstName, isEmpty);
      expect(vm.state.ward, '04');
      expect(vm.state.district, 'Kaski');
      expect(vm.state.municipality, 'Pokhara');
    });

    test('Strict field validation rejects invalid phone numbers and single-character guardian names', () {
      vm.updateField(
        firstName: 'Sita',
        surname: 'Poudel',
        age: 31,
        ward: '03',
        spouseOrFatherName: 'b', // Incomplete 1-char name
        mobile: '234', // Invalid 3-digit phone
      );

      // Should be invalid
      expect(vm.state.isValid, isFalse);
      expect(vm.state.validationError, contains('10 digits'));

      // Fix phone to valid 10-digit Nepali number
      vm.updateField(mobile: '9841234567');
      expect(vm.state.isValid, isFalse);
      expect(vm.state.validationError, contains('Guardian/Spouse name'));

      // Fix guardian name
      vm.updateField(spouseOrFatherName: 'Bishnu Poudel');
      expect(vm.state.isValid, isTrue);
      expect(vm.state.validationError, isNull);
    });
  });
}
