import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
import 'package:gyno_camp/core/services/duplicate_detection_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/camp_report_summary_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/models/user_model.dart';
import 'package:gyno_camp/repositories/camp_repository.dart';
import 'package:gyno_camp/repositories/auth_repository.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';
import 'package:gyno_camp/repositories/reporting_repository.dart';
import 'package:gyno_camp/viewmodels/auth_viewmodel.dart';
import 'package:gyno_camp/viewmodels/camp_viewmodel.dart';
import 'package:gyno_camp/viewmodels/patient_list_viewmodel.dart';
import 'package:gyno_camp/viewmodels/patient_registration_viewmodel.dart';
import 'package:gyno_camp/viewmodels/reporting_viewmodel.dart';
import 'package:gyno_camp/views/dashboard/home_gateway_view.dart';

class FakeCampRepoForResponsive implements ICampRepository {
  List<CampModel> testCamps = [
    CampModel(
      id: 'camp-1',
      campCode: 'KTM01',
      name: 'Outreach Gyno Health Camp',
      district: 'Kathmandu',
      municipality: 'Budhanilkantha',
      ward: '03',
      venue: 'Primary Health Care Center',
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 5),
      status: CampStatus.open,
      assignedStaffIds: const ['u-admin-1', 'u-taker-1', 'u-analyst-1'],
      createdAt: DateTime.now(),
      totalPatientsRegistered: 42,
    ),
  ];

  @override
  Future<List<CampModel>> getAllCamps({String? tenantId}) async => testCamps;

  @override
  Future<CampModel?> getActiveCamp() async => testCamps.first;

  @override
  Future<CampModel?> getCampById(String id) async => testCamps.first;

  @override
  Future<CampModel> createCamp(CampModel camp, {required String createdByUserId, required String deviceId}) async => camp;

  @override
  Future<CampModel> updateCamp(CampModel camp, {required String adminUserId, required String deviceId}) async => camp;

  @override
  Future<bool> deleteCamp(String campId, {required String adminUserId, required String deviceId}) async => true;

  @override
  Future<bool> archiveCamp(String campId, {required String adminUserId, required String deviceId}) async => true;

  @override
  Future<bool> assignStaff(String campId, List<String> staffIds, {required String adminUserId, required String deviceId}) async => true;

  @override
  Future<bool> openCamp(String campId, {required String adminUserId, required String deviceId}) async => true;

  @override
  Future<bool> closeCamp(String campId, {required String adminUserId, required String deviceId}) async => true;
}

class FakeAuthRepoForResponsive implements IAuthRepository {
  final UserModel? user;
  FakeAuthRepoForResponsive(this.user);

  @override
  UserModel? get currentUser => user;

  @override
  void setCurrentUser(UserModel? u) {}

  @override
  Future<UserModel?> login({required String email, String? password, required String deviceId}) async => user;

  @override
  Future<UserModel?> loginAsRole({required UserRole role, required String deviceId}) async => user;

  @override
  Future<void> logout({required String deviceId}) async {}

  @override
  Future<UserModel?> getUserByEmail(String email) async => user;

  @override
  Future<UserModel?> getUserById(String id) async => user;

  @override
  Future<List<UserModel>> getAllUsers({bool includeInactive = false}) async => user != null ? [user!] : [];

  @override
  Future<UserModel> createUser({required UserModel user, required String adminUserId, required String deviceId}) async => user;

  @override
  Future<UserModel> updateUser({required UserModel user, required String adminUserId, required String deviceId}) async => user;

  @override
  Future<void> deleteUser({required String userId, required String adminUserId, required String deviceId}) async {}

  @override
  Future<List<String>> getValidCampsForUser(List<String> assignedCampIds) async => assignedCampIds;
}

class FakePatientRepoForResponsive implements IPatientRepository {
  final List<PatientModel> patients;
  FakePatientRepoForResponsive(this.patients);

  @override
  Future<PatientModel> registerPatient(PatientModel patient, {required String createdByUserId, required String createdByUserName, required String createdByUserRole, required String deviceId}) async => patient;

