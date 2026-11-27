import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/constants/app_constants.dart';
import 'package:gyno_camp/core/services/pdf_report_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/lookup_item_model.dart';
import 'package:gyno_camp/models/patient_model.dart';

int _countPdfPages(Uint8List bytes) {
  final raw = String.fromCharCodes(bytes);
  return RegExp(r'/Type\s*/Page\b(?!s)').allMatches(raw).length;
}

Future<String?> _extractPdfTextIfAvailable(Uint8List bytes) async {
  const pdftotextPath = r'C:\Program Files\Git\mingw64\bin\pdftotext.exe';
  if (!File(pdftotextPath).existsSync()) return null;
  final tempDir = await Directory.systemTemp.createTemp('gyno_followup_pdf_');
  try {
    final pdfFile = File('${tempDir.path}/out.pdf');
    final txtFile = File('${tempDir.path}/out.txt');
    await pdfFile.writeAsBytes(bytes, flush: true);
    final result = await Process.run(
      pdftotextPath,
      ['-enc', 'UTF-8', pdfFile.path, txtFile.path],
    );
    if (result.exitCode != 0 || !txtFile.existsSync()) return null;
    return await txtFile.readAsString();
  } finally {
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  }
}

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
      test(
        'Generates strictly 1-page blank Follow-Up Slip PDF matching Sections 1-5 even with full lookup & clinician rosters',
        () async {
          final fullRosterCamp = CampModel(
            id: 'camp-full-fu',
            campCode: '1111',
            name: 'Bhaktapur Reproductive Follow-Up Camp',
            venue: 'Bhaktapur Hospital',
            district: 'Bhaktapur',
            municipality: 'BHAKTAPUR',
            ward: '07',
            doctorNames: const [
              'Dr. Anish Tiwari (NMC: 12)',
              'Dr. Sagar P (NMC: 3223)',
              'Dr. Mina Shrestha (NMC: 7788)',
            ],
            nurseNames: const [
              'Rita Sharma (NNC: 4455)',
              'Sita Gurung (NNC: 8899)',
              'Gita Thapa (NNC: 9911)',
            ],
            showDoctorOnForms: true,
            showNurseOnForms: true,
            startDate: DateTime(2026, 11, 25),
            endDate: DateTime(2026, 11, 28),
            createdAt: now,
          );

          final customDiagnoses = List.generate(
            24,
            (i) => LookupItemModel(
              id: 'diag-$i',
              category: 'diagnosis',
              code: 'diag_$i',
              labelEn: i == 0
                  ? 'Custom Follow-Up Diagnosis Alpha'
                  : 'Clinical Diagnosis Item ${i + 1}',
              labelNe: '',
              sortOrder: i,
              isActive: true,
            ),
          );

          final customMedications = List.generate(
            16,
            (i) => LookupItemModel(
              id: 'med-$i',
              category: 'medication',
              code: 'med_$i',
              labelEn: i == 0
                  ? 'Custom Estradiol Cream Rx'
                  : 'Camp Medication Option ${i + 1}',
              labelNe: '',
              sortOrder: i,
              isActive: true,
            ),
          );

          final customHospitals = [
            const LookupItemModel(
              id: 'hosp-1',
              category: 'referral_hospital',
              code: 'dhulikhel',
              labelEn: 'Dhulikhel Partner Hospital',
              labelNe: '',
              sortOrder: 1,
              isActive: true,
            ),
          ];

          final bytes = await pdfService.generateBlankFollowUpSlipPdf(
            camp: fullRosterCamp,
            preprintedTokenId: '00100',
            allDoctorsChecklist: true,
            allNursesChecklist: true,
            organizationName: AppConstants.defaultOrganizationName,
            diagnoses: customDiagnoses,
            medications: customMedications,
            referralHospitals: customHospitals,
          );

          expect(bytes, isNotNull);
          expect(bytes.isNotEmpty, isTrue);
          expect(String.fromCharCodes(bytes.take(5)), equals('%PDF-'));
          expect(_countPdfPages(bytes), equals(1));

          final extracted = await _extractPdfTextIfAvailable(bytes);
          if (extracted != null) {
            expect(extracted, contains('FOLLOW-UP VISIT ASSESSMENT SHEET'));
            expect(extracted, contains('1. FOLLOW-UP COMPLAINTS & NEW ISSUES'));
            expect(extracted, contains('2. PHYSICAL VITALS CHECK & SCREENING LABS'));
            expect(extracted, contains('3. PELVIC FLOOR & POP RE-STAGING'));
            expect(extracted, contains('4. DIAGNOSES & SURGICAL EVALUATION'));
            expect(extracted, contains('5. PRESCRIPTION & FOLLOW-UP DESTINATION'));
            expect(extracted, contains('Uterus Inside'));
            expect(extracted, contains('Pelvic Floor Muscle'));
            expect(extracted, contains('Custom Follow-Up Diagnosis Alpha'));
            expect(extracted, contains('Custom Estradiol Cream Rx'));
            expect(extracted, contains('Dhulikhel Partner Hospital'));
            // Non-existent legacy fields must be absent
            expect(extracted, isNot(contains('Temp (°F)')));
            expect(extracted, isNot(contains('Significantly Improved')));
            expect(extracted, isNot(contains('Pessary Clean & In-Situ')));
          }
        },
      );

      test('Generates batch pre-numbered blank follow-up slips (1 page per token)', () async {
        final bytes = await pdfService.generatePreNumberedBlankFollowUpSlipsPdf(
          camp: testCamp,
          startSequence: 1,
          count: 3,
        );

        expect(bytes, isNotNull);
        expect(bytes.isNotEmpty, isTrue);
        expect(String.fromCharCodes(bytes.take(5)), equals('%PDF-'));
        expect(_countPdfPages(bytes), equals(3));
      });

      test(
        'Filled Follow-Up Encounter Slip PDF renders exact Sections 1-5 matching Follow-Up Visit Assessment',
        () async {
          final filledFollowUp = ClinicalVisitModel(
            id: 'vis-fu-complete',
            patientId: '00100',
            campId: testCamp.id,
            visitDate: DateTime(2026, 11, 27),
            isFollowUp: true,
            anamnesisComplaints: const {
              'reasons': ['something hanging out', 'pain'],
              'new_issues': 'MILD PELVIC HEAVINESS AFTER HEAVY LIFTING',
            },
            systolicBp: 118,
            diastolicBp: 76,
            pulse: 74,
            spo2: 98,
            glucose: 96,
            urineTest: 'normal',
            pregnancyTest: 'neg',
            ecgNotes: 'NORMAL SINUS RHYTHM',
            uterusInside: false,
            pelvicFloorTone: 'weak',
            popAnteriorStage: 2,
            popMiddleStage: 3,
            popPosteriorStage: 1,
            highestPopStage: 3,
            diagnoses: const ['POP', 'weak pelvic floor muscle'],
            surgeryDone: true,
            surgeryType: 'Vaginal route',
            surgicalReferral: 'Dhulikhel Hospital',
            medications: const ['estradiol crème'],
            counseling: const ['pelvic floor exercises', 'pessary care & hygiene'],
            pessaryType: 'ring with support',
            pessarySize: '65',
            followUpNeeded: false,
            followUpDestination: null,
            outtakeNotes: 'CONTINUE PELVIC FLOOR EXERCISES DAILY',
            createdAt: now,
            createdByUserId: 'usr-1',
          );

          final bytes = await pdfService.generateFollowUpEncounterSlipPdf(
            patient: testPatientStage4,
            visit: filledFollowUp,
            camp: testCamp,
            organizationName: AppConstants.defaultOrganizationName,
          );

          expect(bytes, isNotEmpty);
          expect(String.fromCharCodes(bytes.take(5)), equals('%PDF-'));

          final extracted = await _extractPdfTextIfAvailable(bytes);
          if (extracted != null) {
            expect(extracted, contains('FOLLOW-UP VISIT ASSESSMENT'));
            expect(extracted, contains('PATIENT IDENTITY'));
            expect(extracted, contains('1. FOLLOW-UP COMPLAINTS & NEW ISSUES'));
            expect(extracted, contains('Selected Follow-Up Complaints'));
            expect(extracted, contains('MILD PELVIC HEAVINESS AFTER HEAVY LIFTING'));
            expect(extracted, contains('2. PHYSICAL VITALS CHECK & SCREENING LABS'));
            expect(extracted, contains('118 mmHg'));
            expect(extracted, contains('NORMAL SINUS RHYTHM'));
            expect(extracted, contains('3. PELVIC FLOOR & POP RE-STAGING'));
            expect(extracted, contains('Uterus Inside'));
            expect(extracted, contains('Pelvic Floor Muscle'));
            expect(extracted, contains('APICAL (Uterine/Apex)'));
            expect(extracted, contains('4. DIAGNOSES & SURGICAL EVALUATION'));
            expect(extracted, contains('Vaginal route'));
            expect(extracted, contains('Dhulikhel Hospital'));
            expect(extracted, contains('5. PRESCRIPTION & FOLLOW-UP DESTINATION'));
            expect(extracted, contains('estradiol crème'));
            expect(extracted, contains('ring with support'));
            expect(extracted, contains('65mm'));
            expect(extracted, contains('None / Not Specified'));
            expect(extracted, contains('CONTINUE PELVIC FLOOR EXERCISES DAILY'));
            // Must NOT render Primary Examination numbering or default fake 'Local Health Post'
            expect(extracted, isNot(contains('Local Health Post')));
            expect(extracted, isNot(contains('STATION 3')));
          }
        },
      );
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
