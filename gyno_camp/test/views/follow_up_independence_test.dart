import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';
import 'package:gyno_camp/viewmodels/patient_registration_viewmodel.dart';
import 'package:gyno_camp/views/patient/patient_follow_up_form_view.dart';
import 'package:material_ui/material_ui.dart';

class _InMemoryPatientRepo extends Fake implements IPatientRepository {
  final List<ClinicalVisitModel> visits;

  _InMemoryPatientRepo({List<ClinicalVisitModel>? initialVisits})
      : visits = List<ClinicalVisitModel>.from(initialVisits ?? const []);

  @override
  Future<List<ClinicalVisitModel>> getClinicalVisits(
    String patientId, {
    String? patientUuid,
  }) async {
    return List<ClinicalVisitModel>.from(visits);
  }

  @override
  Future<ClinicalVisitModel?> getLatestClinicalVisit(
    String patientId, {
    String? patientUuid,
  }) async {
    return visits.isEmpty ? null : visits.first;
  }

  @override
  Future<ClinicalVisitModel> saveClinicalVisit(
    ClinicalVisitModel visit, {
    required String createdByUserId,
    required String deviceId,
  }) async {
    final assignedId = visit.id.isNotEmpty ? visit.id : 'vis-fu-${visits.length + 1}';
    final saved = visit.copyWith(id: assignedId);
    final existingIdx = visits.indexWhere((v) => v.id == assignedId);
    if (existingIdx >= 0) {
      visits[existingIdx] = saved;
    } else {
      visits.insert(0, saved);
    }
    return saved;
  }
}

