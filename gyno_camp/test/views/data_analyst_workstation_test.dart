import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/duplicate_detection_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/camp_report_summary_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/lookup_item_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/models/user_model.dart';
import 'package:gyno_camp/repositories/lookup_repository.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';
import 'package:gyno_camp/repositories/reporting_repository.dart';
import 'package:gyno_camp/viewmodels/master_lookup_viewmodel.dart';
import 'package:gyno_camp/viewmodels/auth_viewmodel.dart';
import 'package:gyno_camp/viewmodels/camp_viewmodel.dart';
import 'package:gyno_camp/viewmodels/patient_list_viewmodel.dart';
import 'package:gyno_camp/viewmodels/patient_registration_viewmodel.dart';
import 'package:gyno_camp/viewmodels/reporting_viewmodel.dart';
import 'package:gyno_camp/viewmodels/sync_viewmodel.dart';
import 'package:gyno_camp/viewmodels/device_security_viewmodel.dart';
import 'package:gyno_camp/views/dashboard/home_gateway_view.dart';

class _FakeSyncViewModel extends StateNotifier<SyncState> implements SyncViewModel {
  _FakeSyncViewModel() : super(const SyncState(isOnline: false));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDeviceSecurityViewModel extends StateNotifier<DeviceSecurityState> implements DeviceSecurityViewModel {
  _FakeDeviceSecurityViewModel() : super(const DeviceSecurityState(hardwareFingerprint: 'test-fp', isInitialized: true, isChecking: false, isAppLocked: false));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePatientRepository implements IPatientRepository {
  List<PatientModel> storedPatients = [];
  List<ClinicalVisitModel> visits = [];
  String? lastCampIdQueried;
  List<String>? lastAllowedCampIdsQueried;

  @override
  Future<PatientModel> registerPatient(
    PatientModel patient, {
    required String createdByUserId,
    required String createdByUserName,
    required String createdByUserRole,
    required String deviceId,
  }) async {
    storedPatients.add(patient);
    return patient;
  }

  @override
  Future<PatientModel> updatePatient(
    PatientModel patient, {
    required String updatedByUserId,
    required String updatedByUserName,
    required String updatedByUserRole,
    required String deviceId,
  }) async {
    final idx = storedPatients.indexWhere((p) => p.id == patient.id || p.patientId == patient.patientId);
    if (idx != -1) {
      storedPatients[idx] = patient;
    } else {
      storedPatients.add(patient);
    }
    return patient;
  }

  @override
  Future<List<PatientModel>> getPatientsByCamp([String? campId, List<String>? allowedCampIds]) async {
    lastCampIdQueried = campId;
    lastAllowedCampIdsQueried = allowedCampIds;
    if (campId != null && campId != 'all') {
      return storedPatients.where((p) => p.campId == campId).toList();
    }
    if (allowedCampIds != null) {
      return storedPatients.where((p) => allowedCampIds.contains(p.campId)).toList();
    }
    return storedPatients;
  }

  @override
  Future<PatientModel?> getPatientByPatientId(String patientId) async {
    try {
      return storedPatients.firstWhere((p) => p.patientId == patientId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<PatientModel>> searchPatients({required String campId, required String query}) async {
    final q = query.toLowerCase();
    return storedPatients.where((p) =>
      p.patientId.toLowerCase().contains(q) ||
      p.fullName.toLowerCase().contains(q) ||
      p.mobile.contains(q)
    ).toList();
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
  }) async => const DuplicateCheckResult.none();

  @override
  Future<ClinicalVisitModel> saveClinicalVisit(
    ClinicalVisitModel visit, {
    required String createdByUserId,
    required String deviceId,
  }) async {
    visits.add(visit);
    return visit;
  }

  @override
  Future<List<ClinicalVisitModel>> getClinicalVisits(String patientId, {String? patientUuid}) async {
    return visits.where((v) => v.patientId == patientId).toList();
  }

  @override
  Future<ClinicalVisitModel?> getLatestClinicalVisit(String patientId, {String? patientUuid}) async {
    final vList = visits.where((v) => v.patientId == patientId).toList();
    if (vList.isEmpty) return null;
    return vList.last;
  }
}

class _FakeReportingRepository implements IReportingRepository {
  CampReportSummaryModel? customSummary;
  String? lastCampIdQueried;
  List<String>? lastAllowedCampIdsQueried;

  @override
  Future<CampReportSummaryModel> getCampSummary({
    String? campId,
    List<String>? allowedCampIds,
    String? doctorFilter,
    String? nurseFilter,
    String generatedBy = 'Data Analyst',
    DateTime? startDate,
    DateTime? endDate,
    String? diagnosisFilter,
    String? popStageFilter,
    String? treatmentFilter,
    String? complaintFilter,
    String? visitReasonFilter,
  }) async {
    lastCampIdQueried = campId;
    lastAllowedCampIdsQueried = allowedCampIds;
    return customSummary ?? CampReportSummaryModel.empty(
      generatedBy: generatedBy,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLookupRepository implements ILookupRepository {
  List<LookupItemModel> items = [];
  String? lastCampIdQueried;
  List<String>? lastAllowedCampIdsQueried;

  @override
  Future<List<LookupItemModel>> getAllItems({String? campId, String? tenantId}) async => items;

  @override
  Future<List<LookupItemModel>> getItemsByCategory(
    String category, {
    String? campId,
    String? tenantId,
    List<String>? allowedCampIds,
    bool activeOnly = false,
  }) async {
    lastCampIdQueried = campId;
    lastAllowedCampIdsQueried = allowedCampIds;
    return items.where((i) {
      if (i.category != category) return false;
      if (activeOnly && !i.isActive) return false;
      if (campId != null && i.campId != null && i.campId != campId) return false;
      if (allowedCampIds != null && i.campId != null && !allowedCampIds.contains(i.campId)) return false;
      return true;
    }).toList();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCampViewModel extends StateNotifier<CampState> implements CampViewModel {
  _FakeCampViewModel({required CampModel active, required List<CampModel> all})
      : super(CampState(activeCamp: active, selectedCamp: active, camps: all));

  void setCamps(List<CampModel> newCamps) {
    state = state.copyWith(
      camps: newCamps,
      activeCamp: newCamps.contains(state.activeCamp) ? state.activeCamp : (newCamps.isNotEmpty ? newCamps.first : null),
      selectedCamp: newCamps.contains(state.selectedCamp) ? state.selectedCamp : (newCamps.isNotEmpty ? newCamps.first : null),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAuthViewModel extends StateNotifier<AuthState> implements AuthViewModel {
  _FakeAuthViewModel(UserModel user) : super(AuthState(currentUser: user));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final camp1 = CampModel(
    id: 'camp-1',
    name: 'Sindhupalchok Camp',
    campCode: 'CAMP-SIN-01',
    organizationName: 'Nepal Health Outreach',
    venue: 'Chautara Hospital',
    district: 'Sindhupalchok',
    province: 'Bagmati',
    municipality: 'Chautara',
    ward: '4',
    startDate: DateTime(2026, 1, 1),
    endDate: DateTime(2026, 1, 5),
    status: CampStatus.open,
    createdAt: DateTime.now(),
  );

  final camp2 = CampModel(
    id: 'camp-2',
    name: 'Kavre Health Outreach',
    campCode: 'CAMP-KAV-02',
    organizationName: 'Nepal Health Outreach',
    venue: 'Dhulikhel Center',
    district: 'Kavrepalanchok',
    province: 'Bagmati',
    municipality: 'Dhulikhel',
    ward: '2',
    startDate: DateTime(2026, 2, 1),
    endDate: DateTime(2026, 2, 5),
    status: CampStatus.open,
    createdAt: DateTime.now(),
  );

  final testAnalystUser = UserModel(
    id: 'usr-analyst-1',
    name: 'Dr. Sunita Adhikari',
    email: 'sunita@gynocamp.org',
    phone: '9841000000',
    role: UserRole.dataAnalyst,
    assignedCampIds: const ['camp-1', 'camp-2'],
    tenantId: 'tenant-test',
    tenantName: 'Nepal Health Outreach Network',
  );

  Widget createTestWidget({
    required Widget child,
    required _FakePatientRepository patientRepo,
    required _FakeReportingRepository reportingRepo,
    _FakeLookupRepository? lookupRepo,
    _FakeCampViewModel? campViewModel,
    UserModel? user,
  }) {
    return ProviderScope(
      overrides: [
        patientRepositoryProvider.overrideWithValue(patientRepo),
        reportingRepositoryProvider.overrideWithValue(reportingRepo),
        lookupRepositoryProvider.overrideWithValue(lookupRepo ?? _FakeLookupRepository()),
        authStateProvider.overrideWith((ref) => _FakeAuthViewModel(user ?? testAnalystUser)),
        campStateProvider.overrideWith((ref) => campViewModel ?? _FakeCampViewModel(active: camp1, all: [camp1, camp2])),
        patientListProvider.overrideWith((ref) => PatientListViewModel(patientRepo)),
        syncStateProvider.overrideWith((ref) => _FakeSyncViewModel()),
        deviceSecurityProvider.overrideWith((ref) => _FakeDeviceSecurityViewModel()),
      ],
      child: MaterialApp(
        home: child,
      ),
    );
  }

  group('Data Analyst Workstation & Charts Verification', () {
    testWidgets('Renders Clinical Data Analyst Terminal, KPIs, and Visual Charts', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final patientRepo = _FakePatientRepository();
      final reportingRepo = _FakeReportingRepository();

      // Seed 3 Patients with distinct features across 2 camps
      final p1 = PatientModel(
        id: 'p1',
        patientId: 'GC-2026-0001',
        campId: 'camp-1',
        campCode: 'CAMP-SIN-01',
        intakeDate: DateTime(2026, 1, 2),
        firstName: 'Sita',
        surname: 'Sharma',
        age: 48,
        mobile: '9841234567',
        district: 'Sindhupalchok',
        province: 'Bagmati',
        municipality: 'Chautara',
        ward: '4',
        reasonsForVisit: ['something hanging out', 'pain'],
        highestPopStage: 3,
        hasClinicalVisit: true,
        createdAt: DateTime.now(),
        createdByUserId: 'user-1',
        createdByDeviceId: 'dev-1',
      );

      final p2 = PatientModel(
        id: 'p2',
        patientId: 'GC-2026-0002',
        campId: 'camp-1',
        campCode: 'CAMP-SIN-01',
        intakeDate: DateTime(2026, 1, 2),
        firstName: 'Gita',
        surname: 'Thapa',
        age: 28,
        mobile: '9841234568',
        district: 'Sindhupalchok',
        province: 'Bagmati',
        municipality: 'Chautara',
        ward: '3',
        reasonsForVisit: ['discharge and or itching'],
        highestPopStage: 1,
        hasClinicalVisit: true,
        createdAt: DateTime.now(),
        createdByUserId: 'user-1',
        createdByDeviceId: 'dev-1',
      );

      final p3 = PatientModel(
        id: 'p3',
        patientId: 'GC-2026-0003',
        campId: 'camp-2',
        campCode: 'CAMP-KAV-02',
        intakeDate: DateTime(2026, 2, 2),
        firstName: 'Maya',
        surname: 'Tamang',
        age: 62,
        mobile: '9841234569',
        district: 'Kavrepalanchok',
        province: 'Bagmati',
        municipality: 'Dhulikhel',
        ward: '2',
        reasonsForVisit: ['problems passing urine'],
        highestPopStage: 4,
        surgeryDone: true,
        hasClinicalVisit: true,
        createdAt: DateTime.now(),
        createdByUserId: 'user-1',
        createdByDeviceId: 'dev-1',
      );

      patientRepo.storedPatients = [p1, p2, p3];

      patientRepo.visits = [
        ClinicalVisitModel(
          id: 'v1',
          patientId: 'GC-2026-0001',
          campId: 'camp-1',
          visitDate: DateTime(2026, 1, 2),
          highestPopStage: 3,
          systolicBp: 150,
          diastolicBp: 95,
          surgicalReferral: 'Model Hospital',
          anamnesisComplaints: const {'reasons': ['something hanging out', 'pain']},
          createdAt: DateTime.now(),
          createdByUserId: 'nurse-1',
        ),
        ClinicalVisitModel(
          id: 'v2',
          patientId: 'GC-2026-0002',
          campId: 'camp-1',
          visitDate: DateTime(2026, 1, 2),
          highestPopStage: 1,
          systolicBp: 118,
          diastolicBp: 78,
          pessaryType: 'ring',
          pessarySize: 'size 3',
          anamnesisComplaints: const {'reasons': ['discharge and or itching']},
          createdAt: DateTime.now(),
          createdByUserId: 'nurse-1',
        ),
        ClinicalVisitModel(
          id: 'v3',
          patientId: 'GC-2026-0003',
          campId: 'camp-2',
          visitDate: DateTime(2026, 2, 2),
          highestPopStage: 4,
          systolicBp: 130,
          diastolicBp: 84,
          surgeryDone: true,
          anamnesisComplaints: const {'reasons': ['problems passing urine']},
          createdAt: DateTime.now(),
          createdByUserId: 'nurse-1',
        ),
      ];

      await tester.pumpWidget(createTestWidget(
        child: const HomeGatewayView(),
        patientRepo: patientRepo,
        reportingRepo: reportingRepo,
      ));
      await tester.pumpAndSettle();

      // 1. Verify Command Header & Role Title
      expect(find.textContaining('CLINICAL DATA ANALYST WORKSTATION'), findsOneWidget);
      expect(find.textContaining('Dr. Sunita Adhikari'), findsWidgets);
      expect(find.textContaining('Nepal Health Outreach'), findsWidgets);

      // 2. Verify 4 Telemetry Metric Cards
      expect(find.text('Registered Cohort'), findsOneWidget);
      expect(find.text('POP Grade II-IV'), findsOneWidget);
      expect(find.text('Surgical Candidates'), findsOneWidget);
      expect(find.text('Prescriptions'), findsOneWidget);

      // 3. Verify Multi-Dimensional Filter Bar Controls
      expect(find.text('Multi-Dimensional Analytics Filters'), findsOneWidget);
      expect(find.text('POP Severity'), findsOneWidget);
      expect(find.text('Chief Clinical Complaint (मुख्य समस्या)'), findsOneWidget);
      expect(find.text('Surgery Status'), findsOneWidget);
      expect(find.text('Age Cohort'), findsOneWidget);
      expect(find.textContaining('Hypertension Alert (HTN >= 140/90)'), findsOneWidget);

      // 4. Verify 5 Charts Exist
      expect(find.textContaining('Pelvic Organ Prolapse (POP-Q) Severity Spectrum'), findsOneWidget);
      expect(find.textContaining('Chief Clinical Complaints Frequency & Ranking'), findsOneWidget);
      expect(find.textContaining('Demographic Age Cohort Distribution'), findsOneWidget);
      expect(find.textContaining('Clinical Treatment & Management Modalities'), findsOneWidget);
      expect(find.textContaining('Cross-Camp Volume & Epidemiological Comparison'), findsOneWidget);

      // 5. Verify Camp-Wise Patient Registry with Camp Badges
      expect(find.textContaining('Individual Patient Clinical Dossiers'), findsOneWidget);
      expect(find.text('Sita Sharma'), findsOneWidget);
      expect(find.text('Gita Thapa'), findsOneWidget);
      expect(find.text('Maya Tamang'), findsOneWidget);

      // Verify camp badges
      expect(find.textContaining('CAMP-SIN-01'), findsWidgets);
      expect(find.textContaining('CAMP-KAV-02'), findsWidgets);

      // Verify Inspect and PDF Dossier buttons exist
      expect(find.text('Inspect'), findsWidgets);
      expect(find.text('PDF Dossier'), findsWidgets);

      // 6. Test Filtering: Tap Hypertension Alert Filter
      final htnChip = find.textContaining('Hypertension Alert (HTN >= 140/90)');
      await tester.ensureVisible(htnChip);
      await tester.pumpAndSettle();
      await tester.tap(htnChip);
      await tester.pumpAndSettle();

      // Only Sita Sharma (BP 150/95) matches HTN alert!
      expect(find.text('Sita Sharma'), findsOneWidget);
      expect(find.text('Gita Thapa'), findsNothing);
      expect(find.text('Maya Tamang'), findsNothing);

      // Reset filters
      final resetBtn = find.text('Reset All');
      expect(resetBtn, findsOneWidget);
      await tester.ensureVisible(resetBtn);
      await tester.pumpAndSettle();
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();

      // All patients visible again
      final gita = find.text('Gita Thapa');
      await tester.ensureVisible(gita);
      await tester.pumpAndSettle();

      expect(find.text('Sita Sharma'), findsOneWidget);
      expect(find.text('Gita Thapa'), findsOneWidget);
      expect(find.text('Maya Tamang'), findsOneWidget);
    });

    testWidgets('Tab navigation switches views and inspect button opens patient dossier sheet', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final patientRepo = _FakePatientRepository();
      final reportingRepo = _FakeReportingRepository();

      final p1 = PatientModel(
        id: 'p1',
        patientId: 'GC-2026-0001',
        campId: 'camp-1',
        campCode: 'CAMP-SIN-01',
        intakeDate: DateTime(2026, 1, 2),
        firstName: 'Sita',
        surname: 'Sharma',
        age: 48,
        mobile: '9841234567',
        district: 'Sindhupalchok',
        province: 'Bagmati',
        municipality: 'Chautara',
        ward: '4',
        reasonsForVisit: ['something hanging out'],
        highestPopStage: 3,
        hasClinicalVisit: true,
        createdAt: DateTime.now(),
        createdByUserId: 'user-1',
        createdByDeviceId: 'dev-1',
      );
      patientRepo.storedPatients = [p1];

      patientRepo.visits = [
        ClinicalVisitModel(
          id: 'v1',
          patientId: 'GC-2026-0001',
          campId: 'camp-1',
          visitDate: DateTime(2026, 1, 2),
          highestPopStage: 3,
          systolicBp: 145,
          diastolicBp: 92,
          deliveries: 4,
          livingChildren: 4,
          popAnteriorStage: 3,
          popMiddleStage: 2,
          popPosteriorStage: 1,
          diagnoses: const ['fistula', 'cervicitis'],
          counseling: const ['Pelvic floor muscle training'],
          createdAt: DateTime.now(),
          createdByUserId: 'nurse-1',
        ),
      ];

      await tester.pumpWidget(createTestWidget(
        child: const DataAnalystWorkstationPage(),
        patientRepo: patientRepo,
        reportingRepo: reportingRepo,
      ));
      await tester.pumpAndSettle();

      // Verify DataAnalystWorkstationPage AppBar title
      expect(find.text('Data Analyst Workstation'), findsOneWidget);
      expect(find.text('Cross-Camp Epidemiology & Visual Analytics'), findsWidgets);

      // Tap on "Camp-Wise Patients" tab
      final patientsTab = find.textContaining('Camp-Wise Patients');
      expect(patientsTab, findsOneWidget);
      await tester.tap(patientsTab);
      await tester.pumpAndSettle();

      // Inspect button for Sita Sharma
      final inspectBtn = find.widgetWithText(OutlinedButton, 'Inspect');
      expect(inspectBtn, findsOneWidget);
      await tester.tap(inspectBtn);
      await tester.pumpAndSettle();

      // Bottom sheet is displayed with clinical sections
      expect(find.textContaining('1. Obstetric History (प्रसूति इतिहास)'), findsOneWidget);
      expect(find.textContaining('2. Triage & Vitals (शारीरिक परीक्षण)'), findsOneWidget);
      expect(find.textContaining('3. Pelvic Organ Prolapse (Baden-Walker POP-Q)'), findsOneWidget);
      expect(find.textContaining('4. Diagnoses & Management (निदान तथा उपचार)'), findsOneWidget);

      // Verify diagnosis chips in dossier
      expect(find.text('fistula'), findsOneWidget);
      expect(find.text('cervicitis'), findsOneWidget);
    });

    testWidgets('All Camps filter strictly scopes patient queries and lookups to assigned camps, excluding unassigned and deleted camps', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final patientRepo = _FakePatientRepository();
      final reportingRepo = _FakeReportingRepository();
      final lookupRepo = _FakeLookupRepository();

      final camp3 = CampModel(
        id: 'camp-3',
        name: 'Unassigned Pokhara Camp',
        campCode: 'CAMP-PKR-03',
        organizationName: 'Global Health',
        venue: 'Pokhara Clinic',
        district: 'Kaski',
        province: 'Gandaki',
        municipality: 'Pokhara',
        ward: '1',
        startDate: DateTime(2026, 3, 1),
        endDate: DateTime(2026, 3, 5),
        status: CampStatus.open,
        createdAt: DateTime.now(),
      );

      final p1 = PatientModel(
        id: 'pat-1',
        patientId: 'GC-2026-0010',
        campId: 'camp-1',
        campCode: 'CAMP-SIN-01',
        intakeDate: DateTime(2026, 1, 2),
        firstName: 'Asha',
        surname: 'Rai',
        age: 34,
        mobile: '9841111111',
        district: 'Sindhupalchok',
        province: 'Bagmati',
        municipality: 'Chautara',
        ward: '4',
        reasonsForVisit: ['something hanging out'],
        highestPopStage: 2,
        hasClinicalVisit: true,
        createdAt: DateTime.now(),
        createdByUserId: 'user-1',
        createdByDeviceId: 'dev-1',
      );

      final p2 = PatientModel(
        id: 'pat-2',
        patientId: 'GC-2026-0020',
        campId: 'camp-2',
        campCode: 'CAMP-KAV-02',
        intakeDate: DateTime(2026, 2, 2),
        firstName: 'Binita',
        surname: 'Tamang',
        age: 42,
        mobile: '9842222222',
        district: 'Kavrepalanchok',
        province: 'Bagmati',
        municipality: 'Dhulikhel',
        ward: '2',
        reasonsForVisit: ['pain'],
        highestPopStage: 3,
        hasClinicalVisit: true,
        createdAt: DateTime.now(),
        createdByUserId: 'user-1',
        createdByDeviceId: 'dev-1',
      );

      final p3Unassigned = PatientModel(
        id: 'pat-3',
        patientId: 'GC-2026-0030',
        campId: 'camp-3',
        campCode: 'CAMP-PKR-03',
        intakeDate: DateTime(2026, 3, 2),
        firstName: 'Chandra',
        surname: 'Gurung',
        age: 50,
        mobile: '9843333333',
        district: 'Kaski',
        province: 'Gandaki',
        municipality: 'Pokhara',
        ward: '1',
        reasonsForVisit: ['unassigned reason'],
        highestPopStage: 4,
        hasClinicalVisit: true,
        createdAt: DateTime.now(),
        createdByUserId: 'user-1',
        createdByDeviceId: 'dev-1',
      );

      patientRepo.storedPatients = [p1, p2, p3Unassigned];

      // Seed lookups: assigned camp 1, unassigned camp 3, and a deleted camp
      lookupRepo.items = [
        const LookupItemModel(
          id: 'vr-1',
          category: 'visit_reason',
          code: 'vr_assigned_1',
          labelEn: 'Assigned Camp 1 Reason',
          labelNe: 'तोकिएको शिविर १ कारण',
          campId: 'camp-1',
          isActive: true,
        ),
        const LookupItemModel(
          id: 'vr-3',
          category: 'visit_reason',
          code: 'vr_unassigned_3',
          labelEn: 'Unassigned Camp 3 Reason',
          labelNe: 'नतोकिएको शिविर ३ कारण',
          campId: 'camp-3',
          isActive: true,
        ),
        const LookupItemModel(
          id: 'vr-del',
          category: 'visit_reason',
          code: 'vr_deleted_camp',
          labelEn: 'Deleted Camp Ghost Reason',
          labelNe: 'हटाइएको शिविर कारण',
          campId: 'camp-deleted',
          isActive: true,
        ),
      ];

      // testAnalystUser is only assigned to ['camp-1', 'camp-2']
      final campVM = _FakeCampViewModel(active: camp1, all: [camp1, camp2, camp3]);

      await tester.pumpWidget(createTestWidget(
        child: const DataAnalystWorkstationPage(),
        patientRepo: patientRepo,
        reportingRepo: reportingRepo,
        lookupRepo: lookupRepo,
        campViewModel: campVM,
      ));
      await tester.pumpAndSettle();

      // 1. Verify queries passed allowedCampIds strictly matching assigned visible camps
      expect(patientRepo.lastAllowedCampIdsQueried, isNotNull);
      expect(patientRepo.lastAllowedCampIdsQueried, contains('camp-1'));
      expect(patientRepo.lastAllowedCampIdsQueried, contains('camp-2'));
      expect(patientRepo.lastAllowedCampIdsQueried, isNot(contains('camp-3')));
      expect(patientRepo.lastAllowedCampIdsQueried, isNot(contains('camp-deleted')));

      expect(reportingRepo.lastAllowedCampIdsQueried, isNotNull);
      expect(reportingRepo.lastAllowedCampIdsQueried, contains('camp-1'));
      expect(reportingRepo.lastAllowedCampIdsQueried, contains('camp-2'));
      expect(reportingRepo.lastAllowedCampIdsQueried, isNot(contains('camp-3')));

      expect(lookupRepo.lastAllowedCampIdsQueried, isNotNull);
      expect(lookupRepo.lastAllowedCampIdsQueried, contains('camp-1'));
      expect(lookupRepo.lastAllowedCampIdsQueried, contains('camp-2'));
      expect(lookupRepo.lastAllowedCampIdsQueried, isNot(contains('camp-3')));

      // 2. Verify lookup options strictly include assigned camp and exclude unassigned & deleted camps in overview
      expect(find.textContaining('Assigned Camp 1 Reason'), findsWidgets);
      expect(find.textContaining('Unassigned Camp 3 Reason'), findsNothing);
      expect(find.textContaining('Deleted Camp Ghost Reason'), findsNothing);

      // 3. Switch to Camp-Wise Patients tab
      final patientsTab = find.textContaining('Camp-Wise Patients');
      expect(patientsTab, findsOneWidget);
      await tester.tap(patientsTab);
      await tester.pumpAndSettle();

      // Assigned patients appear
      expect(find.text('Asha Rai'), findsOneWidget);
      expect(find.text('Binita Tamang'), findsOneWidget);
      // Unassigned camp patient is NOT rendered
      expect(find.text('Chandra Gurung'), findsNothing);
    });

    testWidgets('Deleting an assigned camp reactively resets selection and re-scopes queries to remaining visible camps', (tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final patientRepo = _FakePatientRepository();
      final reportingRepo = _FakeReportingRepository();
      final lookupRepo = _FakeLookupRepository();

      final p1 = PatientModel(
        id: 'pat-1',
        patientId: 'GC-2026-0010',
        campId: 'camp-1',
        campCode: 'CAMP-SIN-01',
        intakeDate: DateTime(2026, 1, 2),
        firstName: 'Asha',
        surname: 'Rai',
        age: 34,
        mobile: '9841111111',
        district: 'Sindhupalchok',
        province: 'Bagmati',
        municipality: 'Chautara',
        ward: '4',
        reasonsForVisit: ['something hanging out'],
        highestPopStage: 2,
        hasClinicalVisit: true,
        createdAt: DateTime.now(),
        createdByUserId: 'user-1',
        createdByDeviceId: 'dev-1',
      );
      patientRepo.storedPatients = [p1];

      final campVM = _FakeCampViewModel(active: camp1, all: [camp1, camp2]);

      await tester.pumpWidget(createTestWidget(
        child: const DataAnalystWorkstationPage(),
        patientRepo: patientRepo,
        reportingRepo: reportingRepo,
        lookupRepo: lookupRepo,
        campViewModel: campVM,
      ));
      await tester.pumpAndSettle();

      // Initially All Assigned Camps (2) is present
      expect(find.textContaining('All Assigned Camps (2)'), findsOneWidget);

      // Simulate deletion of camp2: camps list now contains only camp1
      campVM.setCamps([camp1]);
      await tester.pumpAndSettle();

      // Reactive listener fired and refreshed workstation with only camp1 remaining
      expect(patientRepo.lastAllowedCampIdsQueried, isNotNull);
      expect(patientRepo.lastAllowedCampIdsQueried, contains('camp-1'));
      expect(patientRepo.lastAllowedCampIdsQueried, isNot(contains('camp-2')));

      // UI updates gracefully without errors
      expect(find.text('Data Analyst Workstation'), findsOneWidget);
    });
  });
}
