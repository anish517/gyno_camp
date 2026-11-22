import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/duplicate_detection_service.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/lookup_item_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/repositories/lookup_repository.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';
import 'package:gyno_camp/viewmodels/master_lookup_viewmodel.dart';
import 'package:gyno_camp/viewmodels/patient_registration_viewmodel.dart';
import 'package:gyno_camp/views/patient/clinical_assessment_view.dart';

class FakeLookupRepository implements ILookupRepository {
  List<LookupItemModel> items = [
    const LookupItemModel(
      id: 'd1',
      category: 'diagnosis',
      code: 'candid',
      labelEn: 'Candid Infection',
      labelNe: 'कन्डिडा',
      isActive: true,
    ),
    const LookupItemModel(
      id: 'm1',
      category: 'medicine',
      code: 'metronidazole',
      labelEn: 'Metronidazole 400mg',
      labelNe: 'मेट्रोनिडाजोल',
      isActive: true,
    ),
    const LookupItemModel(
      id: 'h1',
      category: 'referral_hospital',
      code: 'bpkihs',
      labelEn: 'B.P. Koirala Institute of Health Sciences',
      labelNe: 'बीपी कोइराला स्वास्थ्य विज्ञान प्रतिष्ठान',
      isActive: true,
    ),
  ];

  @override
  Future<List<LookupItemModel>> getAllItems({
    String? campId,
    String? tenantId,
  }) async => items;

  @override
  Future<List<LookupItemModel>> getItemsByCategory(
    String category, {
    String? campId,
    String? tenantId,
    List<String>? allowedCampIds,
    bool activeOnly = false,
  }) async {
    return items.where((i) {
      if (i.category != category) return false;
      if (activeOnly && !i.isActive) return false;
      if (campId != null && i.campId != null && i.campId != campId)
        return false;
      if (allowedCampIds != null &&
          i.campId != null &&
          !allowedCampIds.contains(i.campId))
        return false;
      return true;
    }).toList();
  }

  @override
  Future<LookupItemModel> addItem(
    LookupItemModel item, {
    required String userId,
    required String userName,
    required String deviceId,
  }) async {
    items.add(item);
    return item;
  }

  @override
  Future<LookupItemModel> updateItem(
    LookupItemModel item, {
    required String userId,
    required String userName,
    required String deviceId,
  }) async => item;

  @override
  Future<bool> toggleItemStatus(
    String id,
    bool isActive, {
    String? campId,
    required String userId,
    required String userName,
    required String deviceId,
  }) async => true;

  @override
  Future<bool> deleteItem(
    String id, {
    String? campId,
    required String userId,
    required String userName,
    required String deviceId,
  }) async => true;

  @override
  Future<bool> restoreItemToCamp(
    String id, {
    required String campId,
    required String userId,
    required String userName,
    required String deviceId,
  }) async => true;

  @override
  Future<void> ensureDefaultsSeeded({String? tenantId}) async {}

  @override
  Future<void> purgeNonStandardItems({String? tenantId}) async {}

  @override
  Future<void> backfillSubCategories() async {}
}

class FakePatientRepository implements IPatientRepository {
  ClinicalVisitModel? lastSavedVisit;
  bool shouldThrowOnSave = false;

  @override
  Future<ClinicalVisitModel> saveClinicalVisit(
    ClinicalVisitModel visit, {
    required String createdByUserId,
    required String deviceId,
  }) async {
    if (shouldThrowOnSave) {
      throw Exception(
        'Database constraint violation: column missing or locked',
      );
    }
    lastSavedVisit = visit;
    return visit;
  }

  @override
  Future<PatientModel> registerPatient(
    PatientModel patient, {
    required String createdByUserId,
    required String createdByUserName,
    required String createdByUserRole,
    required String deviceId,
  }) async => patient;

  @override
  Future<PatientModel> updatePatient(
    PatientModel patient, {
    required String updatedByUserId,
    required String updatedByUserName,
    required String updatedByUserRole,
    required String deviceId,
  }) async => patient;

