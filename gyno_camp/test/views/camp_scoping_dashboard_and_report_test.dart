import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/duplicate_detection_service.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
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
import 'package:gyno_camp/viewmodels/device_security_viewmodel.dart';
import 'package:gyno_camp/viewmodels/patient_list_viewmodel.dart';
import 'package:gyno_camp/viewmodels/patient_registration_viewmodel.dart';
import 'package:gyno_camp/viewmodels/reporting_viewmodel.dart';
import 'package:gyno_camp/viewmodels/sync_viewmodel.dart';
import 'package:gyno_camp/views/dashboard/home_gateway_view.dart';
import 'package:gyno_camp/views/reports/camp_report_view.dart';

class _FakeSyncViewModel extends StateNotifier<SyncState> implements SyncViewModel {
  _FakeSyncViewModel() : super(const SyncState(isOnline: false));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDeviceSecurityViewModel extends StateNotifier<DeviceSecurityState>
    implements DeviceSecurityViewModel {
  _FakeDeviceSecurityViewModel()
      : super(const DeviceSecurityState(
          hardwareFingerprint: 'test-fp',
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

class _FakeTwoCampRepo implements ICampRepository {
  final List<CampModel> camps;
  _FakeTwoCampRepo(this.camps);

  @override
  Future<List<CampModel>> getAllCamps({String? tenantId}) async => camps;

  @override
  Future<CampModel?> getActiveCamp() async => camps.first;

  @override
  Future<CampModel?> getCampById(String id) async =>
      camps.where((c) => c.id == id).firstOrNull;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePatientRepo implements IPatientRepository {
  final List<PatientModel> allPatients;
  _FakePatientRepo(this.allPatients);

  @override
  Future<List<PatientModel>> getPatientsByCamp([
    String? campId,
    List<String>? allowedCampIds,
  ]) async {
    if (campId != null && campId.isNotEmpty && campId != 'all') {
      return allPatients.where((p) => p.campId == campId).toList();
    }
    if (allowedCampIds != null) {
      return allPatients.where((p) => allowedCampIds.contains(p.campId)).toList();
    }
    return List.from(allPatients);
  }

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
  final Map<String, List<PatientModel>> patientsByCamp;
  String? lastRequestedCampId;
  List<String>? lastAllowedCampIds;

  _FakeReportingRepo(this.patientsByCamp);

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
  }) async {
    lastRequestedCampId = campId;
    lastAllowedCampIds = allowedCampIds;

    if (allowedCampIds != null && allowedCampIds.isEmpty) {
      return CampReportSummaryModel.empty(generatedBy: generatedBy);
    }

    final matched = <PatientModel>[];
    if (campId != null && campId != 'all') {
      matched.addAll(patientsByCamp[campId] ?? const []);
    } else if (allowedCampIds != null) {
      for (final id in allowedCampIds) {
        matched.addAll(patientsByCamp[id] ?? const []);
      }
    } else {
      for (final list in patientsByCamp.values) {
        matched.addAll(list);
      }
    }

    return CampReportSummaryModel(
      campId: campId ?? 'all',
      campCode: campId == 'camp-122' ? '122' : '2222',
      campName: campId == 'camp-122' ? 'new official testing' : 'Women for Women Sodesi',
      district: 'Kathmandu',
      municipality: 'Budhanilkantha',
      venue: 'Health Post',
      startDate: DateTime(2026, 11, 19),
      endDate: DateTime(2026, 11, 21),
      generatedAt: DateTime.now(),
      generatedBy: generatedBy,
      totalPatientsRegistered: matched.length,
      totalVisitsRecorded: matched.length,
      ageGroups: const {},
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
      patients: matched,
    );
  }

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

void main() {
  final camp2222 = CampModel(
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
    assignedStaffIds: const ['other-staff'],
    // Newer createdAt so CampViewModel resolves camp-2222 as the GLOBAL activeCamp
    createdAt: DateTime(2026, 11, 19, 10, 0),
  );

  final camp122 = CampModel(
    id: 'camp-122',
    campCode: '122',
    name: 'new official testing',
    district: 'Kathmandu',
    municipality: 'Budhanilkantha',
    ward: '01',
    venue: 'Health Post',
    startDate: DateTime(2026, 11, 19),
    endDate: DateTime(2026, 11, 21),
    status: CampStatus.open,
    assignedStaffIds: const ['u-another-test'],
    createdAt: DateTime(2026, 11, 18, 10, 0),
  );

  const dataTakerUser = UserModel(
    id: 'u-another-test',
    name: 'another test',
    email: 'anothertest@gynocamp.org',
    phone: '9800000001',
    role: UserRole.dataTaker,
    assignedCampIds: ['camp-122'],
    isActive: true,
  );

  final camp122Patient = PatientModel(
    id: 'p-122-1',
    patientId: 'GC-122-2026-00001',
    campId: 'camp-122',
    campCode: '122',
    intakeDate: DateTime(2026, 11, 19),
    firstName: 'Maya',
    surname: 'Gurung',
    age: 42,
    mobile: '9841000122',
    ward: '01',
    district: 'Kathmandu',
    municipality: 'Budhanilkantha',
    reasonsForVisit: const ['checkup'],
    createdAt: DateTime(2026, 11, 19),
    createdByUserId: 'u-another-test',
    createdByDeviceId: 'dev-1',
  );

  group('Multi-camp Data Taker Dashboard & CampReportView Scoping Regressions', () {
    testWidgets(
      'Data Taker Dashboard reloads assigned camp (1 Registered) even when patientListProvider was previously loaded for another camp',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final campRepo = _FakeTwoCampRepo([camp2222, camp122]);
        final patientRepo = _FakePatientRepo([camp122Patient]);

        // Pre-populate patientListProvider with stale state for the UNASSIGNED camp-2222
        final stalePatientVm = PatientListViewModel(patientRepo);
        await stalePatientVm.loadPatients('camp-2222');
        expect(stalePatientVm.state.hasLoaded, isTrue);
        expect(stalePatientVm.state.loadedCampId, 'camp-2222');
        expect(stalePatientVm.state.patients, isEmpty);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              campRepositoryProvider.overrideWithValue(campRepo),
              patientRepositoryProvider.overrideWithValue(patientRepo),
              patientListProvider.overrideWith((ref) => stalePatientVm),
              syncStateProvider.overrideWith((ref) => _FakeSyncViewModel()),
              deviceSecurityProvider.overrideWith((ref) => _FakeDeviceSecurityViewModel()),
              authStateProvider.overrideWith((ref) => AuthViewModel(_FakeAuthRepo(dataTakerUser))),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const HomeGatewayView(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Dashboard must automatically detect loadedCampId != camp-122 and show 1 Registered
        expect(find.text('new official testing'), findsOneWidget);
        expect(find.text('1 Registered'), findsOneWidget);
        expect(find.text('0 Registered'), findsNothing);
        expect(stalePatientVm.state.loadedCampId, 'camp-122');
      },
    );

    testWidgets(
      'Data Taker Dashboard still displays 1 Registered even if an active search query filtered patientListProvider.patients to empty',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final campRepo = _FakeTwoCampRepo([camp2222, camp122]);
        final patientRepo = _FakePatientRepo([camp122Patient]);

        final filteredPatientVm = PatientListViewModel(patientRepo);
        await filteredPatientVm.search('camp-122', 'NoSuchName');
        expect(filteredPatientVm.state.rawPatients.length, 1);
        expect(filteredPatientVm.state.patients, isEmpty);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              campRepositoryProvider.overrideWithValue(campRepo),
              patientRepositoryProvider.overrideWithValue(patientRepo),
              patientListProvider.overrideWith((ref) => filteredPatientVm),
              syncStateProvider.overrideWith((ref) => _FakeSyncViewModel()),
              deviceSecurityProvider.overrideWith((ref) => _FakeDeviceSecurityViewModel()),
              authStateProvider.overrideWith((ref) => AuthViewModel(_FakeAuthRepo(dataTakerUser))),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const HomeGatewayView(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('1 Registered'), findsOneWidget);
        expect(find.text('0 Registered'), findsNothing);
      },
    );

    testWidgets(
      'CampReportView rejects unassigned initialCampId (camp-2222) for Data Taker and loads assigned camp-122 (1 Registered)',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final campRepo = _FakeTwoCampRepo([camp2222, camp122]);
        final patientRepo = _FakePatientRepo([camp122Patient]);
        final reportingRepo = _FakeReportingRepo({
          'camp-2222': const [],
          'camp-122': [camp122Patient],
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              campRepositoryProvider.overrideWithValue(campRepo),
              patientRepositoryProvider.overrideWithValue(patientRepo),
              reportingRepositoryProvider.overrideWithValue(reportingRepo),
              syncStateProvider.overrideWith((ref) => _FakeSyncViewModel()),
              deviceSecurityProvider.overrideWith((ref) => _FakeDeviceSecurityViewModel()),
              authStateProvider.overrideWith((ref) => AuthViewModel(_FakeAuthRepo(dataTakerUser))),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              // Even if a caller passes the wrong global active camp (camp-2222),
              // CampReportView must reject it and scope to assigned camp-122.
              home: const CampReportView(initialCampId: 'camp-2222'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(reportingRepo.lastRequestedCampId, 'camp-122');
        expect(reportingRepo.lastAllowedCampIds, ['camp-122']);
        expect(find.text('122 - new official testing'), findsOneWidget);
        expect(find.text('1'), findsWidgets);
      },
    );

    testWidgets(
      'Tapping Camp Summary on Data Taker Dashboard opens CampReportView scoped to user assigned camp (camp-122), not global camp-2222',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 1000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final campRepo = _FakeTwoCampRepo([camp2222, camp122]);
        final patientRepo = _FakePatientRepo([camp122Patient]);
        final reportingRepo = _FakeReportingRepo({
          'camp-2222': const [],
          'camp-122': [camp122Patient],
        });

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              campRepositoryProvider.overrideWithValue(campRepo),
              patientRepositoryProvider.overrideWithValue(patientRepo),
              reportingRepositoryProvider.overrideWithValue(reportingRepo),
              syncStateProvider.overrideWith((ref) => _FakeSyncViewModel()),
              deviceSecurityProvider.overrideWith((ref) => _FakeDeviceSecurityViewModel()),
              authStateProvider.overrideWith((ref) => AuthViewModel(_FakeAuthRepo(dataTakerUser))),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: const HomeGatewayView(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final summaryBtn = find.text('Camp Summary');
        await tester.ensureVisible(summaryBtn);
        await tester.tap(summaryBtn);
        await tester.pumpAndSettle();

        expect(find.text('Camp Clinical Reports'), findsOneWidget);
        expect(reportingRepo.lastRequestedCampId, 'camp-122');
        expect(find.text('122 - new official testing'), findsOneWidget);
      },
    );
  });
}
