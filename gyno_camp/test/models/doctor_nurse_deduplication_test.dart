import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/core/services/duplicate_detection_service.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/camp_report_summary_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/models/user_model.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/auth_repository.dart';
import 'package:gyno_camp/repositories/camp_repository.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';
import 'package:gyno_camp/repositories/reporting_repository.dart';
import 'package:gyno_camp/viewmodels/auth_viewmodel.dart';
import 'package:gyno_camp/viewmodels/camp_viewmodel.dart';
import 'package:gyno_camp/viewmodels/device_security_viewmodel.dart';
import 'package:gyno_camp/viewmodels/patient_list_viewmodel.dart';
import 'package:gyno_camp/viewmodels/patient_registration_viewmodel.dart';
import 'package:gyno_camp/viewmodels/reporting_viewmodel.dart';
import 'package:gyno_camp/viewmodels/sync_viewmodel.dart';
import 'package:gyno_camp/views/reports/camp_report_view.dart';

class _FakeSyncVm extends StateNotifier<SyncState> implements SyncViewModel {
  _FakeSyncVm() : super(const SyncState(isOnline: false));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDeviceSecVm extends StateNotifier<DeviceSecurityState>
    implements DeviceSecurityViewModel {
  _FakeDeviceSecVm()
      : super(const DeviceSecurityState(
          hardwareFingerprint: 'fp',
          isInitialized: true,
          isChecking: false,
          isAppLocked: false,
        ));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthRepo implements IAuthRepository {
  final UserModel user;
  _FakeAuthRepo(this.user);

  @override
  UserModel? get currentUser => user;

  @override
  void setCurrentUser(UserModel? u) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCampRepo implements ICampRepository {
  final List<CampModel> camps;
  _FakeCampRepo(this.camps);

  @override
  Future<List<CampModel>> getAllCamps({String? tenantId}) async => camps;

  @override
  Future<CampModel?> getActiveCamp() async => camps.first;

  @override
  Future<CampModel?> getCampById(String id) async => camps.first;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePatientRepo implements IPatientRepository {
  final List<PatientModel> patients;
  _FakePatientRepo(this.patients);

  @override
  Future<List<PatientModel>> getPatientsByCamp([
    String? campId,
    List<String>? allowedCampIds,
  ]) async =>
      patients;

  @override
  Future<DuplicateCheckResult> checkDuplicate({
    required String campId,
    required String firstName,
    required String surname,
    required int age,
    required String mobile,
    required String ward,
    String? spouseOrFatherName,
    String? maritalStatus,
  }) async =>
      const DuplicateCheckResult.none();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeReportingRepo implements IReportingRepository {
  final CampReportSummaryModel summary;
  _FakeReportingRepo(this.summary);

  @override
  Future<CampReportSummaryModel> getCampSummary({
    String? campId,
    List<String>? allowedCampIds,
    String generatedBy = 'Data Analyst',
    DateTime? startDate,
    DateTime? endDate,
    String? doctorFilter,
    String? nurseFilter,
    String? diagnosisFilter,
    String? popStageFilter,
    String? treatmentFilter,
    String? complaintFilter,
    String? visitReasonFilter,
    String? treatmentLevelFilter,
  }) async =>
      summary;

  @override
  Future<Uint8List> generatePdfReport(CampReportSummaryModel summary) async => Uint8List(0);

  @override
  Future<Uint8List> generateIndividualPatientPdf({
    required PatientModel patient,
    ClinicalVisitModel? visit,
    List<ClinicalVisitModel>? allVisits,
    CampModel? camp,
    String organizationName = 'Org',
  }) async =>
      Uint8List(0);

  @override
  Future<List<int>> generateExcelReport(CampReportSummaryModel summary) async => const [];

  @override
  Future<String> saveReportToFile({
    required List<int> bytes,
    required String filename,
    String? targetDirectoryPath,
  }) async =>
      filename;

  @override
  Future<void> auditReportExport({
    required String userId,
    required String userName,
    required String userRole,
    required String deviceId,
    required String format,
    required String campCode,
    required int totalPatients,
    required String filePath,
  }) async {}
}

PatientModel _makePatient({
  required String id,
  required String patientId,
  required String firstName,
  required String primaryDoctorName,
}) {
  return PatientModel(
    id: id,
    patientId: patientId,
    campId: 'camp-2222',
    campCode: '2222',
    intakeDate: DateTime(2026, 11, 19),
    firstName: firstName,
    surname: 'Thapa',
    age: 32,
    mobile: '9841000001',
    ward: '05',
    district: 'Dhading',
    municipality: 'Nilkantha',
    reasonsForVisit: const ['checkup'],
    createdAt: DateTime(2026, 11, 19),
    createdByUserId: 'u-admin',
    createdByDeviceId: 'dev-1',
    primaryDoctorName: primaryDoctorName,
    attendingDoctorNames: [primaryDoctorName],
  );
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('DoctorProfile & NurseProfile Canonical Normalization', () {
    test('treats Dr. A Sharma, Dr. A. Sharma, Dr. A.Sharma and NMC variants as equal', () {
      final p1 = DoctorProfile.parse('Dr. A Sharma');
      final p2 = DoctorProfile.parse('Dr. A. Sharma');
      final p3 = DoctorProfile.parse('dr.  A.Sharma');
      final p4 = DoctorProfile.parse('Dr. A. Sharma (NMC: 2222/3333)');

      expect(p1.canonicalNameKey, 'a sharma');
      expect(p2.canonicalNameKey, 'a sharma');
      expect(p3.canonicalNameKey, 'a sharma');
      expect(p4.canonicalNameKey, 'a sharma');
      expect(p4.nmcNumber, '2222/3333');

      expect(p1 == p2, isTrue);
      expect(p1.hashCode, p2.hashCode);
      expect(DoctorProfile.namesMatch('Dr. A Sharma', 'Dr. A. Sharma'), isTrue);
      expect(DoctorProfile.namesMatch('Dr. A Sharma', 'Dr. A. Sharma (NMC: 2222/3333)'), isTrue);
      expect(DoctorProfile.namesMatch('Dr. A. Sharma', 'Dr. R. Joshi'), isFalse);

      // pickPreferred favors dotted initials and NMC-bearing entries
      expect(DoctorProfile.pickPreferred(p1, p2).displayName, 'Dr. A. Sharma');
      expect(DoctorProfile.pickPreferred(p2, p4).formattedLabel, 'Dr. A. Sharma (NMC: 2222/3333)');
    });

    test('treats Nurse S Shrestha and S. Shrestha as equal', () {
      final n1 = NurseProfile.parse('Nurse S Shrestha');
      final n2 = NurseProfile.parse('S. Shrestha');

      expect(n1.canonicalNameKey, 's shrestha');
      expect(n2.canonicalNameKey, 's shrestha');
      expect(n1 == n2, isTrue);
      expect(NurseProfile.namesMatch('Nurse S Shrestha', 'S. Shrestha'), isTrue);
      expect(NurseProfile.pickPreferred(n1, n2).displayName, 'S. Shrestha');
    });

    test('PatientListViewModel doctor filter matches both Dr. A Sharma and Dr. A. Sharma', () async {
      final p1 = _makePatient(
        id: 'p1',
        patientId: 'GC-2222-2026-00001',
        firstName: 'Sita',
        primaryDoctorName: 'Dr. A Sharma',
      );
      final p2 = _makePatient(
        id: 'p2',
        patientId: 'GC-2222-2026-00002',
        firstName: 'Gita',
        primaryDoctorName: 'Dr. A. Sharma',
      );
      final p3 = _makePatient(
        id: 'p3',
        patientId: 'GC-2222-2026-00003',
        firstName: 'Mina',
        primaryDoctorName: 'Dr. R. Joshi',
      );

      final vm = PatientListViewModel(_FakePatientRepo([p1, p2, p3]));
      await vm.loadPatients('camp-2222');
      vm.updateFilters(const PatientFilterCriteria(
        campId: 'camp-2222',
        doctor: 'Dr. A. Sharma',
      ));

      expect(vm.state.patients.length, 2);
      expect(vm.state.patients.map((p) => p.id), containsAll(['p1', 'p2']));
    });

    test('ReportingRepository doctorFilter matches both Dr. A Sharma and Dr. A. Sharma', () async {
      final testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      final dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      addTearDown(() => testDb.close());

      final auditRepo = AuditRepository(databaseService: dbService);
      final patientRepo = PatientRepository(
        databaseService: dbService,
        auditRepository: auditRepo,
        enableCentralSync: false,
      );
      final reportingRepo = ReportingRepository(
        databaseService: dbService,
        auditRepository: auditRepo,
      );

      final reg1 = await patientRepo.registerPatient(
        _makePatient(
          id: 'p1',
          patientId: 'GC-2222-2026-00001',
          firstName: 'Sita',
          primaryDoctorName: 'Dr. A Sharma',
        ),
        createdByUserId: 'u-1',
        createdByUserName: 'Nurse',
        createdByUserRole: 'DATA_TAKER',
        deviceId: 'dev-1',
      );
      final reg2 = await patientRepo.registerPatient(
        _makePatient(
          id: 'p2',
          patientId: 'GC-2222-2026-00002',
          firstName: 'Gita',
          primaryDoctorName: 'Dr. A. Sharma',
        ),
        createdByUserId: 'u-1',
        createdByUserName: 'Nurse',
        createdByUserRole: 'DATA_TAKER',
        deviceId: 'dev-1',
      );

      await patientRepo.saveClinicalVisit(
        ClinicalVisitModel(
          id: 'v1',
          patientId: reg1.patientId,
          campId: 'camp-2222',
          visitDate: DateTime(2026, 11, 19),
          createdAt: DateTime(2026, 11, 19),
          createdByUserId: 'u-1',
          primaryDoctorName: 'Dr. A Sharma',
          attendingDoctorNames: const ['Dr. A Sharma'],
        ),
        createdByUserId: 'u-1',
        deviceId: 'dev-1',
      );
      await patientRepo.saveClinicalVisit(
        ClinicalVisitModel(
          id: 'v2',
          patientId: reg2.patientId,
          campId: 'camp-2222',
          visitDate: DateTime(2026, 11, 19),
          createdAt: DateTime(2026, 11, 19),
          createdByUserId: 'u-1',
          primaryDoctorName: 'Dr. A. Sharma',
          attendingDoctorNames: const ['Dr. A. Sharma'],
        ),
        createdByUserId: 'u-1',
        deviceId: 'dev-1',
      );

      final summary = await reportingRepo.getCampSummary(
        campId: 'camp-2222',
        doctorFilter: 'Dr. A. Sharma',
      );
      expect(summary.totalPatientsRegistered, 2);
      expect(summary.totalVisitsRecorded, 2);
    });

    testWidgets(
      'CampReportView merges Dr. A Sharma and Dr. A. Sharma into a single Doctor Filter dropdown item with count 2',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final camp = CampModel(
          id: 'camp-2222',
          campCode: '2222',
          name: 'Women for Women Sodesi',
          district: 'Bhojpur',
          municipality: 'Aamchok',
          ward: '5',
          venue: 'Chitwan Medical College',
          startDate: DateTime(2026, 11, 17),
          endDate: DateTime(2026, 12, 14),
          status: CampStatus.open,
          createdAt: DateTime(2026, 11, 17),
        );

        final p1 = _makePatient(
          id: 'p1',
          patientId: 'GC-2222-2026-00001',
          firstName: 'Sita',
          primaryDoctorName: 'Dr. A Sharma',
        );
        final p2 = _makePatient(
          id: 'p2',
          patientId: 'GC-2222-2026-00002',
          firstName: 'Gita',
          primaryDoctorName: 'Dr. A. Sharma',
        );
        final v1 = ClinicalVisitModel(
          id: 'v1',
          patientId: p1.patientId,
          campId: 'camp-2222',
          visitDate: DateTime(2026, 11, 19),
          createdAt: DateTime(2026, 11, 19),
          createdByUserId: 'u-1',
          primaryDoctorName: 'Dr. A Sharma',
          attendingDoctorNames: const ['Dr. A Sharma'],
        );
        final v2 = ClinicalVisitModel(
          id: 'v2',
          patientId: p2.patientId,
          campId: 'camp-2222',
          visitDate: DateTime(2026, 11, 19),
          createdAt: DateTime(2026, 11, 19),
          createdByUserId: 'u-1',
          primaryDoctorName: 'Dr. A. Sharma',
          attendingDoctorNames: const ['Dr. A. Sharma'],
        );

        final summary = CampReportSummaryModel(
          campId: 'camp-2222',
          campCode: '2222',
          campName: 'Women for Women Sodesi',
          district: 'Bhojpur',
          municipality: 'Aamchok',
          venue: 'Chitwan Medical College',
          startDate: DateTime(2026, 11, 17),
          endDate: DateTime(2026, 12, 14),
          generatedAt: DateTime.now(),
          generatedBy: 'Admin',
          totalPatientsRegistered: 2,
          totalVisitsRecorded: 2,
          ageGroups: const {'20-35': 2},
          maritalStatusCounts: const {},
          wardCounts: const {},
          anteriorStages: const {},
          middleStages: const {},
          posteriorStages: const {},
          highestPopStages: const {},
          significantPopCount: 0,
          significantPopPercentage: 0.0,
          diagnosisCounts: const {},
          hypertensionCount: 0,
          hyperglycemiaCount: 0,
          urinePositiveCount: 0,
          pregnancyPositiveCount: 0,
          pessaryCounts: const {},
          totalPessariesInserted: 0,
          pelvicFloorCounselingCount: 0,
          surgicalReferralCounts: const {},
          totalSurgicalReferrals: 0,
          followUpDestinationCounts: const {},
          medicationDispensedCounts: const {},
          totalPrescriptionsCount: 0,
          patients: [p1, p2],
          visits: [v1, v2],
        );

        const admin = UserModel(
          id: 'u-admin',
          name: 'Admin',
          email: 'admin@gynocamp.org',
          phone: '9800000000',
          role: UserRole.superAdmin,
          isActive: true,
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              campRepositoryProvider.overrideWithValue(_FakeCampRepo([camp])),
              patientRepositoryProvider.overrideWithValue(_FakePatientRepo([p1, p2])),
              reportingRepositoryProvider.overrideWithValue(_FakeReportingRepo(summary)),
              syncStateProvider.overrideWith((ref) => _FakeSyncVm()),
              deviceSecurityProvider.overrideWith((ref) => _FakeDeviceSecVm()),
              authStateProvider.overrideWith((ref) => AuthViewModel(_FakeAuthRepo(admin))),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const CampReportView(initialCampId: 'camp-2222'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Open the Doctor Filter dropdown
        await tester.tap(find.text('All Doctors'));
        await tester.pumpAndSettle();

        // Only ONE merged "Dr. A. Sharma" entry should appear — never a duplicate "Dr. A Sharma"
        expect(find.text('Dr. A. Sharma'), findsOneWidget);
        expect(find.text('Dr. A Sharma'), findsNothing);
      },
    );
  });
}