  @override
  Future<List<PatientModel>> getPatientsByCamp([
    String? campId,
    List<String>? allowedCampIds,
  ]) async => [];

  @override
  Future<PatientModel?> getPatientByPatientId(String patientId) async => null;

  @override
  Future<List<PatientModel>> searchPatients({
    required String campId,
    required String query,
  }) async => [];

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
  Future<List<ClinicalVisitModel>> getClinicalVisits(
    String patientId, {
    String? patientUuid,
  }) async => lastSavedVisit != null ? [lastSavedVisit!] : [];

  @override
  Future<ClinicalVisitModel?> getLatestClinicalVisit(
    String patientId, {
    String? patientUuid,
  }) async => lastSavedVisit;

  @override
  Future<bool> isPatientIdTaken(String patientId) async => false;

  @override
  Future<void> deletePatient(
    String patientIdOrUuid, {
    String deletedByUserId = 'usr-local',
    String deletedByUserName = 'Field Staff',
    String deletedByUserRole = 'DATA_TAKER',
    String deviceId = 'dev-local',
  }) async {}

  @override
  Future<void> deleteClinicalVisit(
    String visitId, {
    String deletedByUserId = 'usr-local',
    String deletedByUserName = 'Field Staff',
    String deletedByUserRole = 'DATA_TAKER',
    String deviceId = 'dev-local',
  }) async {}

  @override
  Future<ClinicalVisitModel> recordNurseSeenQuickVisit({
    required PatientModel patient,
    required String nurseName,
    List<String> attendingNurses = const [],
    String? treatmentLevel,
    String? notes,
    required String userId,
    required String deviceId,
  }) async => throw UnimplementedError();
}

