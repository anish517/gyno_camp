import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/constants/app_constants.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/core/database/database_tables.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';
import 'package:gyno_camp/viewmodels/patient_registration_viewmodel.dart';

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

      expect(registered1.patientId, '00001');
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

      expect(registered2.patientId, '00002');

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

      // Verify allowedCampIds filtering
      final scopedList = await patientRepo.getPatientsByCamp('all', ['camp-ktm-01']);
      expect(scopedList.length, 1);
      final unallowedList = await patientRepo.getPatientsByCamp('all', ['other-camp']);
      expect(unallowedList, isEmpty);
      final emptyAllowedList = await patientRepo.getPatientsByCamp('all', []);
      expect(emptyAllowedList, isEmpty);
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

    test('PatientRegistrationViewModel.submitUpdate updates edited patientId and cascades to clinical_visits', () async {
      final initialPatient = await patientRepo.registerPatient(
        PatientModel(
          id: 'pat-edit-token-1',
          patientId: 'GC-0007-2026-00012',
          campId: 'camp-ktm-01',
          campCode: '0007',
          intakeDate: DateTime(2026, 7, 31),
          firstName: 'KAMALA',
          surname: 'SSSS',
          age: 50,
          mobile: '9841234567',
          ward: '05',
          reasonsForVisit: const ['checkup'],
          createdAt: DateTime.now(),
          createdByUserId: 'usr-1',
          createdByDeviceId: 'dev-1',
        ),
        createdByUserId: 'usr-1',
        createdByUserName: 'Staff',
        createdByUserRole: 'DATA_TAKER',
        deviceId: 'dev-1',
        pushToServer: false,
      );

      await patientRepo.saveClinicalVisit(
        ClinicalVisitModel(
          id: 'vis-edit-token-1',
          patientId: initialPatient.patientId,
          campId: 'camp-ktm-01',
          visitDate: DateTime(2026, 7, 31),
          createdAt: DateTime.now(),
          createdByUserId: 'usr-1',
        ),
        createdByUserId: 'usr-1',
        deviceId: 'dev-1',
        pushToServer: false,
      );

      final vm = PatientRegistrationViewModel(patientRepo);
      vm.loadPatientForEditing(initialPatient);
      vm.updateField(patientId: 'GC-0007-2026-00099');

      final updated = await vm.submitUpdate(
        originalPatient: initialPatient,
        staffUserId: 'usr-1',
        staffUserName: 'Staff',
        staffUserRole: 'DATA_TAKER',
        deviceId: 'dev-1',
      );

      expect(updated, isNotNull);
      expect(updated!.id, 'pat-edit-token-1');
      expect(updated.patientId, 'GC-0007-2026-00099');

      final reloadedPatient = await patientRepo.getPatientByPatientId('GC-0007-2026-00099');
      expect(reloadedPatient, isNotNull);
      expect(reloadedPatient!.id, 'pat-edit-token-1');

      final visits = await patientRepo.getClinicalVisits('GC-0007-2026-00099');
      expect(visits.length, 1);
      expect(visits.first.patientId, 'GC-0007-2026-00099');
    });

    test('Global continuous 5-digit counter continues across camps while leaving historical GC-* patients untouched', () async {
      // Seed a second camp so cross-camp sequence continuation can be tested
      await testDb.insert(DatabaseTables.tableCamps, {
        'id': 'camp-gorkha-02',
        'camp_code': 'GRK02',
        'name': 'Gorkha Camp',
        'district': 'Gorkha',
        'municipality': 'Gorkha',
        'ward': '01',
        'venue': 'Health Post',
        'start_date': DateTime(2026, 4, 1).toIso8601String(),
        'end_date': DateTime(2026, 4, 3).toIso8601String(),
        'status': 'open',
        'created_at': DateTime.now().toIso8601String(),
      });

      // Historical patient with GC-* ID already in DB (must NOT be altered or shift 5-digit start)
      final historical = await patientRepo.registerPatient(
        PatientModel(
          id: 'pat-legacy-012',
          patientId: 'GC-0007-2026-00012',
          campId: 'camp-ktm-01',
          campCode: '0007',
          intakeDate: DateTime(2026, 2, 1),
          firstName: 'Legacy',
          surname: 'Patient',
          age: 50,
          mobile: '',
          ward: '02',
          createdAt: DateTime.now(),
          createdByUserId: 'usr-1',
          createdByDeviceId: 'dev-1',
        ),
        createdByUserId: 'usr-1',
        createdByUserName: 'Staff',
        createdByUserRole: 'DATA_TAKER',
        deviceId: 'dev-1',
        pushToServer: false,
      );
      expect(historical.patientId, 'GC-0007-2026-00012');

      // Camp 1 auto-generated patients: 00001, 00002
      final c1p1 = await patientRepo.registerPatient(
        PatientModel(
          id: '',
          patientId: '',
          campId: 'camp-ktm-01',
          campCode: 'KTM',
          intakeDate: DateTime(2026, 3, 15),
          firstName: 'Kamala',
          surname: 'Thapa',
          age: 41,
          mobile: '',
          ward: '03',
          createdAt: DateTime.now(),
          createdByUserId: 'usr-1',
          createdByDeviceId: 'dev-1',
        ),
        createdByUserId: 'usr-1',
        createdByUserName: 'Staff',
        createdByUserRole: 'DATA_TAKER',
        deviceId: 'dev-1',
        pushToServer: false,
      );
      final c1p2 = await patientRepo.registerPatient(
        c1p1.copyWith(id: '', patientId: '', firstName: 'Sita'),
        createdByUserId: 'usr-1',
        createdByUserName: 'Staff',
        createdByUserRole: 'DATA_TAKER',
        deviceId: 'dev-1',
        pushToServer: false,
      );
      expect(c1p1.patientId, '00001');
      expect(c1p2.patientId, '00002');

      // Camp 2 auto-generated patient continues at 00003 instead of resetting to 00001
      final c2p1 = await patientRepo.registerPatient(
        PatientModel(
          id: '',
          patientId: '',
          campId: 'camp-gorkha-02',
          campCode: 'GRK02',
          intakeDate: DateTime(2026, 4, 1),
          firstName: 'Mina',
          surname: 'Gurung',
          age: 37,
          mobile: '',
          ward: '05',
          createdAt: DateTime.now(),
          createdByUserId: 'usr-1',
          createdByDeviceId: 'dev-1',
        ),
        createdByUserId: 'usr-1',
        createdByUserName: 'Staff',
        createdByUserRole: 'DATA_TAKER',
        deviceId: 'dev-1',
        pushToServer: false,
      );
      expect(c2p1.patientId, '00003');
      expect(await patientRepo.getNextAvailableSequenceNumber(), 4);

      // Lookup by short number ('3') finds '00003', and historical 'GC-0007-2026-00012' stays intact
      final foundShort = await patientRepo.getPatientByPatientId('3');
      expect(foundShort?.id, c2p1.id);
      final foundLegacy = await patientRepo.getPatientByPatientId('GC-0007-2026-00012');
      expect(foundLegacy?.id, 'pat-legacy-012');
    });
  });
}