  @override
  Future<PatientModel> updatePatient(PatientModel patient, {required String updatedByUserId, required String updatedByUserName, required String updatedByUserRole, required String deviceId}) async => patient;

  @override
  Future<List<PatientModel>> getPatientsByCamp([String? campId]) async => patients;

  @override
  Future<PatientModel?> getPatientByPatientId(String patientId) async =>
      patients.firstWhere((p) => p.patientId == patientId, orElse: () => patients.first);

  @override
  Future<List<PatientModel>> searchPatients({required String campId, required String query}) async => patients;

  @override
  Future<DuplicateCheckResult> checkDuplicate({required String campId, required String firstName, required String surname, required int age, required String mobile, required String ward, String? spouseOrFatherName, String? maritalStatus}) async => const DuplicateCheckResult.none();

  @override
  Future<ClinicalVisitModel> saveClinicalVisit(ClinicalVisitModel visit, {required String createdByUserId, required String deviceId}) async => visit;

  @override
  Future<List<ClinicalVisitModel>> getClinicalVisits(String patientId, {String? patientUuid}) async => [];

  @override
  Future<ClinicalVisitModel?> getLatestClinicalVisit(String patientId, {String? patientUuid}) async => null;
}

class FakeReportingRepoForResponsive implements IReportingRepository {
  final CampReportSummaryModel summary;
  FakeReportingRepoForResponsive(this.summary);

  @override
  Future<CampReportSummaryModel> getCampSummary({
    String? campId,
    String? doctorFilter,
    String generatedBy = 'Data Analyst',
    DateTime? startDate,
    DateTime? endDate,
  }) async => summary;

  @override
  Future<Uint8List> generatePdfReport(CampReportSummaryModel summary) async => Uint8List(0);

  @override
  Future<Uint8List> generateIndividualPatientPdf({
    required PatientModel patient,
    ClinicalVisitModel? visit,
    List<ClinicalVisitModel>? allVisits,
    CampModel? camp,
    String organizationName = 'Nepal Gyno Health Outreach Network',
  }) async => Uint8List(0);

  @override
  Future<List<int>> generateExcelReport(CampReportSummaryModel summary) async => [];

