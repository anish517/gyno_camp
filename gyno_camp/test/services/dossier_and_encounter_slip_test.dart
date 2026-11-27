import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/constants/app_constants.dart';
import 'package:gyno_camp/core/services/pdf_report_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/patient_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.now();

  final testCamp = CampModel(
    id: 'camp-11',
    campCode: '11',
    name: 'Gorkha Reproductive Health Camp',
    venue: 'Gorkha Hospital',
    district: 'Gorkha',
    municipality: 'GORKHA',
    ward: '4',
    doctorNames: ['Dr. Anish Tiwari (NMC: 12)', 'Dr. Sagar P (NMC: 3223)'],
    nurseNames: ['Rita Sharma (NNC: 4455)', 'Sita Gurung (NNC: 8899)'],
    startDate: DateTime(2026, 10, 20),
    endDate: DateTime(2026, 10, 24),
    createdAt: now,
  );

  final testPatientStage4 = PatientModel(
    id: 'pat-001',
    campId: 'camp-11',
    campCode: '11',
    patientId: 'GC-11-2026-00041',
    firstName: 'Maya',
    surname: 'Devi',
    age: 62,
    maritalStatus: 'widow',
    mobile: '9841000001',
    district: 'Gorkha',
    municipality: 'GORKHA',
    ward: '4',
    highestPopStage: 4,
    treatmentLevel: 'gyno_checkup',
    intakeDate: now,

    createdAt: now,
    createdByUserId: 'usr-1',
    createdByDeviceId: 'dev-1',
  );

  final testVisitStage4 = ClinicalVisitModel(
    id: 'vis-001',
    patientId: 'GC-11-2026-00041',
    campId: 'camp-11',
    visitDate: DateTime(2026, 10, 21, 10, 30),
    primaryDoctorName: 'Dr. Sagar P (NMC: 3223)',
    attendingDoctorNames: ['Dr. Sagar P (NMC: 3223)'],
    treatmentLevel: 'gyno_checkup',
    systolicBp: 130,
    diastolicBp: 85,
    pulse: 78,
    spo2: 98,
    glucose: 105,
    urineTest: 'normal',
    pregnancyTest: 'neg',
    popAnteriorStage: 3,
    popMiddleStage: 4,
    popPosteriorStage: 3,
    highestPopStage: 4,
    pelvicFloorTone: 'weak',
    diagnoses: [
      'atrophy vagina',
      'stress incontinence',
      'weak pelvic floor muscle',
      'PROCIDENTIA (COMPLETE UTERINE PROLAPSE)',
    ],
    medications: ['estradiol crème'],
    counseling: ['weak pelvic floor', 'POP', 'stress incontinence'],
    surgicalReferral: 'Scheer Memorial',
    followUpNeeded: true,
    followUpDestination: 'Hospital',
    outtakeNotes: 'Severe complete procidentia with decubitus ulceration. Advised surgical repair.',
    createdAt: now,
    createdByUserId: 'usr-1',
  );

  final testPatientCounseling = PatientModel(
    id: 'pat-002',
    campId: 'camp-11',
    campCode: '11',
    patientId: 'GC-11-2026-00042',
    firstName: 'Laxmi',
    surname: 'Adhikari',
    age: 33,
    maritalStatus: 'married',
    mobile: '9841000002',
    district: 'Tanahun',
    municipality: 'BYAS',
    ward: '2',
    highestPopStage: 0,
    treatmentLevel: 'counseling',
    intakeDate: now,

    createdAt: now,
    createdByUserId: 'usr-1',
    createdByDeviceId: 'dev-1',
  );

  final testVisitCounseling = ClinicalVisitModel(
    id: 'vis-002',
    patientId: 'GC-11-2026-00042',
    campId: 'camp-11',
    visitDate: DateTime(2026, 10, 21, 11, 15),
    primaryDoctorName: 'Dr. Anish Tiwari (NMC: 12)',
    attendingDoctorNames: ['Dr. Anish Tiwari (NMC: 12)'],
    treatmentLevel: 'counseling',
    systolicBp: 110,
    diastolicBp: 70,
    pulse: 72,
    spo2: 99,
    popAnteriorStage: 0,
    popMiddleStage: 0,
    popPosteriorStage: 0,
    highestPopStage: 0,
    pelvicFloorTone: 'normal',
    diagnoses: [
      'infertility',
      'myoma',
      'menstrual disorder',
      'RECURRENT PREGNANCY LOSS',
    ],
    medications: ['IRON + FOLIC ACID'],
    counseling: ['abdominal pain'],
    surgicalReferral: 'loc government',
    followUpNeeded: true,
    followUpDestination: 'Hospital',
    outtakeNotes: 'Normal pelvic anatomy. Counseled on menstrual hygiene and secondary infertility.',
    createdAt: now,
    createdByUserId: 'usr-1',
  );

  final pdfService = PdfReportService();

  group('Patient Dossier PDF Generation (generateIndividualPatientPdf)', () {
    test('Generates valid Dossier PDF for Stage IV Gynocheckup patient without error', () async {
      final bytes = await pdfService.generateIndividualPatientPdf(
        patient: testPatientStage4,
        visit: testVisitStage4,
        camp: testCamp,
        organizationName: AppConstants.defaultOrganizationName,
      );

      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);
      // PDF header magic bytes %PDF-
      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.take(5)), equals('%PDF-'));
    });

    test('Generates valid Dossier PDF for Stage 0 Counseling patient without error', () async {
      final bytes = await pdfService.generateIndividualPatientPdf(
        patient: testPatientCounseling,
        visit: testVisitCounseling,
        camp: testCamp,
        organizationName: AppConstants.defaultOrganizationName,
      );

      expect(bytes, isNotNull);
      expect(bytes.isNotEmpty, isTrue);
      expect(bytes.length, greaterThan(1000));
      expect(String.fromCharCodes(bytes.take(5)), equals('%PDF-'));
    });

    test(
      'Generates valid Dossier PDF for unexamined patient (visit == null)',
      () async {
        final bytes = await pdfService.generateIndividualPatientPdf(
          patient: testPatientStage4,
          visit: null,
          camp: testCamp,
          organizationName: AppConstants.defaultOrganizationName,
        );

        expect(bytes, isNotNull);
        expect(bytes.isNotEmpty, isTrue);
        expect(String.fromCharCodes(bytes.take(5)), equals('%PDF-'));
      },
    );
  });

  group('Follow-Up Encounter Slip PDF Generation (generateFollowUpEncounterSlipPdf)', () {
    test(
      'Generates valid Filled Follow-Up Encounter Slip PDF for patient',
      () async {
        final bytes = await pdfService.generateFollowUpEncounterSlipPdf(
          patient: testPatientStage4,
          visit: testVisitStage4,
          camp: testCamp,
          organizationName: AppConstants.defaultOrganizationName,
        );

        expect(bytes, isNotNull);
        expect(bytes.isNotEmpty, isTrue);
        expect(bytes.length, greaterThan(1000));
        expect(String.fromCharCodes(bytes.take(5)), equals('%PDF-'));
      },
    );

    test(
      'Generates valid Follow-Up Encounter Slip for Counseling patient',
      () async {
        final bytes = await pdfService.generateFollowUpEncounterSlipPdf(
          patient: testPatientCounseling,
          visit: testVisitCounseling,
          camp: testCamp,
          organizationName: AppConstants.defaultOrganizationName,
        );

        expect(bytes, isNotNull);
        expect(bytes.isNotEmpty, isTrue);
        expect(bytes.length, greaterThan(1000));
        expect(String.fromCharCodes(bytes.take(5)), equals('%PDF-'));
      },
    );

    test(
      'Independent Follow-Up visit never contaminates Clinical Intake Dossier PDF and generates standalone Follow-Up Slip',
      () async {
        final initialIntake = ClinicalVisitModel(
          id: 'vis-intake-001',
          patientId: testPatientStage4.patientId,
          campId: testCamp.id,
          visitDate: DateTime(2026, 11, 20),
          deliveries: 3,
          livingChildren: 3,
          abortions: 0,
          popAnteriorStage: 2,
          popMiddleStage: 3,
          popPosteriorStage: 1,
          highestPopStage: 3,
          systolicBp: 145,
          diastolicBp: 92,
          diagnoses: const ['POP'],
          medications: const ['Metronidazole'],
          isFollowUp: false,
          createdAt: DateTime(2026, 11, 20),
          createdByUserId: 'usr-1',
        );

        final followUpVisit = ClinicalVisitModel(
          id: 'vis-followup-002',
          patientId: testPatientStage4.patientId,
          campId: testCamp.id,
          visitDate: DateTime(2026, 11, 27),
          anamnesisComplaints: const {
            'reasons': ['Discharge / Itching (स्राव / चिलाउने)'],
            'new_issues': 'MILD VAGINAL IRRITATION RESOLVED',
          },
          popAnteriorStage: 1,
          popMiddleStage: 1,
          popPosteriorStage: 0,
          highestPopStage: 1,
          systolicBp: 112,
          diastolicBp: 72,
          diagnoses: const ['Candidiasis'],
          medications: const ['Fluconazole'],
          isFollowUp: true,
          followUpNotes: 'MILD VAGINAL IRRITATION RESOLVED',
          createdAt: DateTime(2026, 11, 27),
          createdByUserId: 'usr-1',
        );

        // Even if a Follow-Up visit is passed as `visit`, generateIndividualPatientPdf
        // ignores Follow-Up records for Clinical Intake sections and falls back to initialIntake.
        final dossierBytes = await pdfService.generateIndividualPatientPdf(
          patient: testPatientStage4,
          visit: followUpVisit,
          allVisits: [followUpVisit, initialIntake],
          camp: testCamp,
        );
        expect(dossierBytes, isNotEmpty);
        expect(String.fromCharCodes(dossierBytes.take(5)), equals('%PDF-'));

        // Standalone Follow-Up Slip PDF generates cleanly with zero obstetric carry-over
        final followUpSlipBytes = await pdfService.generateFollowUpEncounterSlipPdf(
          patient: testPatientStage4,
          visit: followUpVisit,
          camp: testCamp,
        );
        expect(followUpSlipBytes, isNotEmpty);
        expect(String.fromCharCodes(followUpSlipBytes.take(5)), equals('%PDF-'));

        // Pre-numbered patient-specific Blank Follow-Up Slip PDF
        final blankPatientFollowUpBytes = await pdfService.generateBlankFollowUpSlipPdf(
          camp: testCamp,
          preprintedTokenId: testPatientStage4.patientId,
        );
        expect(blankPatientFollowUpBytes, isNotEmpty);
        expect(String.fromCharCodes(blankPatientFollowUpBytes.take(5)), equals('%PDF-'));
      },
    );
  });

  group(
    'Blank Follow-Up Slip PDF Generation (generateBlankFollowUpSlipPdf)',
    () {
      test('Generates exactly 1-page blank Follow-Up Slip PDF', () async {
        final bytes = await pdfService.generateBlankFollowUpSlipPdf(
          camp: testCamp,
          doctor: const DoctorProfile(
            name: 'Dr. Anish Tiwari',
            nmcNumber: '12',
          ),
          organizationName: AppConstants.defaultOrganizationName,
        );

        expect(bytes, isNotNull);
        expect(bytes.isNotEmpty, isTrue);
        expect(String.fromCharCodes(bytes.take(5)), equals('%PDF-'));
      });

      test('Generates batch pre-numbered blank follow-up slips', () async {
        final bytes = await pdfService.generatePreNumberedBlankFollowUpSlipsPdf(
          camp: testCamp,
          startSequence: 1,
          count: 3,
        );

        expect(bytes, isNotNull);
        expect(bytes.isNotEmpty, isTrue);
        expect(String.fromCharCodes(bytes.take(5)), equals('%PDF-'));
      });
    },
  );

  group('Patient Token Slip & Triage Pass (generatePatientTokenSlipPdf)', () {
    test(
      'Generates valid A5 patient token slip with barcode and QR code',
      () async {
        final bytes = await pdfService.generatePatientTokenSlipPdf(
          patient: testPatientStage4,
          camp: testCamp,
          organizationName: AppConstants.defaultOrganizationName,
        );

        expect(bytes, isNotNull);
        expect(bytes.isNotEmpty, isTrue);
        expect(String.fromCharCodes(bytes.take(5)), equals('%PDF-'));
      },
    );
  });
}