void main() {
  final testCamp = CampModel(
    id: 'camp-fu-ind-01',
    campCode: '111',
    name: 'Budhanilkantha Camp',
    province: 'Bagmati',
    district: 'Kathmandu',
    municipality: 'Budhanilkantha',
    ward: '07',
    venue: 'Health Post',
    startDate: DateTime(2026, 11, 25),
    endDate: DateTime(2026, 11, 28),
    doctorNames: const ['Dr. Anish Tiwari (NMC: 12345)'],
    createdAt: DateTime(2026, 11, 20),
  );

  final testPatient = PatientModel(
    id: 'pat-maya-100',
    patientId: '00100',
    campId: 'camp-fu-ind-01',
    campCode: '111',
    intakeDate: DateTime(2026, 11, 25),
    firstName: 'MAYA',
    surname: 'GURUNG',
    age: 34,
    maritalStatus: 'married',
    mobile: '9841000100',
    province: 'Bagmati',
    district: 'Kathmandu',
    municipality: 'Budhanilkantha',
    ward: '07',
    reasonsForVisit: const ['discharge and or itching', 'pain'],
    treatmentLevel: 'gyno_checkup',
    createdAt: DateTime(2026, 11, 25),
    createdByUserId: 'usr-1',
    createdByDeviceId: 'dev-1',
  );

  final initialClinicalIntake = ClinicalVisitModel(
    id: 'vis-initial-100',
    patientId: '00100',
    campId: 'camp-fu-ind-01',
    visitDate: DateTime(2026, 11, 25, 10, 0),
    deliveries: 3,
    livingChildren: 3,
    abortions: 0,
    uterusInside: false,
    cervixRemarks: 'EROSION',
    popAnteriorStage: 2,
    popMiddleStage: 3,
    popPosteriorStage: 1,
    highestPopStage: 3,
    systolicBp: 152,
    diastolicBp: 94,
    pulse: 88,
    spo2: 98,
    glucose: 138,
    urineTest: 'pos',
    pregnancyTest: 'neg',
    diagnoses: const ['POP'],
    medications: const ['Metronidazole'],
    pessaryType: 'ring',
    pessarySize: '65',
    treatmentLevel: 'gyno_checkup',
    attendingDoctorNames: const ['Dr. Anish Tiwari'],
    primaryDoctorName: 'Dr. Anish Tiwari',
    isFollowUp: false,
    createdAt: DateTime(2026, 11, 25, 10, 0),
    createdByUserId: 'usr-1',
  );

  group('PatientFollowUpFormView Independence from Clinical Intake', () {
    testWidgets(
      'New Follow-Up starts clean without pre-filling Clinical Intake vitals/stages and saves without copying Intake fields',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final fakeRepo = _InMemoryPatientRepo(
          initialVisits: [initialClinicalIntake],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              patientRepositoryProvider.overrideWithValue(fakeRepo),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: PatientFollowUpFormView(
                patient: testPatient,
                camp: testCamp,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Intake vitals (152 / 94 / 88 / 138) must NOT be pre-filled into new Follow-Up fields
        expect(find.text('152'), findsNothing);
        expect(find.text('94'), findsNothing);
        expect(find.text('138'), findsNothing);

        // Save new Follow-Up with only its own observation
        final saveBtn = find.text('Save Follow-Up Record (फलो-अप सुरक्षित गर्नुहोस्)');
        await tester.ensureVisible(saveBtn);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        expect(fakeRepo.visits.length, 2);
        final savedFollowUp = fakeRepo.visits.firstWhere((v) => v.isFollowUp);
        final untouchedIntake = fakeRepo.visits.firstWhere((v) => !v.isFollowUp);

        // Follow-Up has strictly its own blank/new values — zero silent copy from Intake
        expect(savedFollowUp.isFollowUp, isTrue);
        expect(savedFollowUp.systolicBp, isNull);
        expect(savedFollowUp.diastolicBp, isNull);
        expect(savedFollowUp.highestPopStage, isNull);
        expect(savedFollowUp.deliveries, isNull);
        expect(savedFollowUp.cervixRemarks, isNull);
        expect(savedFollowUp.treatmentLevel, isNull);
        expect(savedFollowUp.diagnoses, isEmpty);
        expect(savedFollowUp.pessaryType, isNull);

        // Initial Clinical Intake remains 100% untouched
        expect(untouchedIntake.id, 'vis-initial-100');
        expect(untouchedIntake.highestPopStage, 3);
        expect(untouchedIntake.systolicBp, 152);
        expect(untouchedIntake.diagnoses, equals(['POP']));
      },
    );

    testWidgets(
      'Editing an existing Follow-Up populates its own saved fields and updates in place without touching Clinical Intake',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final existingFollowUp = ClinicalVisitModel(
          id: 'vis-fu-existing-01',
          patientId: '00100',
          campId: 'camp-fu-ind-01',
          visitDate: DateTime(2026, 11, 27, 9, 30),
          anamnesisComplaints: const {
            'reasons': ['Routine follow-up checkup (नियमित जाँच)'],
            'new_issues': 'RING SITTING WELL',
          },
          systolicBp: 118,
          diastolicBp: 76,
          isFollowUp: true,
          followUpNotes: 'RING SITTING WELL',
          outtakeNotes: 'CONTINUE PELVIC EXERCISES',
          createdAt: DateTime(2026, 11, 27, 9, 30),
          createdByUserId: 'usr-1',
        );

        final fakeRepo = _InMemoryPatientRepo(
          initialVisits: [existingFollowUp, initialClinicalIntake],
        );

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              patientRepositoryProvider.overrideWithValue(fakeRepo),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              home: PatientFollowUpFormView(
                patient: testPatient,
                camp: testCamp,
                initialFollowUpVisit: existingFollowUp,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Edit Follow-Up Visit Assessment'), findsOneWidget);
        expect(find.text('118'), findsOneWidget);
        expect(find.text('76'), findsOneWidget);
        expect(find.text('RING SITTING WELL'), findsOneWidget);

        final updateBtn = find.text('Update Follow-Up Record (फलो-अप अद्यावधिक गर्नुहोस्)');
        await tester.ensureVisible(updateBtn);
        await tester.tap(updateBtn);
        await tester.pumpAndSettle();

        // Still 2 visits total (updated Follow-Up in place, did not duplicate or touch Intake)
        expect(fakeRepo.visits.length, 2);
        final initialAfterEdit = await fakeRepo.getInitialClinicalVisit('00100');
        final latestFuAfterEdit = await fakeRepo.getLatestFollowUpVisit('00100');
        expect(initialAfterEdit?.id, 'vis-initial-100');
        expect(initialAfterEdit?.systolicBp, 152);
        expect(latestFuAfterEdit?.id, 'vis-fu-existing-01');
        expect(latestFuAfterEdit?.systolicBp, 118);
      },
    );
  });
}