  @override
  Future<String> saveReportToFile({
    required List<int> bytes,
    required String filename,
    String? targetDirectoryPath,
  }) async => '/fake/$filename';

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

void main() {
  final adminUser = UserModel(
    id: 'u-admin-1',
    name: 'Dr. Aarav Sharma Very Long Administrative Name',
    email: 'admin@gynocamp.org',
    phone: '9841000000',
    role: UserRole.superAdmin,
    tenantId: 'tenant_bir',
    tenantName: 'Kathmandu Outreach Center of Excellence',
    isActive: true,
  );

  final dataTakerUser = UserModel(
    id: 'u-taker-1',
    name: 'Sita Kumari Chaudhary (Senior Field Nurse)',
    email: 'sita@gynocamp.org',
    phone: '9841234567',
    role: UserRole.dataTaker,
    tenantId: 'tenant_bir',
    tenantName: 'Community Health Outreach',
    assignedCampIds: const ['camp-1'],
    isActive: true,
  );

  final dataAnalystUser = UserModel(
    id: 'u-analyst-1',
    name: 'Radha Thapa Magar',
    email: 'analyst@gynocamp.org',
    phone: '9841111111',
    role: UserRole.dataAnalyst,
    tenantId: 'tenant_bir',
    tenantName: 'Kathmandu Outreach Center',
    assignedCampIds: const ['camp-1'],
    isActive: true,
  );

  final samplePatients = [
    PatientModel(
      id: 'p-1',
      patientId: 'GC-KTM-2026-0001',
      campId: 'camp-1',
      campCode: 'KTM01',
      intakeDate: DateTime.now(),
      firstName: 'Maya Devi',
      surname: 'Shrestha',
      age: 48,
      mobile: '9841000001',
      ward: '03',
      reasonsForVisit: const ['Pelvic organ prolapse symptom'],
      createdAt: DateTime.now(),
      createdByUserId: 'u-taker-1',
      createdByDeviceId: 'dev-1',
    ),
    PatientModel(
      id: 'p-2',
      patientId: 'GC-KTM-2026-0002',
      campId: 'camp-1',
      campCode: 'KTM01',
      intakeDate: DateTime.now(),
      firstName: 'Chandrakala',
      surname: 'Adhikari',
      age: 55,
      mobile: '9841000002',
      ward: '05',
      reasonsForVisit: const ['Lower abdominal pain'],
      createdAt: DateTime.now(),
      createdByUserId: 'u-taker-1',
      createdByDeviceId: 'dev-1',
    ),
  ];

  final mockSummary = CampReportSummaryModel(
    campId: 'camp-1',
    campCode: 'KTM01',
    campName: 'Outreach Gyno Health Camp',
    district: 'Kathmandu',
    municipality: 'Budhanilkantha',
    venue: 'Primary Health Care Center',
    startDate: DateTime(2026, 9, 1),
    endDate: DateTime(2026, 9, 5),
    generatedAt: DateTime.now(),
    generatedBy: 'Data Analyst',
    totalPatientsRegistered: 50,
    totalVisitsRecorded: 48,
    ageGroups: const {},
    maritalStatusCounts: const {},
    wardCounts: const {},
    anteriorStages: const {},
    middleStages: const {},
    posteriorStages: const {},
    highestPopStages: const {0: 10, 1: 15, 2: 15, 3: 5, 4: 3},
    significantPopCount: 23,
    significantPopPercentage: 47.9,
    diagnosisCounts: const {},
    hypertensionCount: 4,
    hyperglycemiaCount: 2,
    urinePositiveCount: 1,
    pregnancyPositiveCount: 0,
    pessaryCounts: const {},
    totalPessariesInserted: 8,
    pelvicFloorCounselingCount: 12,
    surgicalReferralCounts: const {},
    totalSurgicalReferrals: 5,
    followUpDestinationCounts: const {},
    medicationDispensedCounts: const {},
    totalPrescriptionsCount: 30,
    patients: samplePatients,
    visits: const [],
  );

  Widget createResponsiveApp({
    required UserModel user,
    List<PatientModel> patients = const [],
    CampReportSummaryModel? summary,
  }) {
    final fakeCampRepo = FakeCampRepoForResponsive();
    final fakePatientRepo = FakePatientRepoForResponsive(patients);
    final fakeReportingRepo = FakeReportingRepoForResponsive(summary ?? mockSummary);

    final activeCamp = fakeCampRepo.testCamps.first;
    return ProviderScope(
      overrides: [
        campRepositoryProvider.overrideWithValue(fakeCampRepo),
        authStateProvider.overrideWith((ref) {
          return AuthViewModel(FakeAuthRepoForResponsive(user));
        }),
        patientRepositoryProvider.overrideWithValue(fakePatientRepo),
        reportingRepositoryProvider.overrideWithValue(fakeReportingRepo),
        campStateProvider.overrideWith((ref) {
          final vm = CampViewModel(fakeCampRepo);
          vm.state = CampState(
            camps: fakeCampRepo.testCamps,
            activeCamp: activeCamp,
            selectedCamp: activeCamp,
          );
          return vm;
        }),
        patientListProvider.overrideWith((ref) {
          final vm = PatientListViewModel(fakePatientRepo);
          vm.state = PatientListState(
            patients: patients,
            hasLoaded: true,
            loadedCampId: activeCamp.id,
          );
          return vm;
        }),
        reportingViewModelProvider.overrideWith((ref) {
          final vm = ReportingViewModel(reportingRepository: fakeReportingRepo);
          vm.state = ReportingState(summary: summary ?? mockSummary);
          return vm;
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const HomeGatewayView(),
      ),
    );
  }

  group('Super Admin Dashboard Responsiveness', () {
    testWidgets('renders cleanly on mobile viewport (360x640) with zero RenderFlex overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createResponsiveApp(user: adminUser));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('SECURE ROOT SESSION ACTIVE'), findsOneWidget);
      expect(find.text('Super Admin Command Console'), findsOneWidget);
      expect(find.text('New Camp'), findsOneWidget);
      expect(find.text('Switch Camp'), findsWidgets);
      expect(find.text('Disaster Recovery & Data Export Operations'), findsOneWidget);
      expect(find.text('Export Audit Log'), findsOneWidget);
      expect(find.text('Database Backup'), findsOneWidget);
      expect(find.text('Restore Database'), findsOneWidget);
    });

    testWidgets('renders cleanly on desktop viewport (1280x1000)', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createResponsiveApp(user: adminUser));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Super Admin Command Console • Field Operations & Clinical Governance'), findsOneWidget);
      expect(find.text('New Camp'), findsOneWidget);
      expect(find.text('Switch Camp'), findsWidgets);
    });
  });

