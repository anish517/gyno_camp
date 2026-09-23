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
import 'package:gyno_camp/repositories/auth_repository.dart';
import 'package:gyno_camp/repositories/camp_repository.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';
import 'package:gyno_camp/repositories/reporting_repository.dart';
import 'package:gyno_camp/viewmodels/auth_viewmodel.dart';
import 'package:gyno_camp/viewmodels/camp_viewmodel.dart';
import 'package:gyno_camp/viewmodels/patient_registration_viewmodel.dart';
import 'package:gyno_camp/viewmodels/reporting_viewmodel.dart';
import 'package:gyno_camp/views/reports/camp_report_view.dart';

class FakeCampRepoForReports implements ICampRepository {
  List<CampModel> testCamps = [
    CampModel(
      id: 'camp-ui-01',
      campCode: 'KTM01',
      name: 'Kathmandu Health Camp',
      district: 'Kathmandu',
      municipality: 'Budhanilkantha',
      ward: '03',
      venue: 'Health Post',
      startDate: DateTime(2026, 3, 1),
      endDate: DateTime(2026, 3, 5),
      status: CampStatus.open,
      assignedStaffIds: const ['u-analyst-1'],
      createdAt: DateTime.now(),
      totalPatientsRegistered: 42,
    ),
    CampModel(
      id: 'camp-ui-02',
      campCode: 'PKR01',
      name: 'Pokhara Outreach Camp',
      district: 'Kaski',
      municipality: 'Pokhara',
      ward: '05',
      venue: 'Community Center',
      startDate: DateTime(2026, 4, 1),
      endDate: DateTime(2026, 4, 5),
      status: CampStatus.open,
      assignedStaffIds: const ['u-analyst-1'],
      createdAt: DateTime.now(),
      totalPatientsRegistered: 28,
    ),
  ];

  @override
  Future<List<CampModel>> getAllCamps({String? tenantId}) async => testCamps;
  @override
  Future<CampModel?> getActiveCamp() async => testCamps.first;
  @override
  Future<CampModel?> getCampById(String id) async =>
      testCamps.firstWhere((c) => c.id == id, orElse: () => testCamps.first);
  @override
  Future<CampModel> createCamp(CampModel camp, {required String createdByUserId, required String deviceId}) async => camp;
  @override
  Future<CampModel> updateCamp(CampModel camp, {required String adminUserId, required String deviceId}) async => camp;
  @override
  Future<bool> deleteCamp(String campId, {required String adminUserId, required String deviceId}) async => true;
  @override
  Future<bool> archiveCamp(String campId, {required String adminUserId, required String deviceId}) async => true;
  @override
  Future<bool> openCamp(String campId, {required String adminUserId, required String deviceId}) async => true;
  @override
  Future<bool> closeCamp(String campId, {required String adminUserId, required String deviceId}) async => true;
  @override
  Future<bool> assignStaff(String campId, List<String> staffIds, {required String adminUserId, required String deviceId}) async => true;
}

class FakeAuthRepoForReports implements IAuthRepository {
  final UserModel? user;
  FakeAuthRepoForReports(this.user);

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

class FakePatientRepoForReports implements IPatientRepository {
  final List<PatientModel> patients;
  FakePatientRepoForReports(this.patients);

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
  Future<DuplicateCheckResult> checkDuplicate({required String campId, required String firstName, required String surname, required int age, required String mobile, required String ward, String? spouseOrFatherName, String? maritalStatus}) async =>
      const DuplicateCheckResult.none();
  @override
  Future<ClinicalVisitModel> saveClinicalVisit(ClinicalVisitModel visit, {required String createdByUserId, required String deviceId}) async => visit;
  @override
  Future<List<ClinicalVisitModel>> getClinicalVisits(String patientId, {String? patientUuid}) async => [];
  @override
  Future<ClinicalVisitModel?> getLatestClinicalVisit(String patientId, {String? patientUuid}) async => null;
}

class FakeReportingRepo implements IReportingRepository {
  CampReportSummaryModel summary;
  FakeReportingRepo(this.summary);

  @override
  Future<CampReportSummaryModel> getCampSummary({
    String? campId,
    String generatedBy = 'Data Analyst',
    DateTime? startDate,
    DateTime? endDate,
  }) async =>
      summary;

  @override
  Future<Uint8List> generatePdfReport(CampReportSummaryModel summary) async =>
      Uint8List.fromList([37, 80, 68, 70, 45]);

  @override
  Future<Uint8List> generateIndividualPatientPdf({
    required PatientModel patient,
    ClinicalVisitModel? visit,
    List<ClinicalVisitModel>? allVisits,
    CampModel? camp,
    String organizationName = 'Nepal Gyno Health Outreach Network',
  }) async =>
      Uint8List.fromList([37, 80, 68, 70, 45]);

