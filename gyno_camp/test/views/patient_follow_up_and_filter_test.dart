import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/duplicate_detection_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/lookup_item_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/models/user_model.dart';
import 'package:gyno_camp/repositories/lookup_repository.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';
import 'package:gyno_camp/viewmodels/auth_viewmodel.dart';
import 'package:gyno_camp/viewmodels/camp_viewmodel.dart';
import 'package:gyno_camp/viewmodels/master_lookup_viewmodel.dart';
import 'package:gyno_camp/viewmodels/patient_list_viewmodel.dart';
import 'package:gyno_camp/viewmodels/patient_registration_viewmodel.dart';
import 'package:gyno_camp/views/patient/patient_follow_up_form_view.dart';
import 'package:gyno_camp/views/patient/patient_list_view.dart';
import 'package:gyno_camp/views/patient/patient_registration_view.dart';

class _FakeLookupRepository implements ILookupRepository {
  List<LookupItemModel> items = [
    const LookupItemModel(id: 'd1', category: 'diagnosis', code: 'candid', labelEn: 'Candid Infection', labelNe: 'कन्डिडा', subCategory: 'Infections & Reproductive Tract', isActive: true),
    const LookupItemModel(id: 'd2', category: 'diagnosis', code: 'fistula', labelEn: 'Fistula', labelNe: 'फिस्टुला', subCategory: 'Pelvic Floor & Incontinence', isActive: true),
    const LookupItemModel(id: 'm1', category: 'medicine', code: 'metronidazole', labelEn: 'Metronidazole 400mg', labelNe: 'मेट्रोनिडाजोल', subCategory: 'Antibiotics & Antifungals', isActive: true),
  ];

  @override
  Future<List<LookupItemModel>> getAllItems({String? campId, String? tenantId}) async => items;

  @override
  Future<List<LookupItemModel>> getItemsByCategory(String category, {String? campId, String? tenantId, bool activeOnly = false}) async {
    return items.where((i) => i.category == category && (!activeOnly || i.isActive)).toList();
  }

  @override
  Future<LookupItemModel> addItem(LookupItemModel item, {required String userId, required String userName, required String deviceId}) async {
    items.add(item);
    return item;
  }

  @override
  Future<LookupItemModel> updateItem(LookupItemModel item, {required String userId, required String userName, required String deviceId}) async => item;

  @override
  Future<bool> toggleItemStatus(String id, bool isActive, {String? campId, required String userId, required String userName, required String deviceId}) async => true;

  @override
  Future<bool> deleteItem(String id, {String? campId, required String userId, required String userName, required String deviceId}) async => true;

  @override
  Future<bool> restoreItemToCamp(String id, {required String campId, required String userId, required String userName, required String deviceId}) async => true;

  @override
  Future<void> ensureDefaultsSeeded({String? tenantId}) async {}
}

class _FakePatientRepository implements IPatientRepository {
  List<PatientModel> storedPatients = [];
  List<ClinicalVisitModel> visits = [];

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
  Future<List<PatientModel>> getPatientsByCamp([String? campId]) async {
    if (campId == null || campId == 'all') return storedPatients;
    return storedPatients.where((p) => p.campId == campId).toList();
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
    final list = visits.where((v) => v.patientId == patientId).toList();
    if (list.isEmpty) return null;
    return list.last;
  }
}

class _FakeCampViewModel extends StateNotifier<CampState> implements CampViewModel {
  _FakeCampViewModel(CampModel camp) : super(CampState(activeCamp: camp, camps: [camp]));

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

  final testUser = UserModel(
    id: 'user-nurse-1',
    name: 'Sita Sharma',
    email: 'sita@gynocamp.org',
    phone: '9841234567',
    role: UserRole.dataTaker,
    assignedCampIds: const ['camp-bagmati-1'],
    isActive: true,
  );

  final testCamp = CampModel(
    id: 'camp-bagmati-1',
    name: 'Sindhupalchok Health Outreach Camp',
    campCode: 'CAMP-SIN-01',
    venue: 'Chautara Primary Health Center',
    district: 'Sindhupalchok',
    municipality: 'Chautara',
    ward: '04',
    province: 'Bagmati',
    startDate: DateTime(2026, 1, 1),
    endDate: DateTime(2026, 1, 5),
    createdAt: DateTime(2026, 1, 1),
  );

  Widget createTestWidget({
    required Widget child,
    required _FakePatientRepository patientRepo,
    required _FakeLookupRepository lookupRepo,
    CampModel? camp,
  }) {
    final activeCamp = camp ?? testCamp;
    return ProviderScope(
      overrides: [
        patientRepositoryProvider.overrideWithValue(patientRepo),
        lookupRepositoryProvider.overrideWithValue(lookupRepo),
        authStateProvider.overrideWith((ref) => _FakeAuthViewModel(testUser)),
        campStateProvider.overrideWith((ref) => _FakeCampViewModel(activeCamp)),
        patientListProvider.overrideWith((ref) => PatientListViewModel(patientRepo)),
      ],
      child: MaterialApp(
        home: child,
      ),
    );
  }

