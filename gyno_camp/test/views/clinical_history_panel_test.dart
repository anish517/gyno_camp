import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/utils/nepali_date_helper.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';
import 'package:gyno_camp/views/patient/clinical_history_panel.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nepali_utils/nepali_utils.dart';

class _StubPatientRepo implements IPatientRepository {
  final List<ClinicalVisitModel> visits;
  _StubPatientRepo(this.visits);

  @override
  Future<List<ClinicalVisitModel>> getClinicalVisits(String patientId, {String? patientUuid}) async => visits;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('ClinicalHistoryPanel labels Intake Date, Visit Date source, and all 6 Station Dates without overflow', (tester) async {
    final camp = CampModel(
      id: 'camp-1',
      campCode: '0007',
      name: '1st testing camp',
      district: 'Dhankuta',
      municipality: 'Dhankuta Mun',
      ward: '05',
      venue: 'Hosp Hall',
      startDate: NepaliDateHelper.toEnglish(NepaliDateTime(2083, 4, 10)),
      endDate: NepaliDateHelper.toEnglish(NepaliDateTime(2083, 4, 16)),
      createdAt: DateTime(2026, 7, 26),
    );
    final patient = PatientModel(
      id: 'pat-1',
      patientId: 'GC-0007-2026-00012',
      campId: camp.id,
      campCode: camp.campCode,
      intakeDate: NepaliDateHelper.toEnglish(NepaliDateTime(2083, 4, 10)),
      firstName: 'KAMALA',
      surname: 'RAI',
      age: 58,
      mobile: '9842167305',
      ward: '05',
      district: 'Dhankuta',
      municipality: 'Dhankuta Mun',
      createdByUserId: 'u1',
      createdByDeviceId: 'd1',
      createdAt: DateTime(2026, 7, 26),
    );
    final visit = ClinicalVisitModel(
      id: 'vis-1',
      patientId: patient.patientId,
      campId: camp.id,
      visitDate: NepaliDateHelper.toEnglish(NepaliDateTime(2083, 4, 15)),
      anamnesisDate: NepaliDateHelper.toEnglish(NepaliDateTime(2083, 4, 11)),
      examDate: NepaliDateHelper.toEnglish(NepaliDateTime(2083, 4, 12)),
      labTestDate: NepaliDateHelper.toEnglish(NepaliDateTime(2083, 4, 13)),
      conclusionDate: NepaliDateHelper.toEnglish(NepaliDateTime(2083, 4, 14)),
      treatmentDate: NepaliDateHelper.toEnglish(NepaliDateTime(2083, 4, 15)),
      outtakeDate: NepaliDateHelper.toEnglish(NepaliDateTime(2083, 4, 16)),
      diagnoses: const ['stress incontinence'],
      medications: const ['estradiol crème', 'Calcium + Vit D3'],
      customMedication: 'Calcium + Vit D3',
      createdByUserId: 'u1',
      createdAt: DateTime(2026, 7, 26),
    );

    await tester.binding.setSurfaceSize(const Size(1100, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClinicalHistoryPanel(
            patient: patient,
            camp: camp,
            orgName: 'Women for Women',
            repo: _StubPatientRepo([visit]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Clinical History & Dossier'), findsOneWidget);
    expect(find.text('1st testing camp'), findsOneWidget);
    // Patient name and ID appear once in left sidebar (not duplicated in top bar)
    expect(find.text('KAMALA RAI'), findsOneWidget);
    expect(find.text('GC-0007-2026-00012'), findsOneWidget);
    expect(find.text('Dhankuta, Ward 05'), findsNothing);
    expect(find.text('Age 58'), findsNothing);

    expect(find.textContaining('Intake Date: 2083-04-10 BS', findRichText: true), findsOneWidget);
    expect(find.textContaining('1st Visit (Treatment)'), findsOneWidget);
    expect(find.text('Visit Date (Treatment Date): 2083-04-15 BS (2026-07-31 AD)'), findsOneWidget);
    expect(find.text('Station Dates (BS / AD):'), findsOneWidget);
    expect(find.textContaining('1. Anamnesis: 2083-04-11 BS'), findsOneWidget);
    expect(find.textContaining('2. Exam: 2083-04-12 BS'), findsOneWidget);
    expect(find.textContaining('3. Lab Test: 2083-04-13 BS'), findsOneWidget);
    expect(find.textContaining('4. Conclusion: 2083-04-14 BS'), findsOneWidget);
    expect(find.textContaining('5. Treatment: 2083-04-15 BS'), findsOneWidget);
    expect(find.textContaining('6. Outtake: 2083-04-16 BS'), findsOneWidget);
    expect(find.text('estradiol crème'), findsOneWidget);
    expect(find.text('Calcium + Vit D3'), findsNothing);
    expect(find.text('Other Medication: Calcium + Vit D3'), findsOneWidget);
    expect(find.textContaining('Rx:'), findsNothing);
    expect(find.text('Download Slip'), findsNothing);
    expect(find.text('Full Clinical Dossier (PDF)'), findsOneWidget);
  });

  testWidgets('ClinicalHistoryPanel mobile layout renders Encounter and Profile tabs without overflow', (tester) async {
    final camp = CampModel(
      id: 'camp-m',
      campCode: '0007',
      name: '1st testing camp',
      district: 'Dhankuta',
      municipality: 'Dhankuta Mun',
      ward: '05',
      venue: 'Hosp Hall',
      startDate: NepaliDateHelper.toEnglish(NepaliDateTime(2083, 4, 10)),
      endDate: NepaliDateHelper.toEnglish(NepaliDateTime(2083, 4, 16)),
      createdAt: DateTime(2026, 7, 26),
    );
    final patient = PatientModel(
      id: 'pat-m',
      patientId: 'GC-0007-2026-00012',
      campId: camp.id,
      campCode: camp.campCode,
      intakeDate: NepaliDateHelper.toEnglish(NepaliDateTime(2083, 4, 10)),
      firstName: 'KAMALA',
      surname: 'RAI',
      age: 58,
      mobile: '9842167305',
      ward: '05',
      district: 'Dhankuta',
      municipality: 'Dhankuta Mun',
      createdByUserId: 'u1',
      createdByDeviceId: 'd1',
      createdAt: DateTime(2026, 7, 26),
    );
    final visit = ClinicalVisitModel(
      id: 'vis-m',
      patientId: patient.patientId,
      campId: camp.id,
      visitDate: NepaliDateHelper.toEnglish(NepaliDateTime(2083, 4, 15)),
      anamnesisDate: NepaliDateHelper.toEnglish(NepaliDateTime(2083, 4, 11)),
      treatmentDate: NepaliDateHelper.toEnglish(NepaliDateTime(2083, 4, 15)),
      diagnoses: const ['stress incontinence'],
      medications: const ['estradiol crème'],
      createdByUserId: 'u1',
      createdAt: DateTime(2026, 7, 26),
    );

    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClinicalHistoryPanel(
            patient: patient,
            camp: camp,
            orgName: 'Women for Women',
            repo: _StubPatientRepo([visit]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Clinical History & Dossier'), findsOneWidget);
    expect(find.text('1st testing camp'), findsOneWidget);
    expect(find.text('KAMALA RAI'), findsNothing);
    expect(find.text('Slip'), findsNothing);
    expect(find.text('Download Slip'), findsNothing);
    expect(find.text('Full Dossier (PDF)'), findsOneWidget);
    expect(find.text('Visit Date (Treatment Date): 2083-04-15 BS (2026-07-31 AD)'), findsOneWidget);

    await tester.tap(find.text('Patient Profile & History'));
    await tester.pumpAndSettle();

    expect(find.text('KAMALA RAI'), findsOneWidget);
    expect(find.text('GC-0007-2026-00012'), findsOneWidget);
    expect(find.text('Dhankuta, Ward 05'), findsNothing);
    expect(find.text('Age 58'), findsNothing);
    expect(find.textContaining('Intake Date: 2083-04-10 BS', findRichText: true), findsOneWidget);
    expect(find.textContaining('1st Visit (Treatment)'), findsOneWidget);
  });
}