  @override
  Future<List<int>> generateExcelReport(CampReportSummaryModel summary) async => [80, 75, 3, 4];

  @override
  Future<String> saveReportToFile({
    required List<int> bytes,
    required String filename,
    String? targetDirectoryPath,
  }) async => '/storage/emulated/0/Download/$filename';

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
  final analystUser = UserModel(
    id: 'u-analyst-1',
    name: 'Bishal Shrestha',
    email: 'analyst@gynocamp.org',
    phone: '9841111111',
    role: UserRole.dataAnalyst,
    tenantId: 'tenant_bir',
    tenantName: 'Kathmandu Outreach Center',
    assignedCampIds: const ['camp-ui-01', 'camp-ui-02'],
    isActive: true,
  );

  final samplePatients = [
    PatientModel(
      id: 'pat-1',
      patientId: 'GC-KTM-2026-0001',
      campId: 'camp-ui-01',
      campCode: 'KTM01',
      intakeDate: DateTime.now(),
      firstName: 'Maya Devi',
      surname: 'Shrestha',
      age: 48,
      mobile: '9841000001',
      ward: '03',
      reasonsForVisit: const ['Prolapse'],
      createdAt: DateTime.now(),
      createdByUserId: 'u-analyst-1',
      createdByDeviceId: 'dev-1',
    ),
    PatientModel(
      id: 'pat-2',
      patientId: 'GC-KTM-2026-0002',
      campId: 'camp-ui-01',
      campCode: 'KTM01',
      intakeDate: DateTime.now(),
      firstName: 'Chandrakala',
      surname: 'Adhikari',
      age: 55,
      mobile: '9841000002',
      ward: '05',
      reasonsForVisit: const ['Pelvic pain'],
      createdAt: DateTime.now(),
      createdByUserId: 'u-analyst-1',
      createdByDeviceId: 'dev-1',
    ),
  ];

  final mockSummary = CampReportSummaryModel(
    campId: 'camp-ui-01',
    campCode: 'KTM01',
    campName: 'Kathmandu Health Camp',
    district: 'Kathmandu',
    municipality: 'Budhanilkantha',
    venue: 'Health Post',
    startDate: DateTime(2026, 3, 1),
    endDate: DateTime(2026, 3, 5),
    generatedAt: DateTime.now(),
    generatedBy: 'Data Analyst',
    totalPatientsRegistered: 42,
    totalVisitsRecorded: 42,
    ageGroups: {'<20': 5, '20-35': 15, '36-50': 12, '51-65': 7, '>65': 3},
    maritalStatusCounts: {'married': 35, 'widow': 5, 'unmarried': 2},
    wardCounts: {'01': 20, '02': 22},
    anteriorStages: {0: 10, 1: 15, 2: 12, 3: 5},
    middleStages: {0: 15, 1: 12, 2: 10, 3: 4, 4: 1},
    posteriorStages: {0: 20, 1: 12, 2: 8, 3: 2},
    highestPopStages: {0: 8, 1: 14, 2: 12, 3: 6, 4: 2},
    significantPopCount: 20,
    significantPopPercentage: 47.6,
    diagnosisCounts: {'PID': 18, 'POP Stage 2': 12, 'Cervicitis': 8},
    hypertensionCount: 6,
    hyperglycemiaCount: 4,
    urinePositiveCount: 5,
    pregnancyPositiveCount: 2,
    pessaryCounts: {'Ring (65mm)': 8},
    totalPessariesInserted: 8,
    pelvicFloorCounselingCount: 25,
    surgicalReferralCounts: {'Scheer Memorial': 5, 'Model Hospital': 2},
    totalSurgicalReferrals: 7,
    followUpDestinationCounts: {'Health Post': 20},
    medicationDispensedCounts: {'Ciprofloxacin 500mg': 18, 'Metronidazole 400mg': 18},
    totalPrescriptionsCount: 36,
  );

  Widget buildTestApp() {
    final fakeReportingRepo = FakeReportingRepo(mockSummary);
    final fakeCampRepo = FakeCampRepoForReports();
    final fakePatientRepo = FakePatientRepoForReports(samplePatients);
    final fakeAuthRepo = FakeAuthRepoForReports(analystUser);

    return ProviderScope(
      overrides: [
        reportingRepositoryProvider.overrideWithValue(fakeReportingRepo),
        campRepositoryProvider.overrideWithValue(fakeCampRepo),
        patientRepositoryProvider.overrideWithValue(fakePatientRepo),
        authStateProvider.overrideWith((ref) => AuthViewModel(fakeAuthRepo)),
        campStateProvider.overrideWith((ref) {
          final vm = CampViewModel(fakeCampRepo);
          vm.loadCamps();
          return vm;
        }),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const CampReportView(),
      ),
    );
  }

