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
import 'package:gyno_camp/viewmodels/patient_registration_viewmodel.dart';
import 'package:gyno_camp/views/patient/clinical_assessment_view.dart';
import 'package:gyno_camp/views/patient/patient_follow_up_slip_modal.dart';
import 'package:gyno_camp/views/patient/patient_list_view.dart';
import 'package:gyno_camp/views/patient/patient_registration_view.dart';

class _FakeLookupRepository implements ILookupRepository {
  List<LookupItemModel> items = [
    const LookupItemModel(id: 'd1', category: 'diagnosis', code: 'candid', labelEn: 'Candid Infection', labelNe: 'कन्डिडा', isActive: true),
    const LookupItemModel(id: 'm1', category: 'medicine', code: 'metronidazole', labelEn: 'Metronidazole 400mg', labelNe: 'मेट्रोनिडाजोल', isActive: true),
    const LookupItemModel(id: 'h1', category: 'referral_hospital', code: 'scheer', labelEn: 'Scheer Memorial Hospital', labelNe: 'शीर मेमोरियल', isActive: true),
  ];

  @override
  Future<List<LookupItemModel>> getAllItems({String? tenantId}) async => items;

  @override
  Future<List<LookupItemModel>> getItemsByCategory(String category, {String? tenantId, bool activeOnly = false}) async {
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
  Future<bool> toggleItemStatus(String id, bool isActive, {required String userId, required String userName, required String deviceId}) async => true;

  @override
  Future<bool> deleteItem(String id, {required String userId, required String userName, required String deviceId}) async => true;

  @override
  Future<void> ensureDefaultsSeeded({String? tenantId}) async {}
}

class _FakePatientRepository implements IPatientRepository {
  List<PatientModel> storedPatients = [];
  ClinicalVisitModel? lastSavedVisit;

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
  Future<List<PatientModel>> getPatientsByCamp([String? campId]) async => storedPatients;

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
    lastSavedVisit = visit;
    return visit;
  }

  @override
  Future<List<ClinicalVisitModel>> getClinicalVisits(String patientId, {String? patientUuid}) async =>
      lastSavedVisit != null ? [lastSavedVisit!] : [];

  @override
  Future<ClinicalVisitModel?> getLatestClinicalVisit(String patientId, {String? patientUuid}) async =>
      lastSavedVisit;
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

  final samplePatient = PatientModel(
    id: 'pat-resp-01',
    patientId: 'GC-KTM01-2026-00042',
    campId: 'camp-resp-01',
    campCode: 'KTM01',
    intakeDate: DateTime(2026, 9, 7),
    firstName: 'Suntali',
    surname: 'Tamang',
    age: 48,
    mobile: '9841555666',
    ward: '03',
    district: 'Kathmandu',
    municipality: 'Budhanilkantha Municipality',
    spouseOrFatherName: 'Dorje Tamang',
    relationshipType: 'Husband',
    maritalStatus: 'married',
    reasonsForVisit: const ['something hanging out', 'pain'],
    createdAt: DateTime(2026, 9, 7),
    createdByUserId: 'usr-datataker-01',
    createdByDeviceId: 'dev-tab-01',
    tenantId: 'tenant_bir_hospital',
  );

  final sampleCamp = CampModel(
    id: 'camp-resp-01',
    campCode: 'KTM01',
    name: 'Kathmandu Community Gyno Health Camp',
    district: 'Kathmandu',
    municipality: 'Budhanilkantha Municipality',
    ward: '03',
    venue: 'Primary Health Care Center',
    startDate: DateTime(2026, 9, 7),
    endDate: DateTime(2026, 9, 10),
    createdAt: DateTime(2026, 9, 6),
    tenantId: 'tenant_bir_hospital',
    organizationName: 'Bir Hospital Gyno Outreach',
  );

  final sampleUser = UserModel(
    id: 'usr-admin-01',
    name: 'Dr. Gita Sharma',
    email: 'gita@gynocamp.org',
    phone: '9841000001',
    role: UserRole.superAdmin,
    tenantId: 'tenant_bir_hospital',
    assignedCampIds: const ['camp-resp-01'],
    isActive: true,
  );

