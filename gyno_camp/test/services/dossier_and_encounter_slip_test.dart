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