  group('Data Taker Dashboard Responsiveness', () {
    testWidgets('renders cleanly on mobile viewport (360x640) with stacked station tiles and zero overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      FlutterError.onError = FlutterError.presentError;
      await tester.pumpWidget(createResponsiveApp(user: dataTakerUser, patients: samplePatients));
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pumpAndSettle();

      final dataTakerErr = tester.takeException();
      if (dataTakerErr != null) {
        if (dataTakerErr is FlutterError) {
          // ignore: avoid_print
          print('DATA_TAKER_MOBILE_ERROR_DEEP: ${dataTakerErr.toStringDeep()}');
        } else {
          // ignore: avoid_print
          print('DATA_TAKER_MOBILE_ERROR: $dataTakerErr');
        }
      }
      expect(dataTakerErr, isNull);
      expect(find.text('LIVE FIELD STATION ACTIVE'), findsOneWidget);
      expect(find.text('Register Patient (दर्ता)'), findsOneWidget);
      expect(find.text('Scan Yellow Form (स्क्यान)'), findsOneWidget);
      expect(find.text('Patient Roll & Triage (सूची)'), findsOneWidget);
      expect(find.text('Offline Sync Hub (सिंक)'), findsOneWidget);
      expect(find.text('Recent Station Intakes'), findsOneWidget);
      expect(find.text('Camp Clinical Summary & Lead Handover'), findsOneWidget);
      expect(find.text('Camp Summary'), findsOneWidget);
    });

    testWidgets('renders cleanly on desktop viewport (1280x1000)', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createResponsiveApp(user: dataTakerUser, patients: samplePatients));
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Register Patient (दर्ता)'), findsOneWidget);
      expect(find.text('Scan Yellow Form (स्क्यान)'), findsOneWidget);
      expect(find.text('Camp Summary'), findsOneWidget);
    });
  });

  group('Data Analyst Workstation Responsiveness', () {
    testWidgets('renders POP-Q 2x2 grid and patient registry list cleanly on mobile (360x640)', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createResponsiveApp(
        user: dataAnalystUser,
        patients: samplePatients,
        summary: mockSummary,
      ));
      await tester.pumpAndSettle();

      final analystErr = tester.takeException();
      if (analystErr != null) {
        // ignore: avoid_print
        print('DATA_ANALYST_MOBILE_ERROR: $analystErr');
      }
      expect(analystErr, isNull);
      expect(find.text('CLINICAL DATA ANALYST WORKSTATION'), findsOneWidget);
      expect(find.text('Stage 0 (Normal)'), findsOneWidget);
      expect(find.text('Stage I (Mild)'), findsOneWidget);
      expect(find.text('Stage II (Moderate)'), findsOneWidget);
      expect(find.text('Stage III-IV (Severe)'), findsOneWidget);
      await tester.tap(find.textContaining('Camp-Wise Patients'));
      await tester.pumpAndSettle();
      expect(find.text('Maya Devi Shrestha'), findsOneWidget);
      expect(find.text('PDF Dossier'), findsWidgets);
    });

    testWidgets('renders cleanly on desktop viewport (1280x1000)', (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(createResponsiveApp(
        user: dataAnalystUser,
        patients: samplePatients,
        summary: mockSummary,
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('CLINICAL DATA ANALYST WORKSTATION'), findsOneWidget);
      expect(find.text('Stage 0 (Normal)'), findsOneWidget);
    });
  });
}
