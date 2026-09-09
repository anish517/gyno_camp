import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/constants/app_constants.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/core/database/database_tables.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('PatientRepository SQLite Tests', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late PatientRepository patientRepo;

    setUp(() async {
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      auditRepo = AuditRepository(databaseService: dbService);
      patientRepo = PatientRepository(databaseService: dbService, auditRepository: auditRepo);
    });

    tearDown(() async {
      await testDb.close();
    });

    test('registerPatient generates sequential Patient IDs and audits creation', () async {
      final p1 = PatientModel(
        id: '',
        patientId: '',
        campId: 'camp-ktm-01',
        campCode: 'KTM',
        intakeDate: DateTime(2026, 3, 15),
        firstName: 'Sunita',
        surname: 'Shrestha',
        age: 28,
        spouseOrFatherName: 'Bikash Shrestha',
        relationshipType: 'Husband',
        mobile: '9841112233',
        ward: '04',
        createdAt: DateTime.now(),
        createdByUserId: 'usr-nurse-1',
        createdByDeviceId: 'dev-field-1',
      );

      final registered1 = await patientRepo.registerPatient(
        p1,
        createdByUserId: 'usr-nurse-1',
        createdByUserName: 'Test Nurse',
        createdByUserRole: 'DATA_TAKER',
        deviceId: 'dev-field-1',
      );

      expect(registered1.patientId, 'GC-KTM-2026-00001');
      expect(registered1.fullName, 'Sunita Shrestha');

      // Second patient in same camp gets next sequence number
      final p2 = p1.copyWith(
        firstName: 'Anita',
        surname: 'Rai',
        mobile: '9849998877',
      );

      final registered2 = await patientRepo.registerPatient(
        p2,
        createdByUserId: 'usr-nurse-1',
        createdByUserName: 'Test Nurse',
        createdByUserRole: 'DATA_TAKER',
        deviceId: 'dev-field-1',
      );

      expect(registered2.patientId, 'GC-KTM-2026-00002');

      // Verify camp total patients updated
      final campRows = await testDb.query(
        DatabaseTables.tableCamps,
        where: 'id = ?',
        whereArgs: ['camp-ktm-01'],
      );
      expect(campRows.first['total_patients_registered'], 2);

      // Verify audit logs exist
      final logs = await auditRepo.getRecentLogs();
      expect(logs.any((l) => l.action == AppConstants.auditActionPatientRegister), isTrue);
    });

    test('getPatientsByCamp and searchPatients retrieve matching records', () async {
      final p = PatientModel(
        id: 'pat-search-1',
        patientId: 'GC-KTM-2026-00005',
        campId: 'camp-ktm-01',
        campCode: 'KTM',
        intakeDate: DateTime(2026, 3, 15),
        firstName: 'Maya',
        surname: 'Gurung',
        age: 35,
        mobile: '9801234567',
        ward: '02',
        createdAt: DateTime.now(),
        createdByUserId: 'usr-1',
        createdByDeviceId: 'dev-1',
      );

      await patientRepo.registerPatient(p, createdByUserId: 'usr-1', createdByUserName: 'Test Nurse', createdByUserRole: 'DATA_TAKER', deviceId: 'dev-1');

      final list = await patientRepo.getPatientsByCamp('camp-ktm-01');
      expect(list.length, 1);
      expect(list.first.firstName, 'Maya');

      // Search by name
      final searchByName = await patientRepo.searchPatients(campId: 'camp-ktm-01', query: 'gurung');
      expect(searchByName.length, 1);

      // Search by phone
      final searchByPhone = await patientRepo.searchPatients(campId: 'camp-ktm-01', query: '980123');
      expect(searchByPhone.length, 1);

      // Search by patient ID
      final searchById = await patientRepo.searchPatients(campId: 'camp-ktm-01', query: '00005');
      expect(searchById.length, 1);

      // Search non-existent
      final emptyResult = await patientRepo.searchPatients(campId: 'camp-ktm-01', query: 'NonExistent');
      expect(emptyResult, isEmpty);
    });

    test('checkDuplicate detects existing patient in SQLite store', () async {
      final p = PatientModel(
        id: 'pat-dup-1',
        patientId: 'GC-KTM-2026-00001',
        campId: 'camp-ktm-01',
        campCode: 'KTM',
        intakeDate: DateTime(2026, 3, 15),
        firstName: 'Laxmi',
        surname: 'Bhandari',
        age: 40,
        mobile: '9841000000',
        ward: '07',
        spouseOrFatherName: 'Hari Bhandari',
        relationshipType: 'Husband',
        createdAt: DateTime.now(),
        createdByUserId: 'usr-1',
        createdByDeviceId: 'dev-1',
      );

      await patientRepo.registerPatient(p, createdByUserId: 'usr-1', createdByUserName: 'Test Nurse', createdByUserRole: 'DATA_TAKER', deviceId: 'dev-1');

      // Check with same phone
      final dupPhone = await patientRepo.checkDuplicate(
        campId: 'camp-ktm-01',
        firstName: 'Other',
        surname: 'Name',
        age: 25,
        mobile: '9841000000',
        ward: '01',
      );
      expect(dupPhone.isDuplicate, isTrue);

      // Check with same name + age + ward
      final dupDemographic = await patientRepo.checkDuplicate(
        campId: 'camp-ktm-01',
        firstName: 'laxmi',
        surname: 'bhandari',
        age: 41, // within +/- 1
        mobile: '',
        ward: '07',
        spouseOrFatherName: 'Hari Bhandari',
      );
      expect(dupDemographic.isDuplicate, isTrue);
    });

    test('saveClinicalVisit stores comprehensive Yellow Form data and calculates highest POP', () async {
      final visit = ClinicalVisitModel(
        id: '',
        patientId: 'GC-KTM-2026-00001',
        campId: 'camp-ktm-01',
        visitDate: DateTime(2026, 3, 15),
        deliveries: 4,
        livingChildren: 3,
        abortions: 1,
        anamnesisComplaints: const {
          'feeling of bulge': {'duration': '<1month'},
          'stress incontinence': {'duration': '>1year'},
        },
        uterusInside: false,
        pelvicFloorTone: 'moderate',
        popAnteriorStage: 2,
        popMiddleStage: 3,
        popPosteriorStage: 1,
        highestPopStage: 3,
        urineTest: 'normal',
        pregnancyTest: 'neg',
        systolicBp: 125,
        diastolicBp: 82,
        pulse: 74,
        spo2: 97,
        glucose: 110,
        diagnoses: ['POP', 'stress incontinence'],
        counseling: ['pelvic floor exercise'],
        pessaryType: 'ring',
        pessarySize: '65',
        surgicalReferral: 'Dhulikhel Hospital',
        medications: ['Iron with Folic Acid', 'Calcium'],
        followUpNeeded: true,
        followUpDestination: 'GynaeSupport Nurse',
        outtakeNotes: 'Pessary fitted successfully. Review in 3 months.',
        createdAt: DateTime.now(),
        createdByUserId: 'usr-doc-1',
      );

      final saved = await patientRepo.saveClinicalVisit(
        visit,
        createdByUserId: 'usr-doc-1',
        deviceId: 'dev-field-1',
      );

      expect(saved.id, isNotEmpty);
      expect(saved.highestPopStage, 3);

      // Verify stored in DB
      final visits = await patientRepo.getClinicalVisits('GC-KTM-2026-00001');
      expect(visits.length, 1);
      expect(visits.first.surgicalReferral, 'Dhulikhel Hospital');
      expect(visits.first.pessarySize, '65');
      expect(visits.first.diagnoses, contains('POP'));

      final latest = await patientRepo.getLatestClinicalVisit('GC-KTM-2026-00001');
      expect(latest?.pessaryType, 'ring');

      // Verify audit log
      final audit = await auditRepo.getRecentLogs();
      expect(audit.any((l) => l.action == AppConstants.auditActionClinicalEntry), isTrue);
    });
  });
}