  group('Patient Registration Block Letters Banner', () {
    testWidgets('Displays block letters instruction banner prominently', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final patientRepo = _FakePatientRepository();
      final lookupRepo = _FakeLookupRepository();

      await tester.pumpWidget(createTestWidget(
        child: const PatientRegistrationView(),
        patientRepo: patientRepo,
        lookupRepo: lookupRepo,
      ));
      await tester.pumpAndSettle();

      // Verify instruction banner text using RichText matcher
      expect(
        find.byWidgetPredicate((w) =>
          w is RichText && w.text.toPlainText().contains('INSTRUCTION: PLEASE FILL IN BLOCK LETTERS')
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate((w) =>
          w is RichText && w.text.toPlainText().contains('ठूला अक्षरमा भर्नुहोस्')
        ),
        findsOneWidget,
      );
    });
  });

  group('Patient Filter Panel (Demographic & Clinical Sections)', () {
    testWidgets('Renders Demographic & Clinical sections and responds to filter actions', (tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final patientRepo = _FakePatientRepository();
      final lookupRepo = _FakeLookupRepository();

      // Seed test patients
      patientRepo.storedPatients.addAll([
        PatientModel(
          id: 'p1',
          patientId: 'GC-2026-0001',
          campId: 'camp-bagmati-1',
          campCode: 'CAMP-SIN-01',
          intakeDate: DateTime.now(),
          firstName: 'Sita',
          surname: 'Sharma',
          age: 42,
          mobile: '9841234567',
          district: 'Sindhupalchok',
          province: 'Bagmati',
          municipality: 'Chautara',
          ward: '4',
          maritalStatus: 'married',
          diagnoses: ['fistula'],
          reasonsForVisit: ['urine problems'],
          highestPopStage: 2,
          surgeryDone: true,
          surgeryType: 'Vaginal route',
          createdAt: DateTime.now(),
          createdByUserId: 'user-nurse-1',
          createdByDeviceId: 'dev-1',
        ),
        PatientModel(
          id: 'p2',
          patientId: 'GC-2026-0002',
          campId: 'camp-bagmati-1',
          campCode: 'CAMP-SIN-01',
          intakeDate: DateTime.now(),
          firstName: 'Gita',
          surname: 'Tamang',
          age: 65,
          mobile: '9847654321',
          district: 'Kaski',
          province: 'Gandaki',
          municipality: 'Pokhara',
          ward: '2',
          maritalStatus: 'widow',
          diagnoses: ['candid'],
          reasonsForVisit: ['discharge/itching'],
          highestPopStage: 3,
          surgeryDone: false,
          createdAt: DateTime.now(),
          createdByUserId: 'user-nurse-1',
          createdByDeviceId: 'dev-1',
        ),
      ]);

      await tester.pumpWidget(createTestWidget(
        child: const PatientListView(),
        patientRepo: patientRepo,
        lookupRepo: lookupRepo,
      ));
      await tester.pumpAndSettle();

      // Open Filter Panel by tapping the Filters button
      final filterToggle = find.widgetWithText(OutlinedButton, 'Filters');
      expect(filterToggle, findsOneWidget);
      await tester.tap(filterToggle);
      await tester.pumpAndSettle();

      // Check Section 1: Demographic & Patient Filters
      expect(find.textContaining('Demographic & Patient Filters'), findsOneWidget);
      // Check Section 2: Clinical Intake & POP Staging Filters
      expect(find.textContaining('Clinical Intake & POP Staging Filters'), findsOneWidget);

      // Verify 5 Dropdowns: Marital Status, Clinical Intake, POP Stage, Surgery Performed, Chief Complaint
      expect(find.textContaining('Marital Status (वैवाहिक स्थिति)'), findsOneWidget);
      expect(find.text('All Marital Statuses (सबै)'), findsOneWidget);

      expect(find.textContaining('Clinical Intake Status (क्लिनिकल अवस्था)'), findsOneWidget);
      expect(find.text('All Patients (सबै बिरामी)'), findsOneWidget);

      expect(find.textContaining('POP Staging (आङ खस्ने अवस्था)'), findsOneWidget);
      expect(find.text('All Stages (सबै स्टेज)'), findsOneWidget);

      expect(find.textContaining('Surgery Performed (शल्यक्रिया भएको)'), findsOneWidget);
      expect(find.text('All / Any (सबै)'), findsOneWidget);

      expect(find.textContaining('Chief Clinical Complaint (मुख्य समस्या)'), findsOneWidget);
      expect(find.text('All Complaints (सबै मुख्य समस्या)'), findsOneWidget);

      // Open and select 'Surgery Done (शल्यक्रिया भएको)' from surgery dropdown
      final surgeryDropdown = find.byKey(const ValueKey('surgery_done_dropdown'));
      expect(surgeryDropdown, findsOneWidget);
      await tester.tap(surgeryDropdown);
      await tester.pumpAndSettle();

      // Tap 'Surgery Done (शल्यक्रिया भएको)' in the popup menu
      final surgeryDoneItem = find.text('Surgery Done (शल्यक्रिया भएको)').last;
      await tester.tap(surgeryDoneItem);
      await tester.pumpAndSettle();

      // Now Surgical Route dropdown is visible
      expect(find.textContaining('Surgical Route (शल्यक्रियाको प्रकार/मार्ग)'), findsOneWidget);
    });
  });