  group('Patient Views Responsive & UX Verification', () {
    late _FakePatientRepository fakePatientRepo;
    late _FakeLookupRepository fakeLookupRepo;

    setUp(() {
      fakePatientRepo = _FakePatientRepository();
      fakePatientRepo.storedPatients = [samplePatient];
      fakeLookupRepo = _FakeLookupRepository();
    });

    testWidgets('PatientFollowUpSlipModal renders cleanly on narrow mobile (360x640) without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FlutterErrorDetails? capturedDetails;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        capturedDetails = details;
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PatientFollowUpSlipModal(
              patient: samplePatient,
              camp: sampleCamp,
              organizationName: 'Bir Hospital Gyno Outreach',
              showProceedButton: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      FlutterError.onError = originalOnError;

      expect(capturedDetails, isNull);
      expect(find.text('PATIENT FOLLOW-UP TOKEN SLIP'), findsOneWidget);
      expect(find.text('GC-KTM01-2026-00042'), findsWidgets);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Print PDF Slip'), findsOneWidget);
      expect(find.text('Station 2 Chart'), findsOneWidget);

      // Verify Copy Button tap
      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(find.textContaining('Copied patient token ID'), findsOneWidget);
    });

    testWidgets('PatientRegistrationView renders on mobile (360x640) and desktop (1024x768) without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      FlutterErrorDetails? capturedDetails2;
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        capturedDetails2 = details;
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patientRepositoryProvider.overrideWithValue(fakePatientRepo),
            campStateProvider.overrideWith((ref) => _FakeCampViewModel(sampleCamp)),
            authStateProvider.overrideWith((ref) => _FakeAuthViewModel(sampleUser)),
          ],
          child: const MaterialApp(
            home: PatientRegistrationView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      FlutterError.onError = originalOnError;

      expect(capturedDetails2, isNull);
      expect(find.text('Patient Registration (दर्ता)'), findsOneWidget);
      expect(find.text('Demographics'), findsOneWidget);
      expect(find.textContaining('First Name * (पहिलो नाम)'), findsOneWidget);

      // Verify Desktop layout transition
      tester.view.physicalSize = const Size(1024, 768);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Register Patient & Start Clinical Form (Station 1 → 2)'), findsOneWidget);
    });

    testWidgets('Block letter grid shows immediate ACTIVE indication upon click before typing text', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patientRepositoryProvider.overrideWithValue(fakePatientRepo),
            campStateProvider.overrideWith((ref) => _FakeCampViewModel(sampleCamp)),
            authStateProvider.overrideWith((ref) => _FakeAuthViewModel(sampleUser)),
          ],
          child: const MaterialApp(
            home: PatientRegistrationView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Before tap, no ACTIVE indicator
      expect(find.text('ACTIVE'), findsNothing);

      // Tap on the First Name block grid
      final firstNameFinder = find.textContaining('First Name * (पहिलो नाम)');
      expect(firstNameFinder, findsOneWidget);
      await tester.tap(firstNameFinder);
      await tester.pump();

      // Immediately after tap (without typing any text yet), ACTIVE badge is displayed!
      expect(find.text('ACTIVE'), findsOneWidget);

      // Enter text
      await tester.enterText(find.byType(TextField).first, 'SITA');
      await tester.pump();

      // Characters are rendered in boxes
      expect(find.text('S'), findsOneWidget);
      expect(find.text('I'), findsOneWidget);
      expect(find.text('T'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
    });

    testWidgets('Father/Husband long full name renders with 24-box full width, char count and scroll buttons without clipping', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patientRepositoryProvider.overrideWithValue(fakePatientRepo),
            campStateProvider.overrideWith((ref) => _FakeCampViewModel(sampleCamp)),
            authStateProvider.overrideWith((ref) => _FakeAuthViewModel(sampleUser)),
          ],
          child: const MaterialApp(
            home: PatientRegistrationView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final husbandFieldFinder = find.textContaining("Husband's Name");
      expect(husbandFieldFinder, findsOneWidget);

      await tester.ensureVisible(husbandFieldFinder);
      await tester.pumpAndSettle();

      // Tap the husband field to focus
      await tester.tap(husbandFieldFinder);
      await tester.pump();

      // Enter 'DANDA PANI TIWARI' into focused text input
      tester.testTextInput.enterText('DANDA PANI TIWARI');
      await tester.pump();

      // Verify character count badge appears
      expect(find.text('(17 chars)'), findsOneWidget);

      // Verify characters of full name are rendered
      expect(find.text('W'), findsOneWidget);
      expect(find.text('R'), findsOneWidget);

      // Scroll buttons exist since total boxes (24) > 12
      expect(find.byIcon(Icons.chevron_left), findsWidgets);
      expect(find.byIcon(Icons.chevron_right), findsWidgets);

      // Tap right scroll chevron button
      await tester.tap(find.byIcon(Icons.chevron_right).last, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('PatientListView renders on mobile (360x640) without overflow and with responsive stats and actions', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patientRepositoryProvider.overrideWithValue(fakePatientRepo),
            campStateProvider.overrideWith((ref) => _FakeCampViewModel(sampleCamp)),
            authStateProvider.overrideWith((ref) => _FakeAuthViewModel(sampleUser)),
          ],
          child: const MaterialApp(
            home: PatientListView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Camp Patient Roll'), findsOneWidget);
      expect(find.text('Scan QR / Barcode'), findsOneWidget);
      expect(find.textContaining('Total: 1 Registered'), findsOneWidget);
      expect(find.text('Suntali Tamang'), findsOneWidget);
      expect(find.text('Slip / QR'), findsOneWidget);
      expect(find.text('Clinical Intake'), findsOneWidget);

      // Verify Desktop transition
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('ClinicalAssessmentView renders all stations on mobile (360x640) without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            patientRepositoryProvider.overrideWithValue(fakePatientRepo),
            lookupRepositoryProvider.overrideWithValue(fakeLookupRepo),
            campStateProvider.overrideWith((ref) => _FakeCampViewModel(sampleCamp)),
            authStateProvider.overrideWith((ref) => _FakeAuthViewModel(sampleUser)),
          ],
          child: MaterialApp(
            home: ClinicalAssessmentView(patient: samplePatient),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final dynamic error4_1 = tester.takeException();
      if (error4_1 != null) {
        debugPrint('TEST 4_1 ERROR: $error4_1');
      }
      expect(error4_1, isNull);
      expect(find.textContaining('Clinical Intake • Suntali Tamang'), findsOneWidget);
      expect(find.text('1. Anamnesis'), findsOneWidget);
      expect(find.text('Obstetric History (सुत्केरी तथा गर्भ विवरण)'), findsOneWidget);

      FlutterErrorDetails? capturedDetails4_2;
      final originalOnError4 = FlutterError.onError;
      FlutterError.onError = (details) {
        capturedDetails4_2 = details;
      };

      // Navigate to Station 2
      await tester.tap(find.text('2. Exam & POP'));
      await tester.pumpAndSettle();
      FlutterError.onError = originalOnError4;

      expect(capturedDetails4_2, isNull);
      expect(find.text('Uterus Inside (पाठेघर भित्रै छ?)'), findsOneWidget);
      expect(find.text('POP STAGING (Pelvic Organ Prolapse)'), findsOneWidget);

      // Navigate to Station 3
      FlutterErrorDetails? capturedDetails4_3;
      final originalOnError4_3 = FlutterError.onError;
      FlutterError.onError = (details) {
        capturedDetails4_3 = details;
      };

      await tester.ensureVisible(find.text('3. Vitals & Lab'));
      await tester.tap(find.text('3. Vitals & Lab'));
      await tester.pumpAndSettle();
      FlutterError.onError = originalOnError4_3;

      expect(capturedDetails4_3, isNull);
      expect(find.text('Rapid Point-of-Care Tests (प्रयोगशाला जाँच)'), findsOneWidget);
      expect(find.text('Systolic BP (सिस्टोलिक)'), findsOneWidget);

      // Navigate to Station 5
      await tester.ensureVisible(find.text('5. Treatment'));
      await tester.tap(find.text('5. Treatment'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Ring Pessary Fitting (रिङ पेसरी)'), findsOneWidget);

      // Navigate to Station 6 (Outtake)
      await tester.ensureVisible(find.text('6. Outtake'));
      await tester.tap(find.text('6. Outtake'));
      await tester.pumpAndSettle();
      final err6 = tester.takeException();
      if (err6 != null) {
        debugPrint('STATION 6 ERROR: $err6');
        if (err6 is FlutterError) {
          debugPrint('STATION 6 DETAILS: ${err6.diagnostics}');
        }
      }
      expect(err6, isNull);
      expect(find.text('Follow-Up Plan (पुनः जाँच योजना)'), findsOneWidget);
      expect(find.textContaining('Save Record'), findsOneWidget);
    });
  });
}