void main() {
  group('ClinicalAssessmentView Widget Tests', () {
    late FakePatientRepository fakePatientRepo;

    final testPatient = PatientModel(
      id: 'pat-clin-01',
      patientId: 'GC-KTM01-2026-00001',
      campId: 'camp-ktm-01',
      campCode: 'KTM01',
      intakeDate: DateTime.now(),
      firstName: 'Sagar',
      surname: 'Poudel',
      age: 31,
      mobile: '9841234567',
      ward: '03',
      createdAt: DateTime.now(),
      createdByUserId: 'usr-doc',
      createdByDeviceId: 'dev-field',
    );

    setUp(() {
      fakePatientRepo = FakePatientRepository();
    });

    testWidgets(
      'Stepping to Station 6 and tapping Complete & Save Record triggers success SnackBar',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 900));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              patientRepositoryProvider.overrideWithValue(fakePatientRepo),
              lookupRepositoryProvider.overrideWithValue(
                FakeLookupRepository(),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: Builder(
                builder: (ctx) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ClinicalAssessmentView(patient: testPatient),
                        ),
                      );
                    },
                    child: const Text('Open Intake'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Intake'));
        await tester.pumpAndSettle();

        // Station 1 is rendered
        expect(
          find.text('Obstetric History (सुत्केरी तथा गर्भ विवरण)'),
          findsOneWidget,
        );

        // Station 1 -> Next
        await tester.tap(find.text('Next Station'));
        await tester.pumpAndSettle();
        expect(
          find.text('POP STAGING (Pelvic Organ Prolapse)'),
          findsOneWidget,
        );

        // Station 2 -> Next
        await tester.tap(find.text('Next Station'));
        await tester.pumpAndSettle();
        expect(
          find.text('Rapid Point-of-Care Tests (प्रयोगशाला जाँच)'),
          findsOneWidget,
        );

        // Station 3 -> Next
        await tester.tap(find.text('Next Station'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Clinical Diagnoses'), findsOneWidget);

        // Station 4 -> Next
        await tester.tap(find.text('Next Station'));
        await tester.pumpAndSettle();
        expect(find.text('Specialized Counseling (परामर्श)'), findsOneWidget);

        // Station 5 -> Next
        await tester.tap(find.text('Next Station'));
        await tester.pumpAndSettle();

        // Station 6 Outtake
        expect(find.text('Follow-Up Plan (पुनः जाँच योजना)'), findsOneWidget);
        expect(find.text('Complete & Save Record'), findsOneWidget);

        // Tap Complete & Save Record
        await tester.tap(find.text('Complete & Save Record'));
        await tester.pump();
        await tester.pumpAndSettle();

        // Verify success SnackBar was shown
        expect(
          find.text('Clinical Assessment successfully saved in local SQLite!'),
          findsOneWidget,
        );
        expect(fakePatientRepo.lastSavedVisit, isNotNull);
        expect(
          fakePatientRepo.lastSavedVisit!.patientId,
          'GC-KTM01-2026-00001',
        );

        await tester.binding.setSurfaceSize(null);
      },
    );

    testWidgets(
      'Displays error SnackBar when saving fails instead of silently aborting',
      (tester) async {
        fakePatientRepo.shouldThrowOnSave = true;
        await tester.binding.setSurfaceSize(const Size(1200, 900));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              patientRepositoryProvider.overrideWithValue(fakePatientRepo),
              lookupRepositoryProvider.overrideWithValue(
                FakeLookupRepository(),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: ClinicalAssessmentView(patient: testPatient),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Go directly to station 5 (Outtake)
        await tester.tap(find.text('6. Outtake'));
        await tester.pumpAndSettle();

        // Tap Complete & Save Record
        await tester.tap(find.text('Complete & Save Record'));
        await tester.pump();
        await tester.pumpAndSettle();

        // Verify error SnackBar is displayed with the exception details
        expect(
          find.textContaining('Database constraint violation'),
          findsOneWidget,
        );

        await tester.binding.setSurfaceSize(null);
      },
    );

    testWidgets(
      'Re-visiting patient pre-populates existing clinical visit and successfully updates changed fields',
      (tester) async {
        // 1. Setup existing visit in fake repository
        fakePatientRepo.lastSavedVisit = ClinicalVisitModel(
          id: 'vis-existing-01',
          patientId: 'GC-KTM01-2026-00001',
          campId: 'camp-ktm-01',
          visitDate: DateTime.now(),
          deliveries: 4,
          livingChildren: 3,
          abortions: 1,
          systolicBp: 130,
          diastolicBp: 85,
          pulse: 78,
          spo2: 97,
          glucose: 110,
          diagnoses: const ['POP'],
          medications: const ['Metronidazole'],
          followUpNeeded: true,
          followUpDestination: 'GynaeSupport Nurse',
          outtakeNotes: 'Original notes from earlier checkup',
          createdAt: DateTime.now(),
          createdByUserId: 'usr-doc',
        );

        await tester.binding.setSurfaceSize(const Size(1200, 900));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              patientRepositoryProvider.overrideWithValue(fakePatientRepo),
              lookupRepositoryProvider.overrideWithValue(
                FakeLookupRepository(),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: ClinicalAssessmentView(patient: testPatient),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify Station 1 text field is pre-populated with 4 deliveries
        expect(find.text('4'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);

        // Jump to Station 6 (Outtake)
        await tester.tap(find.text('6. Outtake'));
        await tester.pumpAndSettle();

        // Verify outtake notes are pre-populated
        expect(
          find.text('Original notes from earlier checkup'),
          findsOneWidget,
        );

        // Modify notes to new changed value
        await tester.enterText(
          find.widgetWithText(TextField, 'Original notes from earlier checkup'),
          'Updated clinical notes: Patient responded well to medication.',
        );
        await tester.pumpAndSettle();

        // Tap Complete & Save Record
        await tester.tap(find.text('Complete & Save Record'));
        await tester.pump();
        await tester.pumpAndSettle();

        // Verify the existing visit ID was preserved and updated
        expect(fakePatientRepo.lastSavedVisit, isNotNull);
        expect(fakePatientRepo.lastSavedVisit!.id, 'vis-existing-01');
        expect(
          fakePatientRepo.lastSavedVisit!.outtakeNotes,
          'Updated clinical notes: Patient responded well to medication.',
        );

        await tester.binding.setSurfaceSize(null);
      },
    );

    testWidgets(
      'Station 6 Outtake allows selecting partner hospital or entering manual custom follow-up hospital',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 900));

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              patientRepositoryProvider.overrideWithValue(fakePatientRepo),
              lookupRepositoryProvider.overrideWithValue(
                FakeLookupRepository(),
              ),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: Builder(
                builder: (ctx) => Scaffold(
                  body: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ClinicalAssessmentView(patient: testPatient),
                        ),
                      );
                    },
                    child: const Text('Open Clinical Assessment'),
                  ),
                ),
              ),
            ),
          ),
        );

        // Open Clinical Assessment
        await tester.tap(find.text('Open Clinical Assessment'));
        await tester.pump();
        await tester.pumpAndSettle();

        // Jump directly to Station 6 (Outtake)
        await tester.tap(find.text('6. Outtake'));
        await tester.pumpAndSettle();

        // Tap 'Follow-up Needed (थप जाँच आवश्यक)' to expand follow-up choices
        await tester.tap(find.text('Follow-up Needed (थप जाँच आवश्यक)'));
        await tester.pumpAndSettle();

        // Verify the dropdown is present with partner hospital
        expect(
          find.text(
            'Hospital: B.P. Koirala Institute of Health Sciences (अस्पताल)',
          ),
          findsOneWidget,
        );

        // Tap the dropdown to open choices
        await tester.tap(
          find.text(
            'Hospital: B.P. Koirala Institute of Health Sciences (अस्पताल)',
          ),
        );
        await tester.pumpAndSettle();

        // Verify partner hospital and Other / Custom options exist in the opened menu
        expect(
          find.text(
            'Hospital: B.P. Koirala Institute of Health Sciences (अस्पताल)',
          ),
          findsWidgets,
        );
        expect(
          find.text('Other / Custom Hospital (अन्य / म्यानुअल अस्पताल)'),
          findsOneWidget,
        );

        // Select 'Other / Custom Hospital'
        await tester.tap(
          find.text('Other / Custom Hospital (अन्य / म्यानुअल अस्पताल)').last,
        );
        await tester.pumpAndSettle();

        // Verify manual entry text field appears
        expect(find.byIcon(Icons.local_hospital_outlined), findsOneWidget);
        expect(
          find.text('Manual Hospital / Center Name (अस्पताल वा संस्थाको नाम)'),
          findsOneWidget,
        );

        // Type custom hospital name
        await tester.enterText(
          find.widgetWithText(
            TextField,
            'Manual Hospital / Center Name (अस्पताल वा संस्थाको नाम)',
          ),
          'Dhading District Hospital',
        );
        await tester.pumpAndSettle();

        // Save visit
        await tester.tap(find.text('Complete & Save Record'));
        await tester.pump();
        await tester.pumpAndSettle();

        // Verify saved follow-up destination
        expect(fakePatientRepo.lastSavedVisit, isNotNull);
        expect(
          fakePatientRepo.lastSavedVisit!.followUpDestination,
          'Dhading District Hospital',
        );

        await tester.binding.setSurfaceSize(null);
      },
    );

    testWidgets(
      'Station 1 Anamnesis dynamically displays custom Chief Complaints from Master Data (e.g. Aaa)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 1200));

        final fakeLookupRepo = FakeLookupRepository();
        fakeLookupRepo.items.add(
          const LookupItemModel(
            id: 'c1',
            category: 'chief_complaint',
            subCategory: 'Pelvic & Abdominal',
            code: 'aaa',
            labelEn: 'Aaa',
            labelNe: '',
            isActive: true,
          ),
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              patientRepositoryProvider.overrideWithValue(fakePatientRepo),
              lookupRepositoryProvider.overrideWithValue(fakeLookupRepo),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: ClinicalAssessmentView(patient: testPatient),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify custom Chief Complaint Aaa is dynamically rendered in Station 1
        expect(find.text('Aaa'), findsOneWidget);
        expect(find.text('Pelvic & Abdominal'), findsWidgets);

        // Verify duration chips on Aaa
        expect(find.text('< 1month'), findsWidgets);

        // Tap '< 1month' on Aaa
        final oneMonthChips = find.widgetWithText(ChoiceChip, '< 1month');
        await tester.tap(oneMonthChips.first);
        await tester.pumpAndSettle();

        await tester.binding.setSurfaceSize(null);
      },
    );

    testWidgets(
      'Station 3 vitals start blank, allow clearing back to null, and Station 5 surgical referral stays blank by default and can be cleared',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1200, 1000));

        final fakeLookupRepo = FakeLookupRepository();
        fakeLookupRepo.items.addAll(const [
          LookupItemModel(
            id: 'h2',
            category: 'referral_hospital',
            code: 'model_hosp',
            labelEn: 'Model Hosp',
            labelNe: 'Model Hosp',
            isActive: true,
          ),
          LookupItemModel(
            id: 'h3',
            category: 'referral_hospital',
            code: 'scheer',
            labelEn: 'Scheer Memorial',
            labelNe: 'Scheer Memorial',
            isActive: true,
          ),
        ]);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              patientRepositoryProvider.overrideWithValue(fakePatientRepo),
              lookupRepositoryProvider.overrideWithValue(fakeLookupRepo),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: ClinicalAssessmentView(patient: testPatient),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Jump to Station 3 (Vitals & Lab)
        await tester.tap(find.text('3. Vitals & Lab'));
        await tester.pumpAndSettle();

        // Must NOT show hardcoded 120 / 80 / 78 / 98 / 110 defaults
        expect(find.text('120'), findsNothing);
        expect(find.text('80'), findsNothing);
        expect(find.text('78'), findsNothing);
        expect(find.text('98'), findsNothing);
        expect(find.text('110'), findsNothing);

        // Enter a BP value then clear it back to blank
        final systolicField = find.widgetWithText(
          TextField,
          'Systolic BP (सिस्टोलिक)',
        );
        await tester.enterText(systolicField, '135');
        await tester.pumpAndSettle();
        await tester.enterText(systolicField, '');
        await tester.pumpAndSettle();

        // Jump to Station 5 (Treatment)
        await tester.tap(find.text('5. Treatment'));
        await tester.pumpAndSettle();

        // Surgical Referral Hospital must be blank by default (NOT Model Hosp)
        expect(find.text('Model Hosp'), findsNothing);
        expect(find.text('Select referral hospital'), findsOneWidget);

        // Select Model Hosp, then clear it back to blank
        final referralDropdown = find.byKey(
          const ValueKey('surgical_referral_null'),
        );
        expect(referralDropdown, findsOneWidget);
        await tester.tap(referralDropdown);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Model Hosp').last);
        await tester.pumpAndSettle();
        expect(find.text('Model Hosp'), findsOneWidget);

        // Re-open dropdown and clear selection
        await tester.tap(
          find.byKey(const ValueKey('surgical_referral_Model Hosp')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.text('None / Clear Referral (कुनै सिफारिस छैन)').last,
        );
        await tester.pumpAndSettle();
        expect(find.text('Model Hosp'), findsNothing);

        // Jump to Station 6 and save — both vitals and surgicalReferral must be saved as null
        await tester.tap(find.text('6. Outtake'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Complete & Save Record'));
        await tester.pumpAndSettle();

        expect(fakePatientRepo.lastSavedVisit, isNotNull);
        expect(fakePatientRepo.lastSavedVisit!.systolicBp, isNull);
        expect(fakePatientRepo.lastSavedVisit!.surgicalReferral, isNull);

        await tester.binding.setSurfaceSize(null);
      },
    );
  });
}
