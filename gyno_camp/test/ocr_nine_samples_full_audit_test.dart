import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/constants/clinical_constants.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/core/services/gemini_ocr_service.dart';
import 'package:gyno_camp/core/services/ocr_form_service.dart';
import 'package:gyno_camp/core/services/pdf_report_service.dart';
import 'package:gyno_camp/core/utils/nepali_date_helper.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/ocr_scan_result_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/ocr_repository.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';

class SampleAuditCase {
  final int index;
  final String slug;
  final CampModel camp;
  final PatientModel patient;
  final ClinicalVisitModel visit;
  final DoctorProfile? doctor;
  final NurseProfile? nurse;
  final bool allDoctorsChecklist;
  final bool allNursesChecklist;
  final Map<String, Map<String, dynamic>> expectedComplaints;
  final String expectedEcgStatus;

  const SampleAuditCase({
    required this.index,
    required this.slug,
    required this.camp,
    required this.patient,
    required this.visit,
    this.doctor,
    this.nurse,
    this.allDoctorsChecklist = false,
    this.allNursesChecklist = false,
    required this.expectedComplaints,
    required this.expectedEcgStatus,
  });
}

String toBsString(DateTime ad) {
  final bs = NepaliDateHelper.toNepali(ad);
  return '${bs.year.toString().padLeft(4, '0')}-${bs.month.toString().padLeft(2, '0')}-${bs.day.toString().padLeft(2, '0')}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  final pdfService = PdfReportService();
  const ocrService = OcrFormService();
  final outDir = Directory('test_samples/nine_samples_audit');

  Future<({String page1, String page2})> extractPdfPages(File pdfFile) async {
    final txtPath = pdfFile.path.replaceAll('.pdf', '.txt');
    final proc = await Process.run(
      r'C:\Program Files\Git\mingw64\bin\pdftotext.exe',
      ['-layout', '-enc', 'UTF-8', pdfFile.path, txtPath],
    );
    expect(proc.exitCode, 0, reason: 'pdftotext failed on ${pdfFile.path}: ${proc.stderr}');
    final rawAll = File(txtPath).readAsStringSync();
    final pages = rawAll
        .split(RegExp(r'[\x0c\f]'))
        .where((p) => p.trim().isNotEmpty)
        .toList();
    expect(pages.length, greaterThanOrEqualTo(2), reason: 'PDF must contain 2 pages');
    return (page1: pages[0], page2: pages[1]);
  }

  CampModel makeCamp({
    required String id,
    required String code,
    required String name,
    required String province,
    required String district,
    required String municipality,
    required String ward,
    required DateTime date,
    List<DoctorProfile> doctors = const [],
    List<NurseProfile> nurses = const [],
  }) {
    return CampModel(
      id: id,
      campCode: code,
      name: name,
      province: province,
      district: district,
      municipality: municipality,
      ward: ward,
      venue: '$municipality Health Center',
      startDate: date,
      endDate: date.add(const Duration(days: 2)),
      status: CampStatus.open,
      doctorNames: doctors.map((d) => d.formattedLabel).toList(),
      nurseNames: nurses.map((n) => n.formattedLabel).toList(),
      tenantId: 'tenant_wfwsn_nepal',
      organizationName: 'Women for Women Support Nepal',
      createdAt: date,
    );
  }

  final List<SampleAuditCase> samples = [
    // SAMPLE 1: Bagmati / Kathmandu — Severe POP Stage 3, Married, Gynocheckup, Ring with Support 65mm
    SampleAuditCase(
      index: 1,
      slug: '01_sita_sharma_bagmati_pop3',
      camp: makeCamp(
        id: 'camp-01',
        code: 'KTM01',
        name: 'Tokha Women Outreach Camp',
        province: 'Bagmati',
        district: 'Kathmandu',
        municipality: 'Tokha',
        ward: '04',
        date: DateTime(2026, 5, 14),
      ),
      doctor: const DoctorProfile(name: 'Roshani Thapa', nmcNumber: '8845'),
      nurse: const NurseProfile(name: 'Anita Gurung', registrationNumber: '10234'),
      expectedEcgStatus: 'Normal Sinus',
      expectedComplaints: {
        'prolapse': {
          'duration': '> 5 years',
          'options': ['pessary'],
          'remarks': 'Worse on standing',
        },
        'urine': {
          'duration': '> 1 year',
          'options': ['stress'],
          'remarks': 'Leaks on cough',
        },
      },
      patient: PatientModel(
        id: 'pat-audit-01',
        patientId: 'GC-KTM01-2026-00001',
        campId: 'camp-01',
        campCode: 'KTM01',
        intakeDate: DateTime(2026, 5, 14),
        firstName: 'Sita',
        surname: 'Sharma',
        age: 52,
        spouseOrFatherName: 'Ram Sharma',
        relationshipType: 'Husband',
        mobile: '9841112233',
        contactPerson: 'Hari KC',
        contactMobile: '9851001122',
        maritalStatus: 'married',
        maritalAge: 18,
        province: 'Bagmati',
        district: 'Kathmandu',
        municipality: 'Tokha',
        ward: '04',
        reasonsForVisit: ['something hanging out', 'problems passing urine'],
        consentTreatment: true,
        consentStoreMedicalInfo: true,
        treatmentLevel: 'gyno_checkup',
        createdAt: DateTime(2026, 5, 14),
        createdByUserId: 'usr-01',
        createdByDeviceId: 'dev-01',
      ),
      visit: ClinicalVisitModel(
        id: 'vis-audit-01',
        patientId: 'GC-KTM01-2026-00001',
        campId: 'camp-01',
        visitDate: DateTime(2026, 5, 14),
        anamnesisDate: DateTime(2026, 5, 14),
        examDate: DateTime(2026, 5, 14),
        labTestDate: DateTime(2026, 5, 14),
        conclusionDate: DateTime(2026, 5, 14),
        treatmentDate: DateTime(2026, 5, 14),
        outtakeDate: DateTime(2026, 5, 14),
        deliveries: 4,
        livingChildren: 3,
        abortions: 1,
        anamnesisComplaints: {
          'clinicalComplaints': ['prolapse', 'urine'],
          'complaintsDuration': '> 5 years',
          'prolapse': {
            'duration': '> 5 years',
            'options': ['pessary'],
            'remarks': 'Worse on standing',
          },
          'urine': {
            'duration': '> 1 year',
            'options': ['stress'],
            'remarks': 'Leaks on cough',
          },
        },
        uterusInside: false,
        pelvicFloorTone: 'weak',
        vulvaRemarks: 'Normal',
        vaginaRemarks: 'Atrophic mucosa',
        cervixRemarks: 'Decubitus ulcer',
        uterusRemarks: 'Normal',
        popAnteriorStage: 2,
        popMiddleStage: 3,
        popPosteriorStage: 1,
        highestPopStage: 3,
        urineTest: 'normal',
        pregnancyTest: 'neg',
        systolicBp: 128,
        diastolicBp: 82,
        pulse: 76,
        spo2: 98,
        glucose: 104,
        ecgNotes: 'Normal Sinus',
        diagnoses: ['atrophy vagina', 'stress incontinence', 'weak pelvic floor muscle'],
        pessaryType: 'ring with support',
        pessarySize: '65',
        counseling: ['weak pelvic floor', 'POP', 'stress incontinence'],
        surgicalReferral: 'Scheer Memorial',
        medications: ['estradiol crème'],
        treatmentLevel: 'gyno_checkup',
        followUpNeeded: true,
        followUpDestination: 'GynaeSupport Nurse',
        outtakeNotes: 'Fitted 65mm ring with support. Review in 2 weeks.',
        primaryDoctorName: 'Dr. Roshani Thapa',
        attendingDoctorNames: ['Dr. Roshani Thapa'],
        primaryNurseName: 'Anita Gurung',
        attendingNurseNames: ['Anita Gurung'],
        createdAt: DateTime(2026, 5, 14),
        createdByUserId: 'usr-01',
      ),
    ),

    // SAMPLE 2: Koshi / Morang — Acute Reproductive Tract Infections, Married, Gynocheckup
    SampleAuditCase(
      index: 2,
      slug: '02_bina_rai_koshi_infections',
      camp: makeCamp(
        id: 'camp-02',
        code: 'MRG02',
        name: 'Biratnagar Gyno Camp',
        province: 'Koshi',
        district: 'Morang',
        municipality: 'Biratnagar',
        ward: '07',
        date: DateTime(2026, 6, 18),
      ),
      doctor: const DoctorProfile(name: 'Bikash Shrestha', nmcNumber: '11209'),
      nurse: const NurseProfile(name: 'Sunita Limbu', registrationNumber: '20451'),
      expectedEcgStatus: 'Not Done',
      expectedComplaints: {
        'discharge': {
          'duration': '< 1month',
          'options': ['white', 'yellow', 'smelly'],
          'remarks': 'Severe vulvar pruritus',
        },
        'lower_abdomen_pain': {
          'duration': '< 1month',
          'options': <String>[],
          'remarks': 'Dull suprapubic ache',
        },
      },
      patient: PatientModel(
        id: 'pat-audit-02',
        patientId: 'GC-MRG02-2026-00014',
        campId: 'camp-02',
        campCode: 'MRG02',
        intakeDate: DateTime(2026, 6, 18),
        firstName: 'Bina',
        surname: 'Rai',
        age: 29,
        spouseOrFatherName: 'Kiran Rai',
        relationshipType: 'Husband',
        mobile: '9802345678',
        contactPerson: 'Mina Rai',
        contactMobile: '9812345679',
        maritalStatus: 'married',
        maritalAge: 21,
        province: 'Koshi',
        district: 'Morang',
        municipality: 'Biratnagar',
        ward: '07',
        reasonsForVisit: ['discharge and or itching', 'pain'],
        consentTreatment: true,
        consentStoreMedicalInfo: true,
        treatmentLevel: 'gyno_checkup',
        createdAt: DateTime(2026, 6, 18),
        createdByUserId: 'usr-01',
        createdByDeviceId: 'dev-01',
      ),
      visit: ClinicalVisitModel(
        id: 'vis-audit-02',
        patientId: 'GC-MRG02-2026-00014',
        campId: 'camp-02',
        visitDate: DateTime(2026, 6, 18),
        anamnesisDate: DateTime(2026, 6, 18),
        examDate: DateTime(2026, 6, 18),
        labTestDate: DateTime(2026, 6, 18),
        conclusionDate: DateTime(2026, 6, 18),
        treatmentDate: DateTime(2026, 6, 18),
        outtakeDate: DateTime(2026, 6, 18),
        deliveries: 2,
        livingChildren: 2,
        abortions: 0,
        anamnesisComplaints: {
          'clinicalComplaints': ['discharge', 'lower_abdomen_pain'],
          'complaintsDuration': '< 1month',
          'discharge': {
            'duration': '< 1month',
            'options': ['white', 'yellow', 'smelly'],
            'remarks': 'Severe vulvar pruritus',
          },
          'lower_abdomen_pain': {
            'duration': '< 1month',
            'options': <String>[],
            'remarks': 'Dull suprapubic ache',
          },
        },
        uterusInside: true,
        pelvicFloorTone: 'normal',
        vulvaRemarks: 'Erythema excoriation',
        vaginaRemarks: 'Curdy white discharge',
        cervixRemarks: 'Cervical hyperemia',
        uterusRemarks: 'Mild tenderness',
        popAnteriorStage: 0,
        popMiddleStage: 0,
        popPosteriorStage: 0,
        highestPopStage: 0,
        urineTest: 'pos',
        pregnancyTest: 'neg',
        systolicBp: 114,
        diastolicBp: 74,
        pulse: 84,
        spo2: 99,
        glucose: 96,
        ecgNotes: 'Not Done',
        diagnoses: [
          'bacterial vaginosis',
          'candid infection',
          'trichomonas',
          'PID',
          'cervicitis',
        ],
        counseling: ['abdominal pain'],
        medications: [
          'clotrimazol (canesten)',
          'metronidazol',
          'doxycycline',
          'azithromycin',
        ],
        treatmentLevel: 'gyno_checkup',
        followUpNeeded: true,
        followUpDestination: 'Health Post',
        outtakeNotes: 'Partner treatment advised. Return if fever develops.',
        primaryDoctorName: 'Dr. Bikash Shrestha',
        attendingDoctorNames: ['Dr. Bikash Shrestha'],
        primaryNurseName: 'Sunita Limbu',
        attendingNurseNames: ['Sunita Limbu'],
        createdAt: DateTime(2026, 6, 18),
        createdByUserId: 'usr-01',
      ),
    ),

    // SAMPLE 3: Madhesh / Dhanusha — Unmarried Young Adult, Counseling, Storage Consent NO, Custom Diagnosis & Med, No Follow-Up
    SampleAuditCase(
      index: 3,
      slug: '03_puja_yadav_madhesh_counseling',
      camp: makeCamp(
        id: 'camp-03',
        code: 'DHN03',
        name: 'Janakpur Youth & Women Camp',
        province: 'Madhesh',
        district: 'Dhanusha',
        municipality: 'Janakpur',
        ward: '11',
        date: DateTime(2026, 7, 22),
      ),
      doctor: const DoctorProfile(name: 'Suman Jha', nmcNumber: '14532'),
      nurse: const NurseProfile(name: 'Kabita Mandal', registrationNumber: '33112'),
      expectedEcgStatus: 'Normal Sinus',
      expectedComplaints: {
        'menstrual': {
          'duration': '',
          'options': ['dysmenorrhoea', 'menorrhagia'],
          'remarks': 'Heavy clots for 7 days',
        },
        'lower_back_pain': {
          'duration': '< 1 year',
          'options': <String>[],
          'remarks': 'Radiates during menses',
        },
      },
      patient: PatientModel(
        id: 'pat-audit-03',
        patientId: 'GC-DHN03-2026-00027',
        campId: 'camp-03',
        campCode: 'DHN03',
        intakeDate: DateTime(2026, 7, 22),
        firstName: 'Puja',
        surname: 'Yadav',
        age: 19,
        spouseOrFatherName: 'Mahesh Yadav',
        relationshipType: 'Father',
        mobile: '9863456789',
        contactPerson: 'Rekha Devi',
        contactMobile: '9844112233',
        maritalStatus: 'unmarried',
        maritalAge: null,
        province: 'Madhesh',
        district: 'Dhanusha',
        municipality: 'Janakpur',
        ward: '11',
        reasonsForVisit: ['menstrual problem', 'pain'],
        consentTreatment: true,
        consentStoreMedicalInfo: false,
        treatmentLevel: 'counseling',
        createdAt: DateTime(2026, 7, 22),
        createdByUserId: 'usr-01',
        createdByDeviceId: 'dev-01',
      ),
      visit: ClinicalVisitModel(
        id: 'vis-audit-03',
        patientId: 'GC-DHN03-2026-00027',
        campId: 'camp-03',
        visitDate: DateTime(2026, 7, 22),
        anamnesisDate: DateTime(2026, 7, 22),
        examDate: DateTime(2026, 7, 22),
        labTestDate: DateTime(2026, 7, 22),
        conclusionDate: DateTime(2026, 7, 22),
        treatmentDate: DateTime(2026, 7, 22),
        outtakeDate: DateTime(2026, 7, 22),
        deliveries: 0,
        livingChildren: 0,
        abortions: 0,
        anamnesisComplaints: {
          'clinicalComplaints': ['menstrual', 'lower_back_pain'],
          'complaintsDuration': '< 1 year',
          'menstrual': {
            'duration': '',
            'options': ['dysmenorrhoea', 'menorrhagia'],
            'remarks': 'Heavy clots for 7 days',
          },
          'lower_back_pain': {
            'duration': '< 1 year',
            'options': <String>[],
            'remarks': 'Radiates during menses',
          },
        },
        uterusInside: true,
        pelvicFloorTone: 'normal',
        vulvaRemarks: 'Normal',
        vaginaRemarks: 'Normal',
        cervixRemarks: 'Normal',
        uterusRemarks: 'Normal',
        popAnteriorStage: 0,
        popMiddleStage: 0,
        popPosteriorStage: 0,
        highestPopStage: 0,
        urineTest: 'normal',
        pregnancyTest: 'neg',
        systolicBp: 106,
        diastolicBp: 68,
        pulse: 88,
        spo2: 99,
        glucose: 89,
        ecgNotes: 'Normal Sinus',
        diagnoses: ['menstrual disorder', 'Iron deficiency anemia'],
        counseling: ['abdominal pain'],
        medications: ['medroxyprogesterone'],
        customMedication: 'Tranexamic acid 500mg TDS',
        treatmentLevel: 'counseling',
        followUpNeeded: false,
        followUpDestination: 'no follow up needed',
        outtakeNotes: 'Reassured regarding primary dysmenorrhoea. Iron supplements given.',
        primaryDoctorName: 'Dr. Suman Jha',
        attendingDoctorNames: ['Dr. Suman Jha'],
        primaryNurseName: 'Kabita Mandal',
        attendingNurseNames: ['Kabita Mandal'],
        createdAt: DateTime(2026, 7, 22),
        createdByUserId: 'usr-01',
      ),
    ),

    // SAMPLE 4: Gandaki / Kaski — Widow, Complete Procidentia POP Stage 4, Abnormal ECG, Ring with Knob 75mm, Hospital Follow-Up, Multi-Staff Checklist
    SampleAuditCase(
      index: 4,
      slug: '04_dilmaya_gurung_gandaki_pop4_multistaff',
      camp: makeCamp(
        id: 'camp-04',
        code: 'KSK04',
        name: 'Pokhara Pelvic Care Camp',
        province: 'Gandaki',
        district: 'Kaski',
        municipality: 'Pokhara',
        ward: '02',
        date: DateTime(2026, 8, 19),
        doctors: const [
          DoctorProfile(name: 'Anjali KC', nmcNumber: '9012'),
          DoctorProfile(name: 'Pradeep Gurung', nmcNumber: '9055'),
          DoctorProfile(name: 'Manish Pokharel', nmcNumber: '9099'),
        ],
        nurses: const [
          NurseProfile(name: 'Swapnil Pathak', registrationNumber: '41001'),
          NurseProfile(name: 'Nikita Sharma', registrationNumber: '41002'),
          NurseProfile(name: 'Pramila Thapa', registrationNumber: '41003'),
        ],
      ),
      allDoctorsChecklist: true,
      allNursesChecklist: true,
      expectedEcgStatus: 'Abnormal',
      expectedComplaints: {
        'prolapse': {
          'duration': '> 10 years',
          'options': ['pessary', 'surgery'],
          'remarks': 'Complete irreducible mass',
        },
        'stool': {
          'duration': '> 5 years',
          'options': <String>[],
          'remarks': 'Needs splinting to defecate',
        },
      },
      patient: PatientModel(
        id: 'pat-audit-04',
        patientId: 'GC-KSK04-2026-00053',
        campId: 'camp-04',
        campCode: 'KSK04',
        intakeDate: DateTime(2026, 8, 19),
        firstName: 'Dilmaya',
        surname: 'Gurung',
        age: 68,
        spouseOrFatherName: 'Birbahadur Gurung',
        relationshipType: 'Father',
        mobile: '9846012345',
        contactPerson: 'Dipak Pun',
        contactMobile: '9806543210',
        maritalStatus: 'widow',
        maritalAge: 16,
        province: 'Gandaki',
        district: 'Kaski',
        municipality: 'Pokhara',
        ward: '02',
        reasonsForVisit: ['something hanging out', 'problems passing stool'],
        consentTreatment: true,
        consentStoreMedicalInfo: true,
        treatmentLevel: 'gyno_checkup',
        createdAt: DateTime(2026, 8, 19),
        createdByUserId: 'usr-01',
        createdByDeviceId: 'dev-01',
      ),
      visit: ClinicalVisitModel(
        id: 'vis-audit-04',
        patientId: 'GC-KSK04-2026-00053',
        campId: 'camp-04',
        visitDate: DateTime(2026, 8, 19),
        anamnesisDate: DateTime(2026, 8, 19),
        examDate: DateTime(2026, 8, 19),
        labTestDate: DateTime(2026, 8, 19),
        conclusionDate: DateTime(2026, 8, 19),
        treatmentDate: DateTime(2026, 8, 19),
        outtakeDate: DateTime(2026, 8, 19),
        deliveries: 6,
        livingChildren: 5,
        abortions: 1,
        anamnesisComplaints: {
          'clinicalComplaints': ['prolapse', 'stool'],
          'complaintsDuration': '> 10 years',
          'prolapse': {
            'duration': '> 10 years',
            'options': ['pessary', 'surgery'],
            'remarks': 'Complete irreducible mass',
          },
          'stool': {
            'duration': '> 5 years',
            'options': <String>[],
            'remarks': 'Needs splinting to defecate',
          },
        },
        uterusInside: false,
        pelvicFloorTone: 'weak',
        vulvaRemarks: 'Pale thin skin fissures',
        vaginaRemarks: 'Keratinized dry wall',
        cervixRemarks: 'Hypertrophied eroded',
        uterusRemarks: 'Atrophic prolapsed',
        popAnteriorStage: 3,
        popMiddleStage: 4,
        popPosteriorStage: 3,
        highestPopStage: 4,
        urineTest: 'normal',
        pregnancyTest: 'neg',
        systolicBp: 136,
        diastolicBp: 86,
        pulse: 72,
        spo2: 95,
        glucose: 122,
        ecgNotes: 'Abnormal: LVH strain pattern',
        diagnoses: ['lichen sclerosis', 'cervical polyp', 'fistula'],
        pessaryType: 'ring with knob',
        pessarySize: '75',
        counseling: ['POP', 'weak pelvic floor'],
        surgicalReferral: 'Model Hosp',
        medications: ['clobetasol'],
        treatmentLevel: 'gyno_checkup',
        followUpNeeded: true,
        followUpDestination: 'Western Regional Hospital',
        outtakeNotes: 'Referred for vaginal hysterectomy after cardiac clearance.',
        primaryDoctorName: 'Dr. Anjali KC',
        attendingDoctorNames: ['Dr. Anjali KC', 'Dr. Pradeep Gurung'],
        primaryNurseName: 'Swapnil Pathak',
        attendingNurseNames: ['Swapnil Pathak', 'Nikita Sharma'],
        createdAt: DateTime(2026, 8, 19),
        createdByUserId: 'usr-01',
      ),
    ),

    // SAMPLE 5: Lumbini / Rupandehi — Divorced, Urge Incontinence + Cystitis + Hypertonic Floor + Condylomata
    SampleAuditCase(
      index: 5,
      slug: '05_sarita_tharu_lumbini_urinary',
      camp: makeCamp(
        id: 'camp-05',
        code: 'RPD05',
        name: 'Butwal Gyno Screening Camp',
        province: 'Lumbini',
        district: 'Rupandehi',
        municipality: 'Butwal',
        ward: '09',
        date: DateTime(2026, 9, 10),
      ),
      doctor: const DoctorProfile(name: 'Nabin Pandey', nmcNumber: '16234'),
      nurse: const NurseProfile(name: 'Laxmi Chaudhary', registrationNumber: '55210'),
      expectedEcgStatus: 'Normal Sinus',
      expectedComplaints: {
        'urine': {
          'duration': '< 1 year',
          'options': ['urge', 'continuous flow'],
          'remarks': 'Frequency and burning',
        },
        'discharge': {
          'duration': '< 1 year',
          'options': ['green', 'grey'],
          'remarks': 'Mild irritation',
        },
      },
      patient: PatientModel(
        id: 'pat-audit-05',
        patientId: 'GC-RPD05-2026-00088',
        campId: 'camp-05',
        campCode: 'RPD05',
        intakeDate: DateTime(2026, 9, 10),
        firstName: 'Sarita',
        surname: 'Tharu',
        age: 38,
        spouseOrFatherName: 'Chandra Tharu',
        relationshipType: 'Father',
        mobile: '9817123456',
        contactPerson: 'Suman Tharu',
        contactMobile: '9857098765',
        maritalStatus: 'divorced',
        maritalAge: 19,
        province: 'Lumbini',
        district: 'Rupandehi',
        municipality: 'Butwal',
        ward: '09',
        reasonsForVisit: ['problems passing urine', 'discharge and or itching'],
        consentTreatment: true,
        consentStoreMedicalInfo: true,
        treatmentLevel: 'gyno_checkup',
        createdAt: DateTime(2026, 9, 10),
        createdByUserId: 'usr-01',
        createdByDeviceId: 'dev-01',
      ),
      visit: ClinicalVisitModel(
        id: 'vis-audit-05',
        patientId: 'GC-RPD05-2026-00088',
        campId: 'camp-05',
        visitDate: DateTime(2026, 9, 10),
        anamnesisDate: DateTime(2026, 9, 10),
        examDate: DateTime(2026, 9, 10),
        labTestDate: DateTime(2026, 9, 10),
        conclusionDate: DateTime(2026, 9, 10),
        treatmentDate: DateTime(2026, 9, 10),
        outtakeDate: DateTime(2026, 9, 10),
        deliveries: 2,
        livingChildren: 2,
        abortions: 0,
        anamnesisComplaints: {
          'clinicalComplaints': ['urine', 'discharge'],
          'complaintsDuration': '< 1 year',
          'urine': {
            'duration': '< 1 year',
            'options': ['urge', 'continuous flow'],
            'remarks': 'Frequency and burning',
          },
          'discharge': {
            'duration': '< 1 year',
            'options': ['green', 'grey'],
            'remarks': 'Mild irritation',
          },
        },
        uterusInside: true,
        pelvicFloorTone: 'hypertonic',
        vulvaRemarks: 'Perineal warts',
        vaginaRemarks: 'Normal',
        cervixRemarks: 'Normal',
        uterusRemarks: 'Normal',
        popAnteriorStage: 1,
        popMiddleStage: 0,
        popPosteriorStage: 0,
        highestPopStage: 1,
        urineTest: 'pos',
        pregnancyTest: 'neg',
        systolicBp: 118,
        diastolicBp: 76,
        pulse: 80,
        spo2: 98,
        glucose: 108,
        ecgNotes: 'Normal Sinus',
        diagnoses: [
          'cystitis',
          'urge incontinence',
          'hypertonic pelvic floor muscle',
          'condylomata',
        ],
        counseling: ['urge incontinence'],
        medications: ['nitrofurantoine', 'ciproflox', 'mirasin'],
        treatmentLevel: 'gyno_checkup',
        followUpNeeded: true,
        followUpDestination: 'Health Post',
        outtakeNotes: 'Pelvic floor relaxation taught. Repeat urine test in 7 days.',
        primaryDoctorName: 'Dr. Nabin Pandey',
        attendingDoctorNames: ['Dr. Nabin Pandey'],
        primaryNurseName: 'Laxmi Chaudhary',
        attendingNurseNames: ['Laxmi Chaudhary'],
        createdAt: DateTime(2026, 9, 10),
        createdByUserId: 'usr-01',
      ),
    ),

    // SAMPLE 6: Karnali / Surkhet — Infertility + Myoma + Ovarian Tumor, loc government referral
    SampleAuditCase(
      index: 6,
      slug: '06_kalpana_shahi_karnali_infertility',
      camp: makeCamp(
        id: 'camp-06',
        code: 'SKT06',
        name: 'Birendranagar Gyno Camp',
        province: 'Karnali',
        district: 'Surkhet',
        municipality: 'Birendranag',
        ward: '05',
        date: DateTime(2026, 10, 5),
      ),
      doctor: const DoctorProfile(name: 'Kamal Rokaya', nmcNumber: '17890'),
      nurse: const NurseProfile(name: 'Radha Budha', registrationNumber: '62109'),
      expectedEcgStatus: 'Normal Sinus',
      expectedComplaints: {
        'infertility': {
          'duration': '> 5 years',
          'options': <String>[],
          'remarks': 'Trying to conceive 6 years',
        },
        'menstrual': {
          'duration': '',
          'options': ['metrorrhagia'],
          'remarks': 'Intermenstrual spotting',
        },
      },
      patient: PatientModel(
        id: 'pat-audit-06',
        patientId: 'GC-SKT06-2026-00105',
        campId: 'camp-06',
        campCode: 'SKT06',
        intakeDate: DateTime(2026, 10, 5),
        firstName: 'Kalpana',
        surname: 'Shahi',
        age: 33,
        spouseOrFatherName: 'Dipendra Shahi',
        relationshipType: 'Husband',
        mobile: '9848054321',
        contactPerson: 'Nabin Shahi',
        contactMobile: '9868112244',
        maritalStatus: 'married',
        maritalAge: 23,
        province: 'Karnali',
        district: 'Surkhet',
        municipality: 'Birendranag',
        ward: '05',
        reasonsForVisit: ['infertility', 'menstrual problem'],
        consentTreatment: true,
        consentStoreMedicalInfo: true,
        treatmentLevel: 'gyno_checkup',
        createdAt: DateTime(2026, 10, 5),
        createdByUserId: 'usr-01',
        createdByDeviceId: 'dev-01',
      ),
      visit: ClinicalVisitModel(
        id: 'vis-audit-06',
        patientId: 'GC-SKT06-2026-00105',
        campId: 'camp-06',
        visitDate: DateTime(2026, 10, 5),
        anamnesisDate: DateTime(2026, 10, 5),
        examDate: DateTime(2026, 10, 5),
        labTestDate: DateTime(2026, 10, 5),
        conclusionDate: DateTime(2026, 10, 5),
        treatmentDate: DateTime(2026, 10, 5),
        outtakeDate: DateTime(2026, 10, 5),
        deliveries: 0,
        livingChildren: 0,
        abortions: 2,
        anamnesisComplaints: {
          'clinicalComplaints': ['infertility', 'menstrual'],
          'complaintsDuration': '> 5 years',
          'infertility': {
            'duration': '> 5 years',
            'options': <String>[],
            'remarks': 'Trying to conceive 6 years',
          },
          'menstrual': {
            'duration': '',
            'options': ['metrorrhagia'],
            'remarks': 'Intermenstrual spotting',
          },
        },
        uterusInside: true,
        pelvicFloorTone: 'normal',
        vulvaRemarks: 'Normal',
        vaginaRemarks: 'Normal',
        cervixRemarks: 'Normal',
        uterusRemarks: 'Enlarged 12 weeks irregular',
        popAnteriorStage: 0,
        popMiddleStage: 0,
        popPosteriorStage: 0,
        highestPopStage: 0,
        urineTest: 'normal',
        pregnancyTest: 'neg',
        systolicBp: 122,
        diastolicBp: 78,
        pulse: 74,
        spo2: 97,
        glucose: 99,
        ecgNotes: 'Normal Sinus',
        diagnoses: ['infertility', 'myoma', 'ovarian tumor'],
        surgicalReferral: 'loc government',
        medications: const [],
        customMedication: 'Folic acid 5mg OD',
        treatmentLevel: 'gyno_checkup',
        followUpNeeded: true,
        followUpDestination: 'Karnali Provincial Hospital',
        outtakeNotes: 'Referred for pelvic ultrasound and myomectomy workup.',
        primaryDoctorName: 'Dr. Kamal Rokaya',
        attendingDoctorNames: ['Dr. Kamal Rokaya'],
        primaryNurseName: 'Radha Budha',
        attendingNurseNames: ['Radha Budha'],
        createdAt: DateTime(2026, 10, 5),
        createdByUserId: 'usr-01',
      ),
    ),

    // SAMPLE 7: Sudurpashchim / Kailali — Suspected Cervical Carcinoma, Postmenopausal Bleeding, Treatment Consent NO
    SampleAuditCase(
      index: 7,
      slug: '07_parvati_bhatta_sudurpashchim_oncology',
      camp: makeCamp(
        id: 'camp-07',
        code: 'KLL07',
        name: 'Dhangadhi Oncology Screening Camp',
        province: 'Sudurpashchim',
        district: 'Kailali',
        municipality: 'Dhangadhi',
        ward: '12',
        date: DateTime(2026, 10, 20),
      ),
      doctor: const DoctorProfile(name: 'Devendra Bohara', nmcNumber: '19401'),
      nurse: const NurseProfile(name: 'Saraswati Joshi', registrationNumber: '71345'),
      expectedEcgStatus: 'Normal Sinus',
      expectedComplaints: {
        'menstrual': {
          'duration': '',
          'options': ['postmenopausal bleeding'],
          'remarks': 'Postcoital bleeding noted',
        },
        'discharge': {
          'duration': '< 1 year',
          'options': ['smelly'],
          'remarks': 'Blood stained foul fluid',
        },
      },
      patient: PatientModel(
        id: 'pat-audit-07',
        patientId: 'GC-KLL07-2026-00142',
        campId: 'camp-07',
        campCode: 'KLL07',
        intakeDate: DateTime(2026, 10, 20),
        firstName: 'Parvati',
        surname: 'Bhatta',
        age: 57,
        spouseOrFatherName: 'Ganesh Bhatta',
        relationshipType: 'Husband',
        mobile: '9848498765',
        contactPerson: 'Ramesh Pant',
        contactMobile: '9809412345',
        maritalStatus: 'married',
        maritalAge: 17,
        province: 'Sudurpashchim',
        district: 'Kailali',
        municipality: 'Dhangadhi',
        ward: '12',
        reasonsForVisit: ['menstrual problem', 'discharge and or itching'],
        consentTreatment: false,
        consentStoreMedicalInfo: true,
        treatmentLevel: 'gyno_checkup',
        createdAt: DateTime(2026, 10, 20),
        createdByUserId: 'usr-01',
        createdByDeviceId: 'dev-01',
      ),
      visit: ClinicalVisitModel(
        id: 'vis-audit-07',
        patientId: 'GC-KLL07-2026-00142',
        campId: 'camp-07',
        visitDate: DateTime(2026, 10, 20),
        anamnesisDate: DateTime(2026, 10, 20),
        examDate: DateTime(2026, 10, 20),
        labTestDate: DateTime(2026, 10, 20),
        conclusionDate: DateTime(2026, 10, 20),
        treatmentDate: DateTime(2026, 10, 20),
        outtakeDate: DateTime(2026, 10, 20),
        deliveries: 5,
        livingChildren: 4,
        abortions: 1,
        anamnesisComplaints: {
          'clinicalComplaints': ['menstrual', 'discharge'],
          'complaintsDuration': '< 1 year',
          'menstrual': {
            'duration': '',
            'options': ['postmenopausal bleeding'],
            'remarks': 'Postcoital bleeding noted',
          },
          'discharge': {
            'duration': '< 1 year',
            'options': ['smelly'],
            'remarks': 'Blood stained foul fluid',
          },
        },
        uterusInside: true,
        pelvicFloorTone: 'normal',
        vulvaRemarks: 'Normal',
        vaginaRemarks: 'Blood tinged fluid',
        cervixRemarks: 'Friable exophytic lesion',
        uterusRemarks: 'Parametrial thickening',
        popAnteriorStage: 0,
        popMiddleStage: 1,
        popPosteriorStage: 1,
        highestPopStage: 1,
        urineTest: 'normal',
        pregnancyTest: 'neg',
        systolicBp: 134,
        diastolicBp: 84,
        pulse: 86,
        spo2: 97,
        glucose: 118,
        ecgNotes: 'Normal Sinus',
        diagnoses: ['cervical carcinoma'],
        surgicalReferral: 'loc government',
        medications: ['metronidazol'],
        treatmentLevel: 'gyno_checkup',
        followUpNeeded: true,
        followUpDestination: 'Seti Provincial Hospital',
        outtakeNotes: 'Urgent oncology referral for punch biopsy and staging.',
        primaryDoctorName: 'Dr. Devendra Bohara',
        attendingDoctorNames: ['Dr. Devendra Bohara'],
        primaryNurseName: 'Saraswati Joshi',
        attendingNurseNames: ['Saraswati Joshi'],
        createdAt: DateTime(2026, 10, 20),
        createdByUserId: 'usr-01',
      ),
    ),

    // SAMPLE 8: Bagmati / Lalitpur — Routine Checkup, Positive Pregnancy Test, Counseling Level
    SampleAuditCase(
      index: 8,
      slug: '08_asmita_maharjan_bagmati_pregnancy',
      camp: makeCamp(
        id: 'camp-08',
        code: 'LTP08',
        name: 'Lalitpur Maternal Wellness Camp',
        province: 'Bagmati',
        district: 'Lalitpur',
        municipality: 'Lalitpur',
        ward: '16',
        date: DateTime(2026, 10, 28),
      ),
      doctor: const DoctorProfile(name: 'Meera Shakya', nmcNumber: '20115'),
      nurse: const NurseProfile(name: 'Sabitri Shrestha', registrationNumber: '82011'),
      expectedEcgStatus: 'Not Done',
      expectedComplaints: {
        'checkup': {
          'duration': '',
          'options': ['routine screening'],
          'remarks': 'Amenorrhoea 8 weeks ANC check',
        },
      },
      patient: PatientModel(
        id: 'pat-audit-08',
        patientId: 'GC-LTP08-2026-00189',
        campId: 'camp-08',
        campCode: 'LTP08',
        intakeDate: DateTime(2026, 10, 28),
        firstName: 'Asmita',
        surname: 'Maharjan',
        age: 25,
        spouseOrFatherName: 'Sujan Maharjan',
        relationshipType: 'Husband',
        mobile: '9841765432',
        contactPerson: 'Sabina KC',
        contactMobile: '9851223344',
        maritalStatus: 'married',
        maritalAge: 22,
        province: 'Bagmati',
        district: 'Lalitpur',
        municipality: 'Lalitpur',
        ward: '16',
        reasonsForVisit: ['checkup'],
        consentTreatment: true,
        consentStoreMedicalInfo: true,
        treatmentLevel: 'counseling',
        createdAt: DateTime(2026, 10, 28),
        createdByUserId: 'usr-01',
        createdByDeviceId: 'dev-01',
      ),
      visit: ClinicalVisitModel(
        id: 'vis-audit-08',
        patientId: 'GC-LTP08-2026-00189',
        campId: 'camp-08',
        visitDate: DateTime(2026, 10, 28),
        anamnesisDate: DateTime(2026, 10, 28),
        examDate: DateTime(2026, 10, 28),
        labTestDate: DateTime(2026, 10, 28),
        conclusionDate: DateTime(2026, 10, 28),
        treatmentDate: DateTime(2026, 10, 28),
        outtakeDate: DateTime(2026, 10, 28),
        deliveries: 1,
        livingChildren: 1,
        abortions: 0,
        anamnesisComplaints: {
          'clinicalComplaints': ['checkup'],
          'complaintsDuration': '',
          'checkup': {
            'duration': '',
            'options': ['routine screening'],
            'remarks': 'Amenorrhoea 8 weeks ANC check',
          },
        },
        uterusInside: true,
        pelvicFloorTone: 'normal',
        vulvaRemarks: 'Normal',
        vaginaRemarks: 'Normal',
        cervixRemarks: 'Bluish Chadwick sign',
        uterusRemarks: '8 weeks soft globular',
        popAnteriorStage: 0,
        popMiddleStage: 0,
        popPosteriorStage: 0,
        highestPopStage: 0,
        urineTest: 'normal',
        pregnancyTest: 'pos',
        systolicBp: 110,
        diastolicBp: 70,
        pulse: 82,
        spo2: 99,
        glucose: 92,
        ecgNotes: 'Not Done',
        diagnoses: ['pregnancy'],
        medications: const [],
        customMedication: 'Iron and Folic Acid OD',
        treatmentLevel: 'counseling',
        followUpNeeded: true,
        followUpDestination: 'Health Post',
        outtakeNotes: 'Enrolled for ANC visit at health post. Dating scan advised.',
        primaryDoctorName: 'Dr. Meera Shakya',
        attendingDoctorNames: ['Dr. Meera Shakya'],
        primaryNurseName: 'Sabitri Shrestha',
        attendingNurseNames: ['Sabitri Shrestha'],
        createdAt: DateTime(2026, 10, 28),
        createdByUserId: 'usr-01',
      ),
    ),

    // SAMPLE 9: Bagmati / Sindhupalchok — Long District Name, POP Stage 2, Plain Ring 60mm, Comorbid Hypertension & Diabetes
    SampleAuditCase(
      index: 9,
      slug: '09_pemba_sherpa_sindhupalchok_pop2_ring',
      camp: makeCamp(
        id: 'camp-09',
        code: 'SPC09',
        name: 'Chautara Mountain Outreach Camp',
        province: 'Bagmati',
        district: 'Sindhupalchok',
        municipality: 'Chautara',
        ward: '01',
        date: DateTime(2026, 11, 1),
      ),
      doctor: const DoctorProfile(name: 'Rajesh Karmacharya', nmcNumber: '22310'),
      nurse: const NurseProfile(name: 'Dolma Tamang', registrationNumber: '91044'),
      expectedEcgStatus: 'Abnormal',
      expectedComplaints: {
        'prolapse': {
          'duration': '> 1 year',
          'options': <String>[],
          'remarks': 'Reducible bulge at introitus',
        },
        'stool': {
          'duration': '> 1 year',
          'options': <String>[],
          'remarks': 'Constipation and straining',
        },
        'lower_back_pain': {
          'duration': '> 1 year',
          'options': <String>[],
          'remarks': 'Chronic lumbar ache',
        },
      },
      patient: PatientModel(
        id: 'pat-audit-09',
        patientId: 'GC-SPC09-2026-00215',
        campId: 'camp-09',
        campCode: 'SPC09',
        intakeDate: DateTime(2026, 11, 1),
        firstName: 'Pemba',
        surname: 'Sherpa',
        age: 61,
        spouseOrFatherName: 'Pasang Sherpa',
        relationshipType: 'Husband',
        mobile: '9849876543',
        contactPerson: 'Tenzin Lama',
        contactMobile: '9860123456',
        maritalStatus: 'married',
        maritalAge: 20,
        province: 'Bagmati',
        district: 'Sindhupalchok',
        municipality: 'Chautara',
        ward: '01',
        reasonsForVisit: ['something hanging out', 'problems passing stool', 'pain'],
        consentTreatment: true,
        consentStoreMedicalInfo: true,
        treatmentLevel: 'gyno_checkup',
        createdAt: DateTime(2026, 11, 1),
        createdByUserId: 'usr-01',
        createdByDeviceId: 'dev-01',
      ),
      visit: ClinicalVisitModel(
        id: 'vis-audit-09',
        patientId: 'GC-SPC09-2026-00215',
        campId: 'camp-09',
        visitDate: DateTime(2026, 11, 1),
        anamnesisDate: DateTime(2026, 11, 1),
        examDate: DateTime(2026, 11, 1),
        labTestDate: DateTime(2026, 11, 1),
        conclusionDate: DateTime(2026, 11, 1),
        treatmentDate: DateTime(2026, 11, 1),
        outtakeDate: DateTime(2026, 11, 1),
        deliveries: 3,
        livingChildren: 3,
        abortions: 0,
        anamnesisComplaints: {
          'clinicalComplaints': ['prolapse', 'stool', 'lower_back_pain'],
          'complaintsDuration': '> 1 year',
          'prolapse': {
            'duration': '> 1 year',
            'options': <String>[],
            'remarks': 'Reducible bulge at introitus',
          },
          'stool': {
            'duration': '> 1 year',
            'options': <String>[],
            'remarks': 'Constipation and straining',
          },
          'lower_back_pain': {
            'duration': '> 1 year',
            'options': <String>[],
            'remarks': 'Chronic lumbar ache',
          },
        },
        uterusInside: true,
        pelvicFloorTone: 'weak',
        vulvaRemarks: 'Normal',
        vaginaRemarks: 'Mild anterior laxity',
        cervixRemarks: 'Normal',
        uterusRemarks: 'Normal',
        popAnteriorStage: 2,
        popMiddleStage: 2,
        popPosteriorStage: 2,
        highestPopStage: 2,
        urineTest: 'pos',
        pregnancyTest: 'neg',
        systolicBp: 152,
        diastolicBp: 94,
        pulse: 79,
        spo2: 96,
        glucose: 196,
        ecgNotes: 'Abnormal: Borderline ST depression',
        diagnoses: ['atrophy vagina', 'weak pelvic floor muscle'],
        pessaryType: 'ring',
        pessarySize: '60',
        counseling: ['weak pelvic floor', 'POP'],
        medications: ['estradiol crème'],
        treatmentLevel: 'gyno_checkup',
        followUpNeeded: true,
        followUpDestination: 'GynaeSupport Nurse',
        outtakeNotes: '60mm ring pessary fitted comfortably. Medical consult for BP and sugar.',
        primaryDoctorName: 'Dr. Rajesh Karmacharya',
        attendingDoctorNames: ['Dr. Rajesh Karmacharya'],
        primaryNurseName: 'Dolma Tamang',
        attendingNurseNames: ['Dolma Tamang'],
        createdAt: DateTime(2026, 11, 1),
        createdByUserId: 'usr-01',
      ),
    ),
  ];

  group('Full Blank Form & 9 Diverse Samples End-to-End OCR & SQLite Audit', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late PatientRepository patientRepo;
    late OcrRepository ocrRepo;

    setUp(() async {
      if (!outDir.existsSync()) {
        outDir.createSync(recursive: true);
      }
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      auditRepo = AuditRepository(databaseService: dbService);
      patientRepo = PatientRepository(
        databaseService: dbService,
        auditRepository: auditRepo,
      );
      ocrRepo = OcrRepository(
        ocrService: ocrService,
        patientRepository: patientRepo,
        auditRepository: auditRepo,
      );
    });

    tearDown(() async {
      await testDb.close();
    });

    test('0. Blank Yellow Form Control: Verify 0% Hallucination Across Every Blank Field', () async {
      final blankCamp = samples.first.camp;
      final blankBytes = await pdfService.generatePatientRegistrationFormPdf(
        camp: blankCamp,
        blankDoctorLines: true,
        blankNurseLines: true,
        page1Layout: BlankFormPage1Layout.grid,
      );
      final blankPdf = File('${outDir.path}/00_blank_yellow_form_control.pdf');
      blankPdf.writeAsBytesSync(blankBytes);

      final pages = await extractPdfPages(blankPdf);
      final p1 = ocrService.parseFormText(pages.page1, pageNumber: 1);
      final p2 = ocrService.parseFormText(pages.page2, pageNumber: 2);
      final merged = OcrScanResultModel.merge(p1, p2);

      final failures = <String>[];
      void check(String label, dynamic actual, dynamic expected) {
        if (actual != expected) {
          failures.add('[BLANK] $label => expected: $expected | actual: $actual');
        }
      }

      check('patientTokenId', merged.patientTokenId, null);
      check('treatmentLevel', merged.treatmentLevel, null);
      check('firstName', merged.demographics['firstName'], null);
      check('surname', merged.demographics['surname'], null);
      check('age', merged.demographics['age'], null);
      check('mobile', merged.demographics['mobile'], '');
      check('maritalAge', merged.demographics['maritalAge'], null);
      check('reasonsForVisit.isEmpty', (merged.demographics['reasonsForVisit'] as List).isEmpty, true);
      check('clinicalComplaints.isEmpty', (merged.obstetrics['clinicalComplaints'] as List).isEmpty, true);
      check('systolicBp', merged.vitals['systolicBp'], null);
      check('diastolicBp', merged.vitals['diastolicBp'], null);
      check('pulseRate', merged.vitals['pulseRate'], null);
      check('spo2', merged.vitals['spo2'], null);
      check('bloodGlucose', merged.vitals['bloodGlucose'], null);
      check('highestPopStage', merged.popStaging['highestPopStage'], 0);
      check('diagnoses.isEmpty', merged.diagnoses.isEmpty, true);
      check('counseling.isEmpty', merged.counseling.isEmpty, true);
      check('medications.isEmpty', merged.medications.isEmpty, true);
      check('ringPessary', merged.ringPessary, false);
      check('surgicalReferral', merged.surgicalReferral, null);
      check('followUpDestination', merged.followUpDestination, null);
      check('examiningDoctor', merged.examiningDoctor, null);
      check('examiningNurse', merged.examiningNurse, null);

      if (failures.isNotEmpty) {
        // ignore: avoid_print
        print('\n=== BLANK FORM CONTROL FAILURES (${failures.length}) ===\n${failures.join('\n')}');
      }
      expect(failures, isEmpty, reason: failures.join('\n'));
    });

    test('1-9. Nine Distinct Filled Samples: Verify 100% Blank-Form Field Detection & SQLite Persistence', () async {
      // Confirm 100% coverage of Blank Form options across the 9 samples
      final allReasonsCovered = samples.expand((s) => s.patient.reasonsForVisit).toSet();
      expect(
        allReasonsCovered,
        containsAll(ClinicalConstants.visitReasonOptions.keys),
        reason: '9 samples must cover all 8 Reasons for Visit',
      );
      final allProvincesCovered = samples.map((s) => s.patient.province).toSet();
      expect(
        allProvincesCovered,
        containsAll(ClinicalConstants.nepalProvinces),
        reason: '9 samples must cover all 7 Nepal Provinces',
      );
      final allDiagnosesCovered = samples.expand((s) => s.visit.diagnoses).toSet();
      expect(
        allDiagnosesCovered,
        containsAll(ClinicalConstants.defaultDiagnoses),
        reason: '9 samples must cover all 21 Standard Diagnoses',
      );
      final allMedsCovered = samples.expand((s) => s.visit.medications).toSet();
      expect(
        allMedsCovered,
        containsAll(ClinicalConstants.defaultMedications),
        reason: '9 samples must cover all 10 Standard Medications',
      );

      int totalChecks = 0;
      int passedChecks = 0;
      final allFailures = <String>[];

      for (final sc in samples) {
        final pdfBytes = await pdfService.generatePatientRegistrationFormPdf(
          patient: sc.patient,
          camp: sc.camp,
          visit: sc.visit,
          doctor: sc.doctor,
          nurse: sc.nurse,
          allDoctorsChecklist: sc.allDoctorsChecklist,
          allNursesChecklist: sc.allNursesChecklist,
          page1Layout: BlankFormPage1Layout.grid,
        );
        final pdfFile = File('${outDir.path}/${sc.slug}.pdf');
        pdfFile.writeAsBytesSync(pdfBytes);

        final pages = await extractPdfPages(pdfFile);
        final p1 = ocrService.parseFormText(pages.page1, pageNumber: 1);
        final p2 = ocrService.parseFormText(pages.page2, pageNumber: 2);
        final scan = OcrScanResultModel.merge(p1, p2);

        void verify(String field, bool condition, {required dynamic expected, required dynamic actual}) {
          totalChecks++;
          if (condition) {
            passedChecks++;
          } else {
            allFailures.add('[Sample ${sc.index}: ${sc.patient.firstName} ${sc.patient.surname}] $field => EXPECTED: $expected | ACTUAL: $actual');
          }
        }

        final expectedBs = toBsString(sc.patient.intakeDate);

        // 1. Header, Token & Triage
        verify('patientTokenId', scan.patientTokenId == sc.patient.patientId, expected: sc.patient.patientId, actual: scan.patientTokenId);
        verify('treatmentLevel', scan.treatmentLevel == sc.patient.treatmentLevel, expected: sc.patient.treatmentLevel, actual: scan.treatmentLevel);
        verify('intakeDate (BS)', scan.intakeDate == expectedBs, expected: expectedBs, actual: scan.intakeDate);

        // 2. Section A: Demographics
        final d = scan.demographics;
        verify('firstName', (d['firstName'] as String?)?.toLowerCase() == sc.patient.firstName.toLowerCase(), expected: sc.patient.firstName, actual: d['firstName']);
        verify('surname', (d['surname'] as String?)?.toLowerCase() == sc.patient.surname.toLowerCase(), expected: sc.patient.surname, actual: d['surname']);
        verify('age', d['age'] == sc.patient.age, expected: sc.patient.age, actual: d['age']);

        final scanRel = '${d['relativeName'] ?? ''} ${d['relativeSurname'] ?? ''}'.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
        final expRelFirst = sc.patient.spouseOrFatherName!.split(' ').first.toLowerCase();
        final expRelLast = sc.patient.spouseOrFatherName!.split(' ').last.toLowerCase();
        verify(
          'relativeName + relativeSurname',
          scanRel.contains(expRelFirst) && scanRel.contains(expRelLast),
          expected: sc.patient.spouseOrFatherName,
          actual: scanRel,
        );
        verify('relativeType', d['relativeType'] == sc.patient.relationshipType, expected: sc.patient.relationshipType, actual: d['relativeType']);
        verify('mobile', d['mobile'] == sc.patient.mobile, expected: sc.patient.mobile, actual: d['mobile']);
        verify('ward', d['ward'] == sc.patient.ward, expected: sc.patient.ward, actual: d['ward']);

        final scanCp = (d['contactPerson'] as String? ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), '');
        final rawExpCp = (sc.patient.contactPerson ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
        final boxedExpCp = rawExpCp.length > 10 ? rawExpCp.substring(0, 10) : rawExpCp;
        final expCpTrunc = boxedExpCp.toLowerCase().replaceAll(RegExp(r'\s+'), '');
        verify(
          'contactPerson',
          scanCp.isNotEmpty && scanCp.startsWith(expCpTrunc),
          expected: sc.patient.contactPerson,
          actual: d['contactPerson'],
        );
        verify('contactMobile', d['contactMobile'] == sc.patient.contactMobile, expected: sc.patient.contactMobile, actual: d['contactMobile']);
        verify('maritalStatus', d['maritalStatus'] == sc.patient.maritalStatus, expected: sc.patient.maritalStatus, actual: d['maritalStatus']);
        verify('maritalAge', d['maritalAge'] == sc.patient.maritalAge, expected: sc.patient.maritalAge, actual: d['maritalAge']);

        final scanMuni = (d['municipality'] as String? ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), '');
        final expMuni = sc.patient.municipality.toLowerCase().replaceAll(RegExp(r'\s+'), '');
        final expMuniTrunc = expMuni.length > 12 ? expMuni.substring(0, 12) : expMuni;
        verify(
          'municipality (Palika)',
          scanMuni.isNotEmpty && scanMuni.startsWith(expMuniTrunc),
          expected: sc.patient.municipality,
          actual: d['municipality'],
        );
        verify(
          'district',
          (d['district'] as String? ?? '').toLowerCase() == sc.patient.district.toLowerCase(),
          expected: sc.patient.district,
          actual: d['district'],
        );
        verify(
          'province',
          (d['province'] as String? ?? '').toLowerCase() == sc.patient.province.toLowerCase(),
          expected: sc.patient.province,
          actual: d['province'],
        );

        // 3. Section B: Reasons for Visit & Consents
        final scanReasons = (d['reasonsForVisit'] as List? ?? []).map((e) => e.toString()).toSet();
        final expReasons = sc.patient.reasonsForVisit.toSet();
        verify('reasonsForVisit (exact set)', scanReasons.length == expReasons.length && scanReasons.containsAll(expReasons), expected: expReasons, actual: scanReasons);
        verify('consentTreatment', d['consentTreatment'] == sc.patient.consentTreatment, expected: sc.patient.consentTreatment, actual: d['consentTreatment']);
        verify('consentStoreMedicalInfo', d['consentStoreMedicalInfo'] == sc.patient.consentStoreMedicalInfo, expected: sc.patient.consentStoreMedicalInfo, actual: d['consentStoreMedicalInfo']);

        // 4. Station 1: Anamnesis & Obstetric History
        final o = scan.obstetrics;
        verify('anamnesisDate (BS)', scan.anamnesisDate == expectedBs, expected: expectedBs, actual: scan.anamnesisDate);
        verify('deliveries', o['deliveries'] == sc.visit.deliveries, expected: sc.visit.deliveries, actual: o['deliveries']);
        verify('livingChildren', o['livingChildren'] == sc.visit.livingChildren, expected: sc.visit.livingChildren, actual: o['livingChildren']);
        verify('abortions', o['abortions'] == sc.visit.abortions, expected: sc.visit.abortions, actual: o['abortions']);

        final expDur = (sc.visit.anamnesisComplaints['complaintsDuration'] as String? ?? '');
        if (expDur.isNotEmpty) {
          verify('complaintsDuration', o['complaintsDuration'] == expDur, expected: expDur, actual: o['complaintsDuration']);
        }

        final scanComplaints = (o['clinicalComplaints'] as List? ?? []).map((e) => e.toString()).toSet();
        final expComplaints = sc.expectedComplaints.keys.toSet();
        verify('clinicalComplaints', scanComplaints.containsAll(expComplaints), expected: expComplaints, actual: scanComplaints);

        final scanDetails = (o['complaintDetails'] as Map?) ?? {};
        for (final entry in sc.expectedComplaints.entries) {
          final cKey = entry.key;
          final expMap = entry.value;
          final actMap = (scanDetails[cKey] as Map?) ?? {};
          final eDur = expMap['duration'] as String? ?? '';
          if (eDur.isNotEmpty) {
            verify('complaintDetails[$cKey].duration', actMap['duration'] == eDur, expected: eDur, actual: actMap['duration']);
          }
          final eOpts = (expMap['options'] as List? ?? []).map((e) => e.toString().toLowerCase()).toList();
          if (eOpts.isNotEmpty) {
            final actSub = (actMap['subOption']?.toString() ?? actMap['options']?.toString() ?? '').toLowerCase();
            verify(
              'complaintDetails[$cKey].subOptions',
              eOpts.every((opt) => actSub.contains(opt)),
              expected: eOpts,
              actual: actSub,
            );
          }
          final eRem = (expMap['remarks'] as String? ?? '').trim();
          if (eRem.isNotEmpty) {
            final actRem = (actMap['remarks']?.toString() ?? '').trim();
            verify(
              'complaintDetails[$cKey].remarks',
              actRem.toLowerCase() == eRem.toLowerCase(),
              expected: eRem,
              actual: actRem,
            );
          }
        }

        // 5. Station 2: POP & Physical Exam
        final p = scan.popStaging;
        verify('examDate (BS)', scan.examDate == expectedBs, expected: expectedBs, actual: scan.examDate);
        verify('uterusInside', p['uterusInside'] == sc.visit.uterusInside, expected: sc.visit.uterusInside, actual: p['uterusInside']);
        verify('pelvicFloorTone', p['pelvicFloorTone'] == sc.visit.pelvicFloorTone, expected: sc.visit.pelvicFloorTone, actual: p['pelvicFloorTone']);
        verify('anteriorStage', p['anteriorStage'] == sc.visit.popAnteriorStage, expected: sc.visit.popAnteriorStage, actual: p['anteriorStage']);
        verify('middleStage', p['middleStage'] == sc.visit.popMiddleStage, expected: sc.visit.popMiddleStage, actual: p['middleStage']);
        verify('posteriorStage', p['posteriorStage'] == sc.visit.popPosteriorStage, expected: sc.visit.popPosteriorStage, actual: p['posteriorStage']);
        verify('highestPopStage', p['highestPopStage'] == sc.visit.highestPopStage, expected: sc.visit.highestPopStage, actual: p['highestPopStage']);

        bool matchRemark(String? actual, String? expected) {
          final a = (actual ?? '').trim().toLowerCase();
          final e = (expected ?? 'normal').trim().toLowerCase();
          if (a.contains('normal or')) return false;
          if (e == 'normal') return a.startsWith('normal');
          return a == e;
        }
        verify('vulvaRemarks', matchRemark(p['vulvaRemarks'] as String?, sc.visit.vulvaRemarks), expected: sc.visit.vulvaRemarks, actual: p['vulvaRemarks']);
        verify('vaginaRemarks', matchRemark(p['vaginaRemarks'] as String?, sc.visit.vaginaRemarks), expected: sc.visit.vaginaRemarks, actual: p['vaginaRemarks']);
        verify('cervixRemarks', matchRemark(p['cervixRemarks'] as String?, sc.visit.cervixRemarks), expected: sc.visit.cervixRemarks, actual: p['cervixRemarks']);
        verify('uterusRemarks', matchRemark(p['uterusRemarks'] as String?, sc.visit.uterusRemarks), expected: sc.visit.uterusRemarks, actual: p['uterusRemarks']);

        // 6. Station 3: Labs, Vitals & ECG
        final v = scan.vitals;
        verify('labTestDate (BS)', scan.labTestDate == expectedBs, expected: expectedBs, actual: scan.labTestDate);
        verify('urineTest', v['urineTest'] == sc.visit.urineTest, expected: sc.visit.urineTest, actual: v['urineTest']);
        verify('pregnancyTest', v['pregnancyTest'] == sc.visit.pregnancyTest, expected: sc.visit.pregnancyTest, actual: v['pregnancyTest']);
        verify('systolicBp', v['systolicBp'] == sc.visit.systolicBp, expected: sc.visit.systolicBp, actual: v['systolicBp']);
        verify('diastolicBp', v['diastolicBp'] == sc.visit.diastolicBp, expected: sc.visit.diastolicBp, actual: v['diastolicBp']);
        verify('pulseRate', v['pulseRate'] == sc.visit.pulse, expected: sc.visit.pulse, actual: v['pulseRate']);
        verify('spo2', v['spo2'] == sc.visit.spo2, expected: sc.visit.spo2, actual: v['spo2']);
        verify('bloodGlucose', v['bloodGlucose'] == sc.visit.glucose, expected: sc.visit.glucose, actual: v['bloodGlucose']);
        verify('ecg', v['ecg'] == sc.expectedEcgStatus, expected: sc.expectedEcgStatus, actual: v['ecg']);
        verify(
          'ecgNotes',
          (v['ecgNotes'] as String? ?? '').toLowerCase() == (sc.visit.ecgNotes ?? '').toLowerCase(),
          expected: sc.visit.ecgNotes,
          actual: v['ecgNotes'],
        );

        // 7. Station 4: Confirmed Diagnoses (including Custom Other: and checking no cross-station leak)
        verify('conclusionDate (BS)', scan.conclusionDate == expectedBs, expected: expectedBs, actual: scan.conclusionDate);
        final scanDiagLow = scan.diagnoses.map((x) => x.toLowerCase()).toSet();
        for (final diag in sc.visit.diagnoses) {
          verify('diagnosis[$diag]', scanDiagLow.contains(diag.toLowerCase()), expected: diag, actual: scan.diagnoses);
        }

        // 8. Station 5: Treatment, Pessary, Counseling, Referral, Medications & Custom Medication
        verify('treatmentDate (BS)', scan.treatmentDate == expectedBs, expected: expectedBs, actual: scan.treatmentDate);
        if (sc.visit.pessaryType != null) {
          verify('ringPessary', scan.ringPessary == true, expected: true, actual: scan.ringPessary);
          verify('pessaryType', scan.pessaryType == sc.visit.pessaryType, expected: sc.visit.pessaryType, actual: scan.pessaryType);
          verify('ringPessarySize', scan.ringPessarySize?.toString() == sc.visit.pessarySize, expected: sc.visit.pessarySize, actual: scan.ringPessarySize);
        } else {
          verify('ringPessary (none)', scan.ringPessary == false, expected: false, actual: scan.ringPessary);
        }

        final scanCounselLow = scan.counseling.map((x) => x.toLowerCase()).toList();
        for (final c in sc.visit.counseling) {
          verify(
            'counseling[$c]',
            scanCounselLow.any((scItem) => scItem.contains(c.toLowerCase())),
            expected: c,
            actual: scan.counseling,
          );
        }
        if (sc.visit.counseling.isEmpty) {
          verify('counseling (empty)', scan.counseling.isEmpty, expected: const <String>[], actual: scan.counseling);
        }

        if (sc.visit.surgicalReferral != null) {
          final expRefKey = sc.visit.surgicalReferral!.toLowerCase().split(' ').first;
          verify(
            'surgicalReferral',
            (scan.surgicalReferral ?? '').toLowerCase().contains(expRefKey),
            expected: sc.visit.surgicalReferral,
            actual: scan.surgicalReferral,
          );
        } else {
          verify('surgicalReferral (none)', scan.surgicalReferral == null, expected: null, actual: scan.surgicalReferral);
        }

        final scanMedsLow = scan.medications.map((x) => x.toLowerCase()).toSet();
        for (final med in sc.visit.medications) {
          verify('medication[$med]', scanMedsLow.contains(med.toLowerCase()), expected: med, actual: scan.medications);
        }
        if (sc.visit.customMedication != null) {
          verify(
            'customMedication',
            scanMedsLow.contains(sc.visit.customMedication!.toLowerCase()),
            expected: sc.visit.customMedication,
            actual: scan.medications,
          );
        }

        // 9. Station 6: Outtake, Follow-Up, Clinical Notes, Nurse & Doctor Signatures
        verify('outtakeDate (BS)', scan.outtakeDate == expectedBs, expected: expectedBs, actual: scan.outtakeDate);
        verify(
          'followUpDestination',
          (scan.followUpDestination ?? '').toLowerCase() == (sc.visit.followUpDestination ?? '').toLowerCase(),
          expected: sc.visit.followUpDestination,
          actual: scan.followUpDestination,
        );
        verify(
          'clinicalNotes',
          (scan.clinicalNotes ?? '').trim() == (sc.visit.outtakeNotes ?? '').trim(),
          expected: sc.visit.outtakeNotes,
          actual: scan.clinicalNotes,
        );

        // Staff extraction directly from OCR (without manual override!)
        final scanDocsLow = scan.attendingDoctors.map((x) => x.toLowerCase()).toList();
        for (final expDoc in sc.visit.attendingDoctorNames) {
          verify(
            'attendingDoctor[$expDoc]',
            scanDocsLow.any((dName) => dName.contains(expDoc.toLowerCase().replaceFirst('dr. ', ''))),
            expected: expDoc,
            actual: scan.attendingDoctors,
          );
        }
        final scanNursesLow = scan.attendingNurses.map((x) => x.toLowerCase()).toList();
        for (final expNurse in sc.visit.attendingNurseNames) {
          verify(
            'attendingNurse[$expNurse]',
            scanNursesLow.any((nName) => nName.contains(expNurse.toLowerCase())),
            expected: expNurse,
            actual: scan.attendingNurses,
          );
        }

        // 10. Commit to SQLite & Verify Round-Trip Database Persistence
        final committed = await ocrRepo.commitVerifiedScan(
          verifiedScan: scan,
          campId: sc.camp.id,
          campCode: sc.camp.campCode,
          userId: 'usr-audit',
          userName: 'Audit Verifier',
          userRole: 'NURSE',
          deviceId: 'dev-audit-01',
        );

        verify('DB.patientId', committed.patientId == sc.patient.patientId, expected: sc.patient.patientId, actual: committed.patientId);
        verify('DB.treatmentLevel', committed.treatmentLevel == sc.patient.treatmentLevel, expected: sc.patient.treatmentLevel, actual: committed.treatmentLevel);
        verify('DB.consentTreatment', committed.consentTreatment == sc.patient.consentTreatment, expected: sc.patient.consentTreatment, actual: committed.consentTreatment);
        verify('DB.consentStoreMedicalInfo', committed.consentStoreMedicalInfo == sc.patient.consentStoreMedicalInfo, expected: sc.patient.consentStoreMedicalInfo, actual: committed.consentStoreMedicalInfo);
        verify('DB.maritalAge', committed.maritalAge == sc.patient.maritalAge, expected: sc.patient.maritalAge, actual: committed.maritalAge);
        verify('DB.province', committed.province == sc.patient.province, expected: sc.patient.province, actual: committed.province);
        verify('DB.district', committed.district == sc.patient.district, expected: sc.patient.district, actual: committed.district);

        final visits = await patientRepo.getClinicalVisits(committed.id);
        expect(visits.length, 1);
        final sv = visits.first;
        verify('DB.visit.pelvicFloorTone', sv.pelvicFloorTone == sc.visit.pelvicFloorTone, expected: sc.visit.pelvicFloorTone, actual: sv.pelvicFloorTone);
        verify('DB.visit.uterusInside', sv.uterusInside == sc.visit.uterusInside, expected: sc.visit.uterusInside, actual: sv.uterusInside);
        verify('DB.visit.highestPopStage', sv.highestPopStage == sc.visit.highestPopStage, expected: sc.visit.highestPopStage, actual: sv.highestPopStage);
        verify('DB.visit.followUpNeeded', sv.followUpNeeded == sc.visit.followUpNeeded, expected: sc.visit.followUpNeeded, actual: sv.followUpNeeded);
        verify(
          'DB.visit.intakeDate (AD roundtrip)',
          committed.intakeDate.year == sc.patient.intakeDate.year &&
              committed.intakeDate.month == sc.patient.intakeDate.month &&
              committed.intakeDate.day == sc.patient.intakeDate.day,
          expected: sc.patient.intakeDate.toIso8601String().split('T').first,
          actual: committed.intakeDate.toIso8601String().split('T').first,
        );
      }

      final pct = totalChecks > 0 ? (passedChecks * 100.0 / totalChecks).toStringAsFixed(2) : '0.00';
      // ignore: avoid_print
      print('\n================================================================');
      // ignore: avoid_print
      print('NINE-SAMPLE OCR + DB FULL AUDIT SCORECARD: $passedChecks / $totalChecks ($pct%)');
      // ignore: avoid_print
      print('================================================================');
      if (allFailures.isNotEmpty) {
        // ignore: avoid_print
        print('FAILURES (${allFailures.length}):\n${allFailures.join('\n')}');
      }

      expect(allFailures, isEmpty, reason: 'Failed ${allFailures.length}/$totalChecks checks:\n${allFailures.take(40).join('\n')}');
    });

    test('10. Gemini Cloud OCR Pipeline: Verify All 9 Sample Payloads Normalize Accurately', () async {
      final dummyImg = File('${outDir.path}/dummy_gemini_probe.jpg');
      if (!dummyImg.existsSync()) {
        dummyImg.createSync(recursive: true);
        dummyImg.writeAsBytesSync([0xFF, 0xD8, 0xFF, 0xD9]);
      }

      for (final sc in samples) {
        final bs = toBsString(sc.patient.intakeDate);
        // Simulate truncated 8-box province & 11-box district on physical form (e.g. SUDURPAS, SINDHUPALCH)
        final rawProv = sc.patient.province.length > 8
            ? sc.patient.province.substring(0, 8).toUpperCase()
            : sc.patient.province.toUpperCase();
        final rawDist = sc.patient.district.length > 11
            ? sc.patient.district.substring(0, 11).toUpperCase()
            : sc.patient.district.toUpperCase();

        final payload = {
          'pageNumber': 0,
          'treatmentLevel': sc.patient.treatmentLevel,
          'intakeDate': bs,
          'anamnesisDate': bs,
          'examDate': bs,
          'labTestDate': bs,
          'conclusionDate': bs,
          'treatmentDate': bs,
          'outtakeDate': bs,
          'demographics': {
            'patientTokenId': sc.patient.patientId,
            'firstName': sc.patient.firstName,
            'surname': sc.patient.surname,
            'age': sc.patient.age,
            'maritalStatus': sc.patient.maritalStatus,
            'relativeName': sc.patient.spouseOrFatherName!.split(' ').first,
            'relativeSurname': sc.patient.spouseOrFatherName!.split(' ').last,
            'relationType': sc.patient.relationshipType,
            'mobile': sc.patient.mobile,
            'maritalAge': sc.patient.maritalAge,
            'contactPerson': sc.patient.contactPerson,
            'contactMobile': sc.patient.contactMobile,
            'province': rawProv,
            'district': rawDist,
            'municipality': sc.patient.municipality,
            'ward': sc.patient.ward,
            'reasonsForVisit': sc.patient.reasonsForVisit,
            'consentTreatment': sc.patient.consentTreatment,
            'consentStoreMedicalInfo': sc.patient.consentStoreMedicalInfo,
          },
          'obstetrics': {
            'deliveries': sc.visit.deliveries,
            'livingChildren': sc.visit.livingChildren,
            'abortions': sc.visit.abortions,
            'complaintsDuration': sc.visit.anamnesisComplaints['complaintsDuration'] ?? '',
            'clinicalComplaints': sc.expectedComplaints.keys.toList(),
            'complaintDetails': sc.expectedComplaints.entries.map((e) => {
              'complaint': e.key,
              'duration': e.value['duration'],
              'subOptions': e.value['options'],
              'remarks': e.value['remarks'],
            }).toList(),
          },
          'popStaging': {
            'uterusInside': sc.visit.uterusInside,
            'pelvicFloorTone': sc.visit.pelvicFloorTone,
            'anteriorStage': sc.visit.popAnteriorStage,
            'middleStage': sc.visit.popMiddleStage,
            'posteriorStage': sc.visit.popPosteriorStage,
            'highestPopStage': sc.visit.highestPopStage,
            'vulvaRemarks': sc.visit.vulvaRemarks,
            'vaginaRemarks': sc.visit.vaginaRemarks,
            'cervixRemarks': sc.visit.cervixRemarks,
            'uterusRemarks': sc.visit.uterusRemarks,
          },
          'vitals': {
            'systolicBp': sc.visit.systolicBp,
            'diastolicBp': sc.visit.diastolicBp,
            'pulseRate': sc.visit.pulse,
            'spo2': sc.visit.spo2,
            'bloodGlucose': sc.visit.glucose,
            'urineTest': sc.visit.urineTest,
            'pregnancyTest': sc.visit.pregnancyTest,
            'ecg': sc.expectedEcgStatus,
            'ecgNotes': sc.visit.ecgNotes,
          },
          'diagnoses': sc.visit.diagnoses,
          'counseling': sc.visit.counseling,
          'medications': [
            ...sc.visit.medications,
            if (sc.visit.customMedication != null) sc.visit.customMedication!,
          ],
          'ringPessary': sc.visit.pessaryType != null,
          'pessaryType': sc.visit.pessaryType,
          'ringPessarySize': sc.visit.pessarySize != null ? int.tryParse(sc.visit.pessarySize!) : null,
          'surgicalReferral': sc.visit.surgicalReferral,
          'followUpDestination': sc.visit.followUpDestination,
          'clinicalNotes': sc.visit.outtakeNotes,
          'examiningDoctor': sc.visit.primaryDoctorName,
          'attendingDoctors': sc.visit.attendingDoctorNames,
          'examiningNurse': sc.visit.primaryNurseName,
          'attendingNurses': sc.visit.attendingNurseNames,
        };

        final mockClient = MockClient((_) async => http.Response(
              jsonEncode({'success': true, 'text': jsonEncode(payload)}),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ));

        final gemini = GeminiOcrService(
          httpClient: mockClient,
          baseUrl: 'http://test-server:8080',
          deviceFingerprint: 'AUDITFINGERPRINT0123456789ABCDEF',
          deviceSecret: 'b' * 64,
        );

        final res = await gemini.extractFromImage(XFile(dummyImg.path), pageNumber: 0);
        expect(res.demographics['province'], sc.patient.province, reason: 'Gemini province normalization failed for Sample ${sc.index} ($rawProv)');
        expect(res.demographics['district'], sc.patient.district, reason: 'Gemini district normalization failed for Sample ${sc.index} ($rawDist)');
        expect(res.demographics['consentTreatment'], sc.patient.consentTreatment);
        expect(res.demographics['consentStoreMedicalInfo'], sc.patient.consentStoreMedicalInfo);
        expect(res.treatmentLevel, sc.patient.treatmentLevel);
        expect(res.popStaging['pelvicFloorTone'], sc.visit.pelvicFloorTone);
      }
    });
  });
}