  group('Follow-Up Visit Workflow', () {
    testWidgets('Renders Follow-Up form and saves follow-up visit linked to same patient', (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final patientRepo = _FakePatientRepository();
      final lookupRepo = _FakeLookupRepository();

      final existingPatient = PatientModel(
        id: 'p1',
        patientId: 'GC-2026-0001',
        campId: 'camp-bagmati-1',
        campCode: 'CAMP-SIN-01',
        intakeDate: DateTime(2026, 1, 2),
        firstName: 'Sita',
        surname: 'Sharma',
        age: 45,
        mobile: '9841234567',
        district: 'Sindhupalchok',
        province: 'Bagmati',
        municipality: 'Chautara',
        ward: '4',
        maritalStatus: 'married',
        diagnoses: ['fistula'],
        reasonsForVisit: ['urine problems'],
        highestPopStage: 2,
        createdAt: DateTime(2026, 1, 2),
        createdByUserId: 'user-nurse-1',
        createdByDeviceId: 'dev-1',
      );

      // Previous initial visit
      final initialVisit = ClinicalVisitModel(
        id: 'vis-1',
        patientId: 'GC-2026-0001',
        campId: 'camp-bagmati-1',
        visitDate: DateTime(2026, 1, 2),
        deliveries: 3,
        livingChildren: 3,
        abortions: 0,
        anamnesisComplaints: {'reasons': ['urine problems']},
        popAnteriorStage: 2,
        popMiddleStage: 1,
        popPosteriorStage: 0,
        highestPopStage: 2,
        diagnoses: ['fistula'],
        medications: ['metronidazole'],
        isFollowUp: false,
        createdAt: DateTime(2026, 1, 2),
        createdByUserId: 'user-nurse-1',
      );
      patientRepo.visits.add(initialVisit);

      await tester.pumpWidget(createTestWidget(
        child: PatientFollowUpFormView(
          patient: existingPatient,
          camp: testCamp,
        ),
        patientRepo: patientRepo,
        lookupRepo: lookupRepo,
      ));
      await tester.pumpAndSettle();

      // Verify banner shows patient name and ID
      expect(find.textContaining('Sita Sharma'), findsWidgets);
      expect(find.textContaining('GC-2026-0001'), findsWidgets);

      // Verify previous visit summary card is shown and expand it
      final historyHeader = find.textContaining('Chronological Visit History');
      expect(historyHeader, findsOneWidget);
      await tester.tap(historyHeader);
      await tester.pumpAndSettle();

      expect(find.textContaining('Initial Assessment'), findsOneWidget);

      // Verify Follow-Up form sections
      expect(find.textContaining('1. Follow-Up Complaints & New Issues'), findsOneWidget);
      expect(find.textContaining('3. Pelvic Floor & POP Re-Staging'), findsOneWidget);

      // Verify Uterus Position and Pelvic Floor Tone controls
      expect(find.textContaining('Uterus Position (पाठेघरको अवस्था)'), findsOneWidget);
      expect(find.textContaining('Pelvic Floor Muscle Tone'), findsOneWidget);
      expect(find.text('Normal (सामान्य)'), findsOneWidget);
      expect(find.text('Weak / Lax (कमजोर)'), findsOneWidget);
      expect(find.text('Torn / Hypertonic (च्यातिएको वा तनाव)'), findsOneWidget);

      // Scroll into view and select Weak tone
      final weakChip = find.text('Weak / Lax (कमजोर)');
      await tester.ensureVisible(weakChip);
      await tester.pumpAndSettle();
      await tester.tap(weakChip);
      await tester.pumpAndSettle();

      // Verify save follow-up button exists
      expect(find.textContaining('Save Follow-Up Record'), findsOneWidget);
    });
  });
}
