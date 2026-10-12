import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/constants/clinical_constants.dart';
import 'package:gyno_camp/core/services/pdf_report_service.dart';
import 'package:gyno_camp/core/services/report_aggregation_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/camp_report_summary_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/lookup_item_model.dart';
import 'package:gyno_camp/models/patient_model.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('PdfReportService Tests', () {
    late PdfReportService pdfService;
    late ReportAggregationService aggregationService;

    setUp(() {
      pdfService = PdfReportService();
      aggregationService = ReportAggregationService();
    });

    test('generates valid multi-page PDF bytes with standard %PDF- header', () async {
      final camp = CampModel(
        id: 'camp-pdf-01',
        campCode: 'KTM01',
        name: 'Kathmandu Free Gyno Health Camp',
        district: 'Kathmandu',
        municipality: 'Budhanilkantha',
        ward: '03',
        venue: 'Primary Health Care Center',
        startDate: DateTime(2026, 3, 10),
        endDate: DateTime(2026, 3, 15),
        createdAt: DateTime(2026, 3, 1),
      );

      final patient = PatientModel(
        id: 'p1',
        patientId: 'GC-KTM01-2026-0001',
        campId: camp.id,
        campCode: camp.campCode,
        intakeDate: DateTime(2026, 3, 11),
        firstName: 'Sita',
        surname: 'Sharma',
        age: 36,
        ward: '03',
        mobile: '9841000000',
        createdByUserId: 'usr-1',
        createdByDeviceId: 'dev-1',
        createdAt: DateTime.now(),
      );

      final visit = ClinicalVisitModel(
        id: 'v1',
        patientId: patient.patientId,
        campId: camp.id,
        visitDate: DateTime(2026, 3, 11),
        popAnteriorStage: 2,
        popMiddleStage: 2,
        highestPopStage: 2,
        diagnoses: ['PID', 'POP Stage 2'],
        medications: ['Ciprofloxacin 500mg', 'Metronidazole 400mg'],
        systolicBp: 145,
        diastolicBp: 92,
        pessaryType: 'Ring',
        pessarySize: '65mm',
        surgicalReferral: 'Scheer Memorial Hospital',
        createdByUserId: 'usr-1',
        createdAt: DateTime.now(),
      );

      final summary = aggregationService.aggregate(
        camp: camp,
        patients: [patient],
        visits: [visit],
        generatedBy: 'Dr. Aarav Sharma',
      );

      final bytes = await pdfService.generateCampSummaryPdf(summary);

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));

      // Validate standard PDF magic bytes (%PDF-)
      final header = utf8.decode(bytes.sublist(0, 5));
      expect(header, equals('%PDF-'));
    });

    test('generates valid PDF from empty summary without throwing', () async {
      final emptySummary = CampReportSummaryModel.empty();
      final bytes = await pdfService.generateCampSummaryPdf(emptySummary);

      expect(bytes, isNotEmpty);
      final header = utf8.decode(bytes.sublist(0, 5));
      expect(header, equals('%PDF-'));
    });

    test('generates valid individual patient dossier PDF with full anamnesis and POP-Q data', () async {
      final camp = CampModel(
        id: 'camp-pdf-02',
        campCode: 'PKR01',
        name: 'Pokhara Women Health Camp',
        district: 'Kaski',
        municipality: 'Pokhara',
        ward: '05',
        venue: 'District Health Center',
        startDate: DateTime(2026, 4, 1),
        endDate: DateTime(2026, 4, 5),
        createdAt: DateTime(2026, 3, 20),
      );

      final patient = PatientModel(
        id: 'p2',
        patientId: 'GC-PKR01-2026-0002',
        campId: camp.id,
        campCode: camp.campCode,
        intakeDate: DateTime(2026, 4, 2),
        firstName: 'Radha',
        surname: 'Adhikari',
        age: 48,
        ward: '05',
        maritalStatus: 'married',
        spouseOrFatherName: 'Hari Adhikari',
        mobile: '9856000000',
        reasonsForVisit: ['Pelvic heaviness', 'Difficulty voiding'],
        createdByUserId: 'usr-1',
        createdByDeviceId: 'dev-1',
        createdAt: DateTime.now(),
      );

      final visit = ClinicalVisitModel(
        id: 'v2',
        patientId: patient.patientId,
        campId: camp.id,
        visitDate: DateTime(2026, 4, 2),
        deliveries: 4,
        livingChildren: 4,
        abortions: 0,
        anamnesisComplaints: {
          'pelvic_heaviness': {
            'duration': '>1 year',
            'options': ['Continuous dragging sensation'],
            'remarks': 'Aggravated by standing',
          },
          'burning_micturition': {
            'duration': '2 weeks',
            'options': ['Dysuria'],
            'remarks': 'Mild burning',
          },
        },
        uterusInside: false,
        pelvicFloorTone: 'weak',
        popAnteriorStage: 2,
        popMiddleStage: 3,
        popPosteriorStage: 2,
        highestPopStage: 3,
        systolicBp: 150,
        diastolicBp: 95,
        pulse: 82,
        spo2: 97,
        glucose: 115,
        urineTest: 'Normal',
        pregnancyTest: 'Negative',
        diagnoses: ['Pelvic Organ Prolapse Stage 3', 'Cystocele', 'Hypertension Stage 1'],
        medications: ['Amoxicillin 500mg TDS x 5d', 'Pelvic Muscle Training'],
        pessaryType: 'Ring with Support',
        pessarySize: '70mm',
        followUpNeeded: true,
        followUpDestination: 'Regional Hospital Pokhara',
        surgicalReferral: 'Pokhara Academy of Health Sciences',
        outtakeNotes: 'Refer for vaginal hysterectomy and pelvic floor repair.',
        createdByUserId: 'usr-1',
        createdAt: DateTime.now(),
      );

      final bytes = await pdfService.generateIndividualPatientPdf(
        patient: patient,
        visit: visit,
        camp: camp,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1500));
      final header = utf8.decode(bytes.sublist(0, 5));
      expect(header, equals('%PDF-'));
      final pdfStr = latin1.decode(bytes);
      final pageMatches = RegExp(r'/Type\s*/Page\b').allMatches(pdfStr);
      expect(pageMatches.length, equals(1));
    });

    test('generatePatientRegistrationFormPdf creates exactly 2 pages', () async {
      final bytes = await pdfService.generatePatientRegistrationFormPdf();
      expect(bytes, isNotEmpty);
      final pdfStr = latin1.decode(bytes);
      final pageMatches = RegExp(r'/Type\s*/Page\b').allMatches(pdfStr);
      expect(pageMatches.length, equals(2));
    });

    test('generatePatientRegistrationFormPdf with BlankFormPage1Layout.classic stays strictly 2 pages', () async {
      final bytes = await pdfService.generatePatientRegistrationFormPdf(
        page1Layout: BlankFormPage1Layout.classic,
      );
      expect(bytes, isNotEmpty);
      final pdfStr = latin1.decode(bytes);
      final pageMatches = RegExp(r'/Type\s*/Page\b').allMatches(pdfStr);
      expect(pageMatches.length, equals(2));
    });

    test('generatePatientRegistrationFormPdf with camp generates 2 pages for blank form without bullet glyph errors', () async {
      final camp = CampModel(
        id: 'c-ktm-01',
        campCode: 'KTM01',
        name: 'Outreach Gyno Health Camp',
        venue: 'Primary Health Care Center',
        district: 'KATHMANDU',
        municipality: 'BUDHANILKANTHA MUNICIPALITY',
        ward: '03',
        startDate: DateTime.now(),
        endDate: DateTime.now().add(const Duration(days: 3)),
        status: CampStatus.open,
        createdAt: DateTime.now(),
      );

      final bytes = await pdfService.generatePatientRegistrationFormPdf(
        camp: camp,
        organizationName: 'Community Health Outreach Mission',
      );
      expect(bytes, isNotEmpty);
      final pdfStr = latin1.decode(bytes);
      final pageMatches = RegExp(r'/Type\s*/Page\b').allMatches(pdfStr);
      expect(pageMatches.length, equals(2));
      // Verify no bullet character exists in raw stream
      expect(pdfStr.contains('•'), isFalse);
    });

    test('generatePatientRegistrationFormPdf with long municipality stays strictly 2 pages', () async {
      final patient = PatientModel(
        id: 'p-long-01',
        patientId: 'KTM01-001',
        campId: 'c-ktm-01',
        campCode: 'KTM01',
        intakeDate: DateTime.now(),
        firstName: 'SITA',
        surname: 'SHRESTHA',
        age: 38,
        maritalStatus: 'married',
        spouseOrFatherName: 'RAM SHRESTHA',
        mobile: '9841234567',
        contactPerson: 'HARI SHRESTHA',
        contactMobile: '9847654321',
        maritalAge: 20,
        district: 'KATHMANDU',
        municipality: 'BUDHANILKANTHA MUNICIPALITY',
        ward: '03',
        province: 'BAGMATI',
        reasonsForVisit: ['pelvic_organ_prolapse', 'urinary_problems'],
        consentTreatment: true,
        consentStoreMedicalInfo: true,
        createdByUserId: 'usr-1',
        createdByDeviceId: 'dev-1',
        createdAt: DateTime.now(),
      );

      final bytes = await pdfService.generatePatientRegistrationFormPdf(
        patient: patient,
      );
      expect(bytes, isNotEmpty);
      final pdfStr = latin1.decode(bytes);
      final pageMatches = RegExp(r'/Type\s*/Page\b').allMatches(pdfStr);
      expect(pageMatches.length, equals(2));
    });

    test('generatePatientRegistrationFormPdf with dynamic lookups and camp doctor stays strictly 2 pages', () async {
      final camp = CampModel(
        id: 'camp-doc-01',
        campCode: 'DOC01',
        name: 'Dhading Health Outreach',
        doctorName: 'Dr. Aarav Koirala, MD',
        province: 'Bagmati',
        district: 'Dhading',
        municipality: 'Nilkantha',
        ward: '04',
        venue: 'Nilkantha Primary Health Care',
        startDate: DateTime.now(),
        endDate: DateTime.now().add(const Duration(days: 2)),
        status: CampStatus.open,
        createdAt: DateTime.now(),
      );

      final customDiagnoses = [
        LookupItemModel(id: 'd1', category: 'diagnosis', code: 'cervical_erosion', labelEn: 'Cervical Erosion', labelNe: 'पाठेघरको मुखको घाउ'),
        LookupItemModel(id: 'd2', category: 'diagnosis', code: 'pelvic_adhesions', labelEn: 'Pelvic Adhesions', labelNe: 'तल्लो पेटको जालो'),
      ];

      final customMedicines = [
        LookupItemModel(id: 'm1', category: 'medicine', code: 'doxycycline_100mg', labelEn: 'Doxycycline 100mg', labelNe: 'डक्सिसाइक्लिन'),
        LookupItemModel(id: 'm2', category: 'medicine', code: 'azithromycin_500mg', labelEn: 'Azithromycin 500mg', labelNe: 'एजिथ्रोमाइसिन'),
      ];

      final customHospitals = [
        LookupItemModel(id: 'h1', category: 'referral_hospital', code: 'patan_hospital', labelEn: 'Patan Hospital', labelNe: 'पाटन अस्पताल'),
      ];

      final customReasons = [
        LookupItemModel(id: 'r1', category: 'visit_reason', code: 'urinary_trouble', labelEn: 'Urinary Issues', labelNe: 'पिसाब सम्बन्धी समस्या'),
      ];

      final customComplaints = [
        LookupItemModel(id: 'c1', category: 'chief_complaint', code: 'dysuria', labelEn: 'Dysuria / Burning Urine', labelNe: 'पिसाब पोल्ने'),
      ];

      final bytes = await pdfService.generatePatientRegistrationFormPdf(
        camp: camp,
        organizationName: 'Community Medical Outreach Mission',
        diagnoses: customDiagnoses,
        medications: customMedicines,
        referralHospitals: customHospitals,
        visitReasons: customReasons,
        chiefComplaints: customComplaints,
      );

      expect(bytes, isNotEmpty);
      final pdfStr = latin1.decode(bytes);
      final pageMatches = RegExp(r'/Type\s*/Page\b').allMatches(pdfStr);
      expect(pageMatches.length, equals(2));
      expect(bytes.length, greaterThan(1000));
    });

    test('generatePatientRegistrationFormPdf renders Page 2 stations under full capacity lookups without blank overflow', () async {
      final camp = CampModel(
        id: 'camp-full-01',
        campCode: 'FULL01',
        name: 'Full Capacity Camp',
        district: 'Kathmandu',
        municipality: 'Budhanilkantha Municipality',
        ward: '03',
        venue: 'Health Post',
        startDate: DateTime(2026, 9, 20),
        endDate: DateTime(2026, 9, 24),
        status: CampStatus.open,
        createdAt: DateTime.now(),
        organizationName: 'Community Health Outreach Mission',
      );

      final diags = ClinicalConstants.defaultDiagnoses.map((d) => LookupItemModel(
        id: d, category: 'diagnosis', code: d, labelEn: d, labelNe: '',
      )).toList();

      final meds = ClinicalConstants.defaultMedications.map((m) => LookupItemModel(
        id: m, category: 'medicine', code: m, labelEn: m, labelNe: '',
      )).toList();

      final hosps = ClinicalConstants.referralHospitals.map((h) => LookupItemModel(
        id: h, category: 'referral_hospital', code: h, labelEn: h, labelNe: '',
      )).toList();

      final bytes = await pdfService.generatePatientRegistrationFormPdf(
        camp: camp,
        organizationName: 'Community Health Outreach Mission',
        diagnoses: diags,
        medications: meds,
        referralHospitals: hosps,
      );

      expect(bytes, isNotEmpty);
      // Size must be over 20KB indicating Page 2 body is populated
      expect(bytes.length, greaterThan(20000));
      
      final pdfStr = String.fromCharCodes(bytes);
      final streamRegex = RegExp(r'stream[\r\n]+(.*?)[\r\n]+endstream', dotAll: true);
      final streams = streamRegex.allMatches(pdfStr).toList();
      var foundStationOnPage2 = false;
      for (final m in streams) {
        try {
          final decoded = String.fromCharCodes(zlib.decode(m.group(1)!.codeUnits));
          if (decoded.contains('CLINICAL') && decoded.contains('STATION') && decoded.contains('ANAMNESIS')) {
            foundStationOnPage2 = true;
          }
        } catch (_) {}
      }
      expect(foundStationOnPage2, isTrue);
    });

    test('CampModel serialization preserves doctorName correctly', () {
      final camp = CampModel(
        id: 'c-test-doc',
        campCode: 'KTM99',
        name: 'Specialist Camp',
        doctorName: 'Dr. Sita Sharma, MD',
        district: 'Kathmandu',
        municipality: 'Kathmandu Metropolitan',
        venue: 'Camp Hall',
        ward: '03',
        startDate: DateTime(2026, 9, 20),
        endDate: DateTime(2026, 9, 22),
        status: CampStatus.scheduled,
        createdAt: DateTime(2026, 9, 20),
      );

      expect(camp.doctorName, equals('Dr. Sita Sharma, MD'));

      final map = camp.toMap();
      expect(map['doctor_name'], equals('Dr. Sita Sharma, MD'));

      final restored = CampModel.fromMap(map);
      expect(restored.doctorName, equals('Dr. Sita Sharma, MD'));

      final copied = camp.copyWith(doctorName: 'Dr. Ramesh Adhikari');
      expect(copied.doctorName, equals('Dr. Ramesh Adhikari'));
      expect(copied.campCode, equals('KTM99'));
    });

    test('generatePatientRegistrationFormPdf with blank doctor and nurse lines succeeds', () async {
      final camp = CampModel(
        id: 'camp-inspect',
        campCode: 'KTM01',
        name: 'Gyno Health Outreach Camp',
        venue: 'Primary Health Care Center',
        district: 'Kathmandu',
        municipality: 'Budhanilkantha Municipality',
        ward: '03',
        startDate: DateTime.now(),
        endDate: DateTime.now().add(const Duration(days: 3)),
        status: CampStatus.open,
        createdAt: DateTime.now(),
      );

      final bytes = await pdfService.generatePatientRegistrationFormPdf(
        camp: camp,
        blankDoctorLines: true,
        blankNurseLines: true,
      );
      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(20000));
      final header = utf8.decode(bytes.sublist(0, 5));
      expect(header, equals('%PDF-'));
    });

    test('generate and export camp 3RD and camp 11 for visual inspection', () async {
      final camp3rd = CampModel(
        id: 'c-3rd',
        campCode: '3RD',
        name: 'old testing camp',
        venue: 'Health Post',
        district: 'Kathmandu',
        municipality: 'Kathmandu',
        ward: '01',
        doctorName: 'sugam tiwari',
        doctorNames: ['sugam tiwari'],
        startDate: DateTime(2026, 10, 11),
        endDate: DateTime(2026, 10, 15),
        status: CampStatus.open,
        createdAt: DateTime.now(),
      );

      final doc3rd = DoctorProfile(
        name: 'sugam tiwari',
        nmcNumber: '456',
      );

      final visitReasons4 = [
        LookupItemModel(id: '1', category: 'visit_reason', code: 'follow_up', labelEn: 'Follow-up Visit', labelNe: 'पुन: जाँच', isActive: true),
        LookupItemModel(id: '2', category: 'visit_reason', code: 'new_consultation', labelEn: 'New Consultation', labelNe: 'नयाँ परामर्श', isActive: true),
        LookupItemModel(id: '3', category: 'visit_reason', code: 'pap_smear', labelEn: 'Pap Smear / Cervical Screening', labelNe: 'पाठेघरको मुखको क्यान्सर जाँच', isActive: true),
        LookupItemModel(id: '4', category: 'visit_reason', code: 'pre_surgical', labelEn: 'Pre-surgical Screening', labelNe: 'शल्यक्रिया पूर्व जाँच', isActive: true),
      ];

      final bytes3rd = await pdfService.generatePatientRegistrationFormPdf(
        camp: camp3rd,
        doctor: doc3rd,
        organizationName: 'Women for Society',
        visitReasons: visitReasons4,
      );

      final camp11 = CampModel(
        id: 'c-11',
        campCode: '11',
        name: 'new nurse testing',
        venue: 'Health Post',
        district: 'Kathmandu',
        municipality: 'Budhanilkantha Municipality',
        ward: '03',
        startDate: DateTime(2026, 10, 11),
        endDate: DateTime(2026, 10, 15),
        status: CampStatus.open,
        createdAt: DateTime.now(),
      );

      final bytes11 = await pdfService.generatePatientRegistrationFormPdf(
        camp: camp11,
        blankDoctorLines: true,
        blankNurseLines: true,
        organizationName: 'Women for Society',
      );

      expect(bytes3rd, isNotEmpty);
      expect(utf8.decode(bytes3rd.sublist(0, 5)), equals('%PDF-'));
      expect(bytes11, isNotEmpty);
      expect(utf8.decode(bytes11.sublist(0, 5)), equals('%PDF-'));
    });

    test('generateFollowUpEncounterSlipPdf generates valid PDF with Level of Treatment', () async {
      final camp = CampModel(
        id: 'camp-slip-01',
        campCode: 'KTM99',
        name: 'Kathmandu Health Camp',
        district: 'Kathmandu',
        municipality: 'Kathmandu',
        ward: '04',
        venue: 'Health Center',
        startDate: DateTime.now(),
        endDate: DateTime.now().add(const Duration(days: 2)),
        status: CampStatus.open,
        createdAt: DateTime.now(),
      );

      final patient = PatientModel(
        id: 'p-slip',
        patientId: 'GC-KTM99-001',
        campId: camp.id,
        campCode: camp.campCode,
        intakeDate: DateTime.now(),
        firstName: 'Sita',
        surname: 'Thapa',
        age: 42,
        treatmentLevel: 'full_check_up',
        ward: '04',
        mobile: '9841112233',
        reasonsForVisit: ['Pelvic heaviness'],
        createdByUserId: 'u1',
        createdByDeviceId: 'd1',
        createdAt: DateTime.now(),
      );

      final visit = ClinicalVisitModel(
        id: 'v-slip',
        patientId: patient.patientId,
        campId: camp.id,
        visitDate: DateTime.now(),
        treatmentLevel: 'full_check_up',
        popAnteriorStage: 1,
        popMiddleStage: 2,
        highestPopStage: 2,
        diagnoses: ['POP Stage 2'],
        medications: ['Metronidazole'],
        createdByUserId: 'u1',
        createdAt: DateTime.now(),
      );

      final bytes = await pdfService.generateFollowUpEncounterSlipPdf(
        patient: patient,
        visit: visit,
        camp: camp,
      );

      expect(bytes, isNotEmpty);
      expect(utf8.decode(bytes.sublist(0, 5)), equals('%PDF-'));
    });

    test('generatePreNumberedBlankFormsPdf generates valid PDF batch with sequential tokens', () async {
      final camp = CampModel(
        id: 'camp-range-01',
        campCode: 'DHN',
        name: 'Dhangadhi Women Health Camp',
        district: 'Kailali',
        municipality: 'Dhangadhi',
        ward: '01',
        venue: 'Zonal Hospital',
        startDate: DateTime(2026, 4, 1),
        endDate: DateTime(2026, 4, 5),
        createdAt: DateTime(2026, 3, 20),
      );

      final bytes = await pdfService.generatePreNumberedBlankFormsPdf(
        camp: camp,
        startSequence: 1,
        count: 3,
      );

      expect(bytes, isNotEmpty);
      expect(utf8.decode(bytes.sublist(0, 5)), equals('%PDF-'));
    });

    test('generatePreNumberedBlankFollowUpSlipsPdf generates valid PDF batch with sequential tokens', () async {
      final camp = CampModel(
        id: 'camp-range-02',
        campCode: 'DHN',
        name: 'Dhangadhi Women Health Camp',
        district: 'Kailali',
        municipality: 'Dhangadhi',
        ward: '01',
        venue: 'Zonal Hospital',
        startDate: DateTime(2026, 4, 1),
        endDate: DateTime(2026, 4, 5),
        createdAt: DateTime(2026, 3, 20),
      );

      final bytes = await pdfService.generatePreNumberedBlankFollowUpSlipsPdf(
        camp: camp,
        startSequence: 10,
        count: 2,
      );

      expect(bytes, isNotEmpty);
      expect(utf8.decode(bytes.sublist(0, 5)), equals('%PDF-'));
    });
  });
}

