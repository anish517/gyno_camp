import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/duplicate_detection_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/models/user_model.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';
import 'package:gyno_camp/viewmodels/auth_viewmodel.dart';
import 'package:gyno_camp/viewmodels/camp_viewmodel.dart';
import 'package:gyno_camp/viewmodels/patient_registration_viewmodel.dart';
import 'package:gyno_camp/views/patient/patient_registration_view.dart';

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
  Future<void> loadCamps({bool silent = false}) async {}

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
  );

  final testCamp = CampModel(
    id: 'camp-ktm-01',
    campCode: 'KTM-01',
    name: 'Budhanilkantha Outreach Camp',
    province: 'Bagmati',
    district: 'Kathmandu',
    municipality: 'Budhanilkantha Municipality',
    ward: '03',
    venue: 'Health Post',
    startDate: DateTime(2026, 3, 1),
    endDate: DateTime(2026, 3, 5),
    createdAt: DateTime(2026, 3, 1),
  );

  Widget createTestWidget({
    required _FakePatientRepository fakePatientRepo,
  }) {
    return ProviderScope(
      overrides: [
        patientRepositoryProvider.overrideWithValue(fakePatientRepo),
        campStateProvider.overrideWith((ref) => _FakeCampViewModel(testCamp)),
        authStateProvider.overrideWith((ref) => _FakeAuthViewModel(testUser)),
      ],
      child: const MaterialApp(
        home: PatientRegistrationView(),
      ),
    );
  }

  group('PatientRegistrationView Empty Form Validation Tests', () {
    testWidgets('Submitting empty form shows validation error and does NOT register any patient', (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeRepo = _FakePatientRepository();

      await tester.pumpWidget(createTestWidget(fakePatientRepo: fakeRepo));
      await tester.pumpAndSettle();

      // Find the Register Patient button
      final submitButton = find.widgetWithText(
        ElevatedButton,
        'Register Patient & Start Clinical Form (Station 1 → 2)',
      );
      expect(submitButton, findsOneWidget);

      // Ensure visible and tap submit without typing any details
      await tester.ensureVisible(submitButton);
      await tester.pumpAndSettle();
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // Zero patients must be stored in the repository
      expect(fakeRepo.storedPatients, isEmpty);

      // Expected validation SnackBar must be displayed
      expect(
        find.text('First name is required (पहिलो नाम अनिवार्य छ).'),
        findsOneWidget,
      );
    });

    testWidgets('Demo sample button opens confirmation dialog before populating', (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeRepo = _FakePatientRepository();

      await tester.pumpWidget(createTestWidget(fakePatientRepo: fakeRepo));
      await tester.pumpAndSettle();

      // Find magic wand demo button in AppBar
      final demoButton = find.byIcon(Icons.auto_fix_high_rounded);
      expect(demoButton, findsOneWidget);

      // Tap demo button
      await tester.tap(demoButton);
      await tester.pumpAndSettle();

      // Confirmation dialog should be displayed
      expect(find.text('Populate Demo Sample?'), findsOneWidget);
      expect(
        find.text(
          'This will fill the registration form with demo sample patient data (SUNTALI TAMANG, age 48) for demonstration and testing.\n\nAre you sure you want to proceed?',
        ),
        findsOneWidget,
      );

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog should be dismissed and form should remain empty
      expect(find.text('Populate Demo Sample?'), findsNothing);

      // Tap submit again - still empty, should show validation error
      final submitButton = find.widgetWithText(
        ElevatedButton,
        'Register Patient & Start Clinical Form (Station 1 → 2)',
      );
      await tester.ensureVisible(submitButton);
      await tester.pumpAndSettle();
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      expect(fakeRepo.storedPatients, isEmpty);
      expect(
        find.text('First name is required (पहिलो नाम अनिवार्य छ).'),
        findsOneWidget,
      );
    });

    testWidgets('Confirming demo sample fills data and can be submitted', (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeRepo = _FakePatientRepository();

      await tester.pumpWidget(createTestWidget(fakePatientRepo: fakeRepo));
      await tester.pumpAndSettle();

      // Tap demo button and confirm
      final demoButton = find.byIcon(Icons.auto_fix_high_rounded);
      await tester.tap(demoButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fill Sample'));
      await tester.pumpAndSettle();

      // Tap submit button
      final submitButton = find.widgetWithText(
        ElevatedButton,
        'Register Patient & Start Clinical Form (Station 1 → 2)',
      );
      await tester.ensureVisible(submitButton);
      await tester.pumpAndSettle();
      await tester.tap(submitButton);
      await tester.pumpAndSettle();

      // Exactly 1 patient registered with sample data
      expect(fakeRepo.storedPatients.length, 1);
      expect(fakeRepo.storedPatients.first.firstName, 'SUNTALI');
      expect(fakeRepo.storedPatients.first.surname, 'TAMANG');
      expect(fakeRepo.storedPatients.first.age, 48);
    });
  });
}