  group('CampReportView Responsiveness & Seamless Camp Switching Tests', () {
    testWidgets('renders cleanly on mobile viewport (360x640) with zero RenderFlex overflow and 2x2 KPI grid', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull, reason: 'Must render with zero exceptions');

      // Verify Title & Camp Selector
      expect(find.text('Camp Clinical Reports'), findsOneWidget);
      expect(find.text('Select Camp Target:'), findsOneWidget);

      // Verify Export buttons in mobile stacked layout
      expect(find.text('Export PDF (पिडिएफ)'), findsOneWidget);
      expect(find.text('Export Excel (एक्सेल)'), findsOneWidget);

      // Verify 2x2 KPI cards
      expect(find.text('Registered'), findsOneWidget);
      expect(find.text('Examined'), findsOneWidget);
      expect(find.text('POP Stage >= 2'), findsOneWidget);
      expect(find.text('Referrals'), findsOneWidget);
      expect(find.text('47.6%'), findsOneWidget);

      // Verify Tabs exist
      expect(find.text('Demographics'), findsOneWidget);
      expect(find.text('POP Staging'), findsOneWidget);
      expect(find.text('Diagnoses'), findsOneWidget);
      expect(find.text('Treatment'), findsOneWidget);
      expect(find.text('Patient Records'), findsOneWidget);

      // Tap POP Staging Tab
      await tester.ensureVisible(find.text('POP Staging'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('POP Staging'));
      await tester.pumpAndSettle();
      expect(find.text('Highest POP Stage (Baden-Walker / POP-Q)'), findsOneWidget);
      expect(find.textContaining('Clinically Significant Prolapse'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(find.text('Middle (Uterine / Apex)'), findsOneWidget);
      expect(find.text('Posterior (Rectocele)'), findsOneWidget);

      // Tap Diagnoses Tab
      await tester.ensureVisible(find.text('Diagnoses'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Diagnoses'));
      await tester.pumpAndSettle();
      expect(find.text('Ranked Pathologies Identified'), findsOneWidget);

      // Tap Treatment Tab
      await tester.ensureVisible(find.text('Treatment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Treatment'));
      await tester.pumpAndSettle();
      expect(find.text('Interventions & Referrals'), findsOneWidget);

      // Tap Patient Records Tab
      await tester.ensureVisible(find.text('Patient Records'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Patient Records'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Search patients in this camp'), findsOneWidget);
      expect(find.text('Maya Devi Shrestha'), findsOneWidget);
      expect(find.text('GC-KTM-2026-0001'), findsOneWidget);

      expect(tester.takeException(), isNull, reason: 'Zero RenderFlex overflow across all tabs');
    });

    testWidgets('renders cleanly on desktop viewport (1280x1000) with wide 4-card KPI row', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.text('Camp Clinical Reports'), findsOneWidget);
      expect(find.text('Registered'), findsOneWidget);
      expect(find.text('Examined'), findsOneWidget);
      expect(find.text('POP Stage >= 2'), findsOneWidget);
      expect(find.text('Referrals'), findsOneWidget);
      expect(find.text('Export PDF (पिडिएफ)'), findsOneWidget);
      expect(find.text('Export Excel (एक्सेल)'), findsOneWidget);
    });

    testWidgets('non-destructive refresh maintains screen stability without unmounting body', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Switch to Patient Records tab first
      await tester.ensureVisible(find.text('Patient Records'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Patient Records'));
      await tester.pumpAndSettle();
      expect(find.text('Maya Devi Shrestha'), findsOneWidget);

      // Tap the Refresh Analytics button in AppBar
      final refreshBtn = find.byTooltip('Refresh Analytics');
      expect(refreshBtn, findsOneWidget);
      await tester.tap(refreshBtn);
      await tester.pump(); // frame where loading begins

      // Body must NOT be replaced with full-screen "Aggregating clinical camp records..."
      expect(find.text('Aggregating clinical camp records...'), findsNothing);
      // The tab view and active patient records must remain mounted and steady!
      expect(find.text('Camp Clinical Reports'), findsOneWidget);
      expect(find.text('Patient Records'), findsOneWidget);

      // Finish loading
      await tester.pumpAndSettle();
      expect(find.text('Maya Devi Shrestha'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('export individual patient dossier triggers PDF generation and displays snackbar', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestApp());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Navigate to Patient Records tab
      await tester.ensureVisible(find.text('Patient Records'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Patient Records'));
      await tester.pumpAndSettle();

      // Find first PDF Dossier button
      final dossierBtn = find.text('PDF Dossier').first;
      expect(dossierBtn, findsOneWidget);
      await tester.ensureVisible(dossierBtn);
      await tester.pumpAndSettle();
      await tester.tap(dossierBtn);
      await tester.pumpAndSettle();

      // Verify feedback snackbar
      expect(find.textContaining('Saved dossier:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
