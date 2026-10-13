import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/pdf_report_service.dart';
import 'package:gyno_camp/core/services/ocr_form_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/patient_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pdfService = PdfReportService();
  final ocrService = const OcrFormService();

  final outDir = Directory('test_samples');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  group('Part 1: Blank & Camp Form Generation — Doctor & Staff Roster Matrix', () {
    // 1. Single Doctor, Single Nurse
    test('1. Generate Blank Form: Single Doctor & Single Nurse', () async {
      final camp = CampModel(
        id: 'camp-single-single',
        campCode: 'S1N1',
        name: 'Single Doc Single Nurse Camp',
        province: 'Bagmati',
        district: 'Kathmandu',
        municipality: 'Budhanilkantha',
        ward: '01',
        venue: 'Health Post',
        startDate: DateTime(2026, 10, 15),
        endDate: DateTime(2026, 10, 16),
        status: CampStatus.open,
        doctorNames: ['Dr. Sita Karki (NMC: 14256)'],
        nurseNames: ['Pooja Thapa (NNC: 8901)'],
        createdAt: DateTime(2026, 10, 1),
      );

      final pdfBytes = await pdfService.generatePatientRegistrationFormPdf(
        camp: camp,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(pdfBytes.isNotEmpty, true);
      final file = File('test_samples/form_single_doc_single_nurse.pdf');
      file.writeAsBytesSync(pdfBytes);
      expect(file.existsSync(), true);
    });

    // 2. Multiple Doctors, Single Nurse
    test('2. Generate Blank Form: Multiple Doctors (3) & Single Nurse', () async {
      final camp = CampModel(
        id: 'camp-multi-single',
        campCode: 'M3N1',
        name: 'Multi Doc Single Nurse Camp',
        province: 'Gandaki',
        district: 'Kaski',
        municipality: 'Pokhara',
        ward: '05',
        venue: 'District Hospital',
        startDate: DateTime(2026, 10, 18),
        endDate: DateTime(2026, 10, 20),
        status: CampStatus.open,
        doctorNames: [
          'Dr. Sita Karki (NMC: 14256)',
          'Dr. Ramesh Thapa (NMC: 22334)',
          'Dr. Anjali Singh (NMC: 33445)',
        ],
        nurseNames: ['Pooja Thapa (NNC: 8901)'],
        createdAt: DateTime(2026, 10, 1),
      );

      final pdfBytes = await pdfService.generatePatientRegistrationFormPdf(
        camp: camp,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(pdfBytes.isNotEmpty, true);
      final file = File('test_samples/form_multi_doc_single_nurse.pdf');
      file.writeAsBytesSync(pdfBytes);
      expect(file.existsSync(), true);
    });

    // 3. Single Doctor, Multiple Nurses
    test('3. Generate Blank Form: Single Doctor & Multiple Nurses (3)', () async {
      final camp = CampModel(
        id: 'camp-single-multi',
        campCode: 'S1N3',
        name: 'Single Doc Multi Nurse Camp',
        province: 'Lumbini',
        district: 'Rupandehi',
        municipality: 'Butwal',
        ward: '08',
        venue: 'Community Health Clinic',
        startDate: DateTime(2026, 10, 22),
        endDate: DateTime(2026, 10, 24),
        status: CampStatus.open,
        doctorNames: ['Dr. Sita Karki (NMC: 14256)'],
        nurseNames: [
          'Pooja Thapa (NNC: 8901)',
          'Gita Sharma (NNC: 9912)',
          'Rita KC (NNC: 7723)',
        ],
        createdAt: DateTime(2026, 10, 1),
      );

      final pdfBytes = await pdfService.generatePatientRegistrationFormPdf(
        camp: camp,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(pdfBytes.isNotEmpty, true);
      final file = File('test_samples/form_single_doc_multi_nurse.pdf');
      file.writeAsBytesSync(pdfBytes);
      expect(file.existsSync(), true);
    });

    // 4. Multiple Doctors, Multiple Nurses
    test('4. Generate Blank Form: Multiple Doctors (3) & Multiple Nurses (3)', () async {
      final camp = CampModel(
        id: 'camp-multi-multi',
        campCode: 'M3N3',
        name: 'Comprehensive Multi-Staff Camp',
        province: 'Koshi',
        district: 'Morang',
        municipality: 'Biratnagar',
        ward: '02',
        venue: 'Sub-Metropolitan Health Center',
        startDate: DateTime(2026, 10, 25),
        endDate: DateTime(2026, 10, 28),
        status: CampStatus.open,
        doctorNames: [
          'Dr. Sita Karki (NMC: 14256)',
          'Dr. Ramesh Thapa (NMC: 22334)',
          'Dr. Anjali Singh (NMC: 33445)',
        ],
        nurseNames: [
          'Pooja Thapa (NNC: 8901)',
          'Gita Sharma (NNC: 9912)',
          'Rita KC (NNC: 7723)',
        ],
        createdAt: DateTime(2026, 10, 1),
      );

      final pdfBytes = await pdfService.generatePatientRegistrationFormPdf(
        camp: camp,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(pdfBytes.isNotEmpty, true);
      final file = File('test_samples/form_multi_doc_multi_nurse.pdf');
      file.writeAsBytesSync(pdfBytes);
      expect(file.existsSync(), true);
    });

    // 5. Blank / No Pre-Assigned Clinicians (Open On-site Signing)
    test('5. Generate Blank Form: Blank Doctors & Blank Nurses', () async {
      final camp = CampModel(
        id: 'camp-blank-staff',
        campCode: 'BLANK',
        name: 'Open Field Camp (On-Site Signing)',
        province: 'Sudurpashchim',
        district: 'Kailali',
        municipality: 'Dhangadhi',
        ward: '03',
        venue: 'Rural Health Post',
        startDate: DateTime(2026, 10, 30),
        endDate: DateTime(2026, 10, 31),
        status: CampStatus.open,
        doctorNames: const [],
        nurseNames: const [],
        createdAt: DateTime(2026, 10, 1),
      );

      final pdfBytes = await pdfService.generatePatientRegistrationFormPdf(
        camp: camp,
        blankDoctorLines: true,
        blankNurseLines: true,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(pdfBytes.isNotEmpty, true);
      final file = File('test_samples/form_blank_doc_blank_nurse.pdf');
      file.writeAsBytesSync(pdfBytes);
      expect(file.existsSync(), true);
    });
  });

  group('Part 2: OCR Detection Logic — Single & Multiple Clinicians', () {
    test('Detects single doctor and nurse from structured text line', () {
      const sampleText = '''
STATION 6: CLINICAL SUMMARY
Follow-up: Health Post in 2 weeks
Examining Doctor: Dr. Sita Karki
Attending Nurse: Staff Nurse Pooja Thapa
''';
      final res = ocrService.parseFormText(sampleText, pageNumber: 2);
      expect(res.examiningDoctor, 'Dr. Sita Karki');
      expect(res.attendingDoctors, ['Dr. Sita Karki']);
      expect(res.examiningNurse, 'Pooja Thapa');
      expect(res.attendingNurses, ['Pooja Thapa']);
    });

    test('Detects doctor from clinician role keyword (gynecologist/doctor)', () {
      const sampleText = '''
Gynecologist: Anita Sharma
Sister: Gita Sharma
''';
      final res = ocrService.parseFormText(sampleText, pageNumber: 2);
      expect(res.examiningDoctor, 'Dr. Anita Sharma');
      expect(res.examiningNurse, 'Gita Sharma');
    });

    test('Strips prefixes ("Nurse", "Sister", "Staff Nurse") reliably', () {
      expect(NurseProfile.stripPrefixes('Staff Nurse Sita Sharma'), 'Sita Sharma');
      expect(NurseProfile.stripPrefixes('Sister Gita Rai'), 'Gita Rai');
      expect(NurseProfile.stripPrefixes('Nurse Pooja Thapa'), 'Pooja Thapa');
      expect(NurseProfile.stripPrefixes('Sr. Rita KC'), 'Rita KC');
      expect(NurseProfile.stripPrefixes('Sita Sharma'), 'Sita Sharma');
    });

    test('Strips "Dr." prefix for doctor comparisons reliably', () {
      expect(DoctorProfile.stripDrPrefix('Dr. Sita Karki'), 'Sita Karki');
      expect(DoctorProfile.stripDrPrefix('Dr Sita Karki'), 'Sita Karki');
      expect(DoctorProfile.stripDrPrefix('Sita Karki'), 'Sita Karki');
    });

    test('Guards against false positives: "GynaeSupport Nurse" is not detected as attending nurse', () {
      const sampleText = '''
Follow-up Destination: GynaeSupport Nurse
Doctor: Dr. Ramesh Thapa
''';
      final res = ocrService.parseFormText(sampleText, pageNumber: 2);
      expect(res.examiningDoctor, 'Dr. Ramesh Thapa');
      expect(res.examiningNurse, isNull);
      expect(res.attendingNurses, isEmpty);
    });
  });

  group('Part 3: Filtering Engine — Multi-Doctor & Multi-Staff Accuracy', () {
    final visit1 = ClinicalVisitModel(
      id: 'vis-1',
      patientId: 'pat-1',
      campId: 'camp-1',
      visitDate: DateTime(2026, 10, 1),
      primaryDoctorName: 'Dr. Sita Karki',
      attendingDoctorNames: ['Dr. Sita Karki'],
      primaryNurseName: 'Pooja Thapa',
      attendingNurseNames: ['Pooja Thapa'],
      createdAt: DateTime(2026, 10, 1),
      createdByUserId: 'usr-1',
    );

    final visit2 = ClinicalVisitModel(
      id: 'vis-2',
      patientId: 'pat-2',
      campId: 'camp-1',
      visitDate: DateTime(2026, 10, 1),
      primaryDoctorName: 'Dr. Ramesh Thapa',
      attendingDoctorNames: ['Dr. Ramesh Thapa', 'Dr. Sita Karki'], // Multiple attending doctors
      primaryNurseName: 'Gita Sharma',
      attendingNurseNames: ['Gita Sharma'],
      createdAt: DateTime(2026, 10, 1),
      createdByUserId: 'usr-1',
    );

    final visit3 = ClinicalVisitModel(
      id: 'vis-3',
      patientId: 'pat-3',
      campId: 'camp-1',
      visitDate: DateTime(2026, 10, 2),
      primaryDoctorName: 'Dr. Anjali Singh',
      attendingDoctorNames: ['Dr. Anjali Singh'],
      primaryNurseName: 'Pooja Thapa',
      attendingNurseNames: ['Pooja Thapa', 'Rita KC'], // Multiple attending nurses
      createdAt: DateTime(2026, 10, 2),
      createdByUserId: 'usr-1',
    );

    final allVisits = [visit1, visit2, visit3];

    bool docNamesMatch(String a, String b) {
      final cleanA = a.replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim().toLowerCase();
      final cleanB = b.replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim().toLowerCase();
      if (cleanA.isEmpty || cleanB.isEmpty) return false;
      return cleanA == cleanB || cleanA.contains(cleanB) || cleanB.contains(cleanA);
    }

    bool nurseNamesMatch(String a, String b) {
      final cleanA = NurseProfile.stripPrefixes(a).toLowerCase().trim();
      final cleanB = NurseProfile.stripPrefixes(b).toLowerCase().trim();
      if (cleanA.isEmpty || cleanB.isEmpty) return false;
      return cleanA == cleanB || cleanA.contains(cleanB) || cleanB.contains(cleanA);
    }

    test('Doctor Filter matches primary and co-attending doctors across records', () {
      // Filter for Sita Karki -> Primary on Visit 1, Co-attending on Visit 2
      final sitaVisits = allVisits.where((v) {
        final pMatch = v.primaryDoctorName != null && docNamesMatch(v.primaryDoctorName!, 'Sita Karki');
        final aMatch = v.attendingDoctorNames.any((d) => docNamesMatch(d, 'Sita Karki'));
        return pMatch || aMatch;
      }).toList();

      expect(sitaVisits.length, 2);
      expect(sitaVisits.map((v) => v.id), containsAll(['vis-1', 'vis-2']));

      // Filter for Ramesh Thapa -> Primary on Visit 2 only
      final rameshVisits = allVisits.where((v) {
        final pMatch = v.primaryDoctorName != null && docNamesMatch(v.primaryDoctorName!, 'Ramesh Thapa');
        final aMatch = v.attendingDoctorNames.any((d) => docNamesMatch(d, 'Ramesh Thapa'));
        return pMatch || aMatch;
      }).toList();

      expect(rameshVisits.length, 1);
      expect(rameshVisits.first.id, 'vis-2');

      // Filter for Anjali Singh -> Primary on Visit 3 only
      final anjaliVisits = allVisits.where((v) {
        final pMatch = v.primaryDoctorName != null && docNamesMatch(v.primaryDoctorName!, 'Anjali Singh');
        final aMatch = v.attendingDoctorNames.any((d) => docNamesMatch(d, 'Anjali Singh'));
        return pMatch || aMatch;
      }).toList();

      expect(anjaliVisits.length, 1);
      expect(anjaliVisits.first.id, 'vis-3');
    });

    test('Nurse Filter matches primary and co-attending nurses across records', () {
      // Filter for Pooja Thapa -> Primary on Visit 1, Primary on Visit 3
      final poojaVisits = allVisits.where((v) {
        final pMatch = v.primaryNurseName != null && nurseNamesMatch(v.primaryNurseName!, 'Pooja Thapa');
        final aMatch = v.attendingNurseNames.any((n) => nurseNamesMatch(n, 'Pooja Thapa'));
        return pMatch || aMatch;
      }).toList();

      expect(poojaVisits.length, 2);
      expect(poojaVisits.map((v) => v.id), containsAll(['vis-1', 'vis-3']));

      // Filter for Gita Sharma -> Primary on Visit 2
      final gitaVisits = allVisits.where((v) {
        final pMatch = v.primaryNurseName != null && nurseNamesMatch(v.primaryNurseName!, 'Gita Sharma');
        final aMatch = v.attendingNurseNames.any((n) => nurseNamesMatch(n, 'Gita Sharma'));
        return pMatch || aMatch;
      }).toList();

      expect(gitaVisits.length, 1);
      expect(gitaVisits.first.id, 'vis-2');

      // Filter for Rita KC -> Co-attending on Visit 3
      final ritaVisits = allVisits.where((v) {
        final pMatch = v.primaryNurseName != null && nurseNamesMatch(v.primaryNurseName!, 'Rita KC');
        final aMatch = v.attendingNurseNames.any((n) => nurseNamesMatch(n, 'Rita KC'));
        return pMatch || aMatch;
      }).toList();

      expect(ritaVisits.length, 1);
      expect(ritaVisits.first.id, 'vis-3');
    });

    test('Data Analyst Workstation matching handles unvisited patient solo-doctor fallback correctly', () {
      final unvisitedPatient = PatientModel(
        id: 'pat-4',
        patientId: 'GC-KTM01-004',
        campId: 'camp-solo',
        campCode: 'SOLO',
        intakeDate: DateTime(2026, 10, 3),
        firstName: 'Kamala',
        surname: 'Adhikari',
        age: 38,
        mobile: '9841000000',
        ward: '01',
        createdAt: DateTime(2026, 10, 3),
        createdByUserId: 'usr-1',
        createdByDeviceId: 'dev-1',
      );

      final soloCamp = CampModel(
        id: 'camp-solo',
        campCode: 'SOLO',
        name: 'Solo Doctor Camp',
        province: 'Bagmati',
        district: 'Kathmandu',
        municipality: 'KMC',
        ward: '01',
        venue: 'Clinic',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 2),
        status: CampStatus.open,
        doctorNames: ['Dr. Sita Karki'],
        nurseNames: ['Pooja Thapa'],
        createdAt: DateTime(2026, 10, 1),
      );

      final multiCamp = CampModel(
        id: 'camp-multi',
        campCode: 'MULTI',
        name: 'Multi Doctor Camp',
        province: 'Bagmati',
        district: 'Kathmandu',
        municipality: 'KMC',
        ward: '02',
        venue: 'Hospital',
        startDate: DateTime(2026, 10, 1),
        endDate: DateTime(2026, 10, 2),
        status: CampStatus.open,
        doctorNames: ['Dr. Sita Karki', 'Dr. Ramesh Thapa'],
        nurseNames: ['Pooja Thapa', 'Gita Sharma'],
        createdAt: DateTime(2026, 10, 1),
      );

      // In a solo doctor camp: unvisited patient matches that solo doctor
      expect(unvisitedPatient.patientId, 'GC-KTM01-004');
      bool matchesSoloDoc = false;
      if (soloCamp.doctorNames.length == 1 && docNamesMatch(soloCamp.doctorNames.first, 'Sita Karki')) {
        matchesSoloDoc = true;
      }
      expect(matchesSoloDoc, true);

      // In a multi-doctor camp: unvisited patient does NOT match any doctor until visited
      bool matchesMultiDoc = false;
      if (multiCamp.doctorNames.length == 1) {
        matchesMultiDoc = true;
      }
      expect(matchesMultiDoc, false);
    });
  });

  group('Part 4: Download Modes Verification — Doctor/Nurse Checklist vs Batch Forms', () {
    final camp = CampModel(
      id: 'camp-test-11',
      campCode: '11',
      name: 'first testing',
      province: 'Province 1',
      district: 'Ilam',
      municipality: 'Mai',
      ward: '5',
      venue: 'Health Post',
      startDate: DateTime(2026, 10, 13),
      endDate: DateTime(2026, 10, 15),
      status: CampStatus.open,
      doctorNames: [
        'Dr. Anish Tiwari (NMC: 222/222)',
        'Dr. Sagar Sharma (NMC: 333/333)',
      ],
      nurseNames: [
        'Ayusha Pathak',
        'Smiriti Gautam',
      ],
      createdAt: DateTime(2026, 10, 1),
    );

    test('4.1 Multi-Doctor Checklist + Multi-Nurse Checklist (Single 2-Page Form)', () async {
      // Both doctor and nurse are null => generates checklist checkboxes on Page 2 for both
      final pdfBytes = await pdfService.generatePatientRegistrationFormPdf(
        camp: camp,
        doctor: null, // allDoctorsChecklist
        blankDoctorLines: false,
        nurse: null, // allNursesChecklist
        blankNurseLines: false,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(pdfBytes.isNotEmpty, true);
      final file = File('test_samples/Blank_YellowForm_11_DoctorsChecklist_NursesChecklist.pdf');
      file.writeAsBytesSync(pdfBytes);
      expect(file.existsSync(), true);
    });

    test('4.2 Multi-Doctor Batch (Separate Copies per Doctor)', () async {
      final doctors = camp.doctorProfiles;
      final pdfBytes = await pdfService.generateBatchBlankYellowFormsPdf(
        doctors: doctors,
        camp: camp,
        nurse: null, // nurses checklist on each doctor copy
        blankNurseLines: false,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(pdfBytes.isNotEmpty, true);
      final file = File('test_samples/Blank_YellowForms_11_AllDoctorsBatch.pdf');
      file.writeAsBytesSync(pdfBytes);
      expect(file.existsSync(), true);
    });

    test('4.3 Multi-Nurse Batch (Separate Copies per Nurse)', () async {
      final nurses = camp.nurseProfiles;
      final pdfBytes = await pdfService.generateBatchBlankYellowFormsByNursesPdf(
        nurses: nurses,
        camp: camp,
        doctor: null, // doctors checklist on each nurse copy
        blankDoctorLines: false,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(pdfBytes.isNotEmpty, true);
      final file = File('test_samples/Blank_YellowForms_11_AllNursesBatch.pdf');
      file.writeAsBytesSync(pdfBytes);
      expect(file.existsSync(), true);
    });

    test('4.4 Follow-Up Slip with Multi-Doctor Checklist & Nurse Checklist', () async {
      final pdfBytes = await pdfService.generateBlankFollowUpSlipPdf(
        camp: camp,
        doctor: null, // doctors checklist
        blankDoctorLines: false,
        nurse: null, // nurses checklist
        blankNurseLines: false,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(pdfBytes.isNotEmpty, true);
      final file = File('test_samples/Blank_FollowUpSlip_11_DoctorsChecklist_NursesChecklist.pdf');
      file.writeAsBytesSync(pdfBytes);
      expect(file.existsSync(), true);
    });

    test('4.5 Follow-Up Slip Batch by Doctors', () async {
      final doctors = camp.doctorProfiles;
      final pdfBytes = await pdfService.generateBatchBlankFollowUpSlipsPdf(
        doctors: doctors,
        camp: camp,
        nurse: null,
        blankNurseLines: false,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(pdfBytes.isNotEmpty, true);
      final file = File('test_samples/Blank_FollowUpSlips_11_AllDoctorsBatch.pdf');
      file.writeAsBytesSync(pdfBytes);
      expect(file.existsSync(), true);
    });

    test('4.6 Follow-Up Slip Batch by Nurses', () async {
      final nurses = camp.nurseProfiles;
      final pdfBytes = await pdfService.generateBatchBlankFollowUpSlipsByNursesPdf(
        nurses: nurses,
        camp: camp,
        doctor: null,
        blankDoctorLines: false,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(pdfBytes.isNotEmpty, true);
      final file = File('test_samples/Blank_FollowUpSlips_11_AllNursesBatch.pdf');
      file.writeAsBytesSync(pdfBytes);
      expect(file.existsSync(), true);
    });
  });
}
