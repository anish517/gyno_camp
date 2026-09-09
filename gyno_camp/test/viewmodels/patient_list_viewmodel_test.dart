import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';
import 'package:gyno_camp/viewmodels/patient_list_viewmodel.dart';

PatientModel _makePatient({
  String id = 'p1',
  String patientId = 'GC-KTM-2026-00001',
  String campId = 'camp-1',
  String firstName = 'Sita',
  String surname = 'Tamang',
  int age = 35,
  String mobile = '9841000001',
  String ward = '04',
}) {
  return PatientModel(
    id: id,
    patientId: patientId,
    campId: campId,
    campCode: 'KTM',
    intakeDate: DateTime(2026, 3, 15),
    firstName: firstName,
    surname: surname,
    age: age,
    mobile: mobile,
    ward: ward,
    district: 'Kathmandu',
    municipality: 'Budhanilkantha',
    reasonsForVisit: const ['something hanging out'],
    createdAt: DateTime.now(),
    createdByUserId: 'usr-test',
    createdByDeviceId: 'dev-test',
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('PatientListViewModel Tests', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late PatientRepository patientRepo;
    late PatientListViewModel vm;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      auditRepo = AuditRepository(databaseService: dbService);
      patientRepo = PatientRepository(databaseService: dbService, auditRepository: auditRepo);
      vm = PatientListViewModel(patientRepo);
    });

    tearDown(() async {
      await testDb.close();
    });

    test('Initial state is empty and not loaded', () {
      expect(vm.state.patients, isEmpty);
      expect(vm.state.isLoading, isFalse);
      expect(vm.state.hasLoaded, isFalse);
      expect(vm.state.errorMessage, isNull);
    });

    test('loadPatients sets isLoading to false and populates patients', () async {
      await patientRepo.registerPatient(
        _makePatient(),
        createdByUserId: 'usr-1',
        createdByUserName: 'Test Nurse',
        createdByUserRole: 'DATA_TAKER',
        deviceId: 'dev-1',
      );

      await vm.loadPatients('camp-1');

      expect(vm.state.isLoading, isFalse);
      expect(vm.state.hasLoaded, isTrue);
      expect(vm.state.patients.length, 1);
      expect(vm.state.patients.first.firstName, 'Sita');
      expect(vm.state.errorMessage, isNull);
    });

    test('loadPatients returns empty list for a camp with no patients', () async {
      await vm.loadPatients('camp-empty');
      expect(vm.state.isLoading, isFalse);
      expect(vm.state.hasLoaded, isTrue);
      expect(vm.state.patients, isEmpty);
    });

    test('hasClinicalVisit is false for newly registered patients with no visit saved', () async {
      await patientRepo.registerPatient(
        _makePatient(),
        createdByUserId: 'usr-1',
        createdByUserName: 'Test Nurse',
        createdByUserRole: 'DATA_TAKER',
        deviceId: 'dev-1',
      );

      await vm.loadPatients('camp-1');

      expect(vm.state.patients.first.hasClinicalVisit, isFalse);
    });

    test('hasClinicalVisit becomes true after a clinical visit is saved', () async {
      final registered = await patientRepo.registerPatient(
        _makePatient(),
        createdByUserId: 'usr-1',
        createdByUserName: 'Test Nurse',
        createdByUserRole: 'DATA_TAKER',
        deviceId: 'dev-1',
      );

      await patientRepo.saveClinicalVisit(
        ClinicalVisitModel(
          id: '',
          patientId: registered.patientId,
          campId: 'camp-1',
          visitDate: DateTime.now(),
          createdAt: DateTime.now(),
          createdByUserId: 'usr-1',
          isSynced: false,
        ),
        createdByUserId: 'usr-1',
        deviceId: 'dev-1',
      );

      await vm.loadPatients('camp-1');

      expect(vm.state.patients.first.hasClinicalVisit, isTrue);
    });

    test('search by name filters correctly', () async {
      await patientRepo.registerPatient(
        _makePatient(id: 'p1', patientId: 'GC-KTM-2026-00001', firstName: 'Sita', surname: 'Tamang'),
        createdByUserId: 'usr-1', createdByUserName: 'Test Nurse',
        createdByUserRole: 'DATA_TAKER', deviceId: 'dev-1',
      );
      await patientRepo.registerPatient(
        _makePatient(id: 'p2', patientId: 'GC-KTM-2026-00002', firstName: 'Anita', surname: 'Rai', mobile: '9841000002'),
        createdByUserId: 'usr-1', createdByUserName: 'Test Nurse',
        createdByUserRole: 'DATA_TAKER', deviceId: 'dev-1',
      );

      await vm.search('camp-1', 'tamang');

      expect(vm.state.patients.length, 1);
      expect(vm.state.patients.first.surname, 'Tamang');
    });

    test('search by phone number filters correctly', () async {
      await patientRepo.registerPatient(
        _makePatient(id: 'p1', patientId: 'GC-KTM-2026-00001', mobile: '9841111111'),
        createdByUserId: 'usr-1', createdByUserName: 'Test Nurse',
        createdByUserRole: 'DATA_TAKER', deviceId: 'dev-1',
      );
      await patientRepo.registerPatient(
        _makePatient(id: 'p2', patientId: 'GC-KTM-2026-00002', mobile: '9849999999', firstName: 'Anita', surname: 'Rai'),
        createdByUserId: 'usr-1', createdByUserName: 'Test Nurse',
        createdByUserRole: 'DATA_TAKER', deviceId: 'dev-1',
      );

      await vm.search('camp-1', '9849999999');

      expect(vm.state.patients.length, 1);
      expect(vm.state.patients.first.mobile, '9849999999');
    });

    test('search with empty string reloads full list', () async {
      await patientRepo.registerPatient(
        _makePatient(id: 'p1', patientId: 'GC-KTM-2026-00001'),
        createdByUserId: 'usr-1', createdByUserName: 'Test Nurse',
        createdByUserRole: 'DATA_TAKER', deviceId: 'dev-1',
      );
      await patientRepo.registerPatient(
        _makePatient(id: 'p2', patientId: 'GC-KTM-2026-00002', firstName: 'Anita', surname: 'Rai', mobile: '9841000002'),
        createdByUserId: 'usr-1', createdByUserName: 'Test Nurse',
        createdByUserRole: 'DATA_TAKER', deviceId: 'dev-1',
      );

      await vm.search('camp-1', 'sita');
      expect(vm.state.patients.length, 1);

      await vm.search('camp-1', '');
      expect(vm.state.patients.length, 2);
    });

    test('search with non-matching query returns empty list', () async {
      await patientRepo.registerPatient(
        _makePatient(),
        createdByUserId: 'usr-1', createdByUserName: 'Test Nurse',
        createdByUserRole: 'DATA_TAKER', deviceId: 'dev-1',
      );

      await vm.search('camp-1', 'NonExistentGhostPatient');

      expect(vm.state.patients, isEmpty);
      expect(vm.state.errorMessage, isNull);
    });

    test('loadPatients for different camp IDs are independent', () async {
      await patientRepo.registerPatient(
        _makePatient(id: 'p1', patientId: 'GC-KTM-2026-00001', campId: 'camp-A'),
        createdByUserId: 'usr-1', createdByUserName: 'N', createdByUserRole: 'DATA_TAKER', deviceId: 'dev-1',
      );
      await patientRepo.registerPatient(
        _makePatient(id: 'p2', patientId: 'GC-BKT-2026-00001', campId: 'camp-B', firstName: 'Laxmi', surname: 'Bhandari', mobile: '9841000002'),
        createdByUserId: 'usr-1', createdByUserName: 'N', createdByUserRole: 'DATA_TAKER', deviceId: 'dev-1',
      );

      await vm.loadPatients('camp-A');
      expect(vm.state.patients.length, 1);
      expect(vm.state.patients.first.campId, 'camp-A');

      await vm.loadPatients('camp-B');
      expect(vm.state.patients.length, 1);
      expect(vm.state.patients.first.campId, 'camp-B');
    });
  });
}
