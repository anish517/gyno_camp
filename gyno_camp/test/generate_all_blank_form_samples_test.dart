import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/pdf_report_service.dart';
import 'package:gyno_camp/models/camp_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pdfService = PdfReportService();

  final outDir = Directory('test_samples');
  if (!outDir.existsSync()) {
    outDir.createSync(recursive: true);
  }

  // Multi-clinician camp fixture (matches user's real setup: 2 doctors & 2 nurses)
  final multiCamp = CampModel(
    id: 'camp-11-first-testing',
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

  // Single-clinician camp fixture
  final soloCamp = CampModel(
    id: 'camp-solo-staff',
    campCode: 'SOLO',
    name: 'Single Clinician Health Outreach',
    province: 'Bagmati',
    district: 'Kathmandu',
    municipality: 'Budhanilkantha',
    ward: '01',
    venue: 'Primary Clinic',
    startDate: DateTime(2026, 10, 15),
    endDate: DateTime(2026, 10, 16),
    status: CampStatus.open,
    doctorNames: ['Dr. Sita Karki (NMC: 14256)'],
    nurseNames: ['Pooja Thapa (NNC: 8901)'],
    createdAt: DateTime(2026, 10, 1),
  );

  // Open field camp fixture (0 assigned clinicians)
  final openFieldCamp = CampModel(
    id: 'camp-open-field',
    campCode: 'OPEN',
    name: 'Rural Outreach (Manual On-Site Signing)',
    province: 'Sudurpashchim',
    district: 'Kailali',
    municipality: 'Dhangadhi',
    ward: '03',
    venue: 'Rural Health Post',
    startDate: DateTime(2026, 10, 20),
    endDate: DateTime(2026, 10, 22),
    status: CampStatus.open,
    doctorNames: const [],
    nurseNames: const [],
    createdAt: DateTime(2026, 10, 1),
  );

  group('Section A: Yellow Registration Forms (2 Pages A4)', () {
    test('1. Two-Column Grid: Multi-Doctor Checklist & Multi-Nurse Checklist', () async {
      final bytes = await pdfService.generatePatientRegistrationFormPdf(
        camp: multiCamp,
        doctor: null, // allDoctorsChecklist
        blankDoctorLines: false,
        nurse: null, // allNursesChecklist
        blankNurseLines: false,
        page1Layout: BlankFormPage1Layout.grid,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(bytes.isNotEmpty, true);
      final file = File('test_samples/01_Blank_YellowForm_Grid_MultiDocChecklist_MultiNurseChecklist.pdf');
      file.writeAsBytesSync(bytes);
      expect(file.existsSync(), true);
      expect(file.lengthSync(), greaterThan(50000));
    });

    test('2. Classic Layout: Multi-Doctor Checklist & Multi-Nurse Checklist', () async {
      final bytes = await pdfService.generatePatientRegistrationFormPdf(
        camp: multiCamp,
        doctor: null, // allDoctorsChecklist
        blankDoctorLines: false,
        nurse: null, // allNursesChecklist
        blankNurseLines: false,
        page1Layout: BlankFormPage1Layout.classic,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(bytes.isNotEmpty, true);
      final file = File('test_samples/02_Blank_YellowForm_Classic_MultiDocChecklist_MultiNurseChecklist.pdf');
      file.writeAsBytesSync(bytes);
      expect(file.existsSync(), true);
      expect(file.lengthSync(), greaterThan(50000));
    });

    test('3. Specific Doctor & Specific Nurse Pre-Printed', () async {
      final bytes = await pdfService.generatePatientRegistrationFormPdf(
        camp: multiCamp,
        doctor: multiCamp.doctorProfiles.first, // Dr. Anish Tiwari
        blankDoctorLines: false,
        nurse: multiCamp.nurseProfiles.first, // Ayusha Pathak
        blankNurseLines: false,
        page1Layout: BlankFormPage1Layout.grid,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(bytes.isNotEmpty, true);
      final file = File('test_samples/03_Blank_YellowForm_SpecificDoctor_SpecificNurse.pdf');
      file.writeAsBytesSync(bytes);
      expect(file.existsSync(), true);
      expect(file.lengthSync(), greaterThan(50000));
    });

    test('4. All Assigned Doctors Batch (Separate 2-page copies per doctor)', () async {
      final bytes = await pdfService.generateBatchBlankYellowFormsPdf(
        doctors: multiCamp.doctorProfiles,
        camp: multiCamp,
        nurse: null, // nurses checklist on each copy
        blankNurseLines: false,
        page1Layout: BlankFormPage1Layout.grid,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(bytes.isNotEmpty, true);
      final file = File('test_samples/04_Blank_YellowForms_AllDoctorsBatch_SeparateCopies.pdf');
      file.writeAsBytesSync(bytes);
      expect(file.existsSync(), true);
      expect(file.lengthSync(), greaterThan(100000));
    });

    test('5. All Assigned Nurses Batch (Separate 2-page copies per nurse)', () async {
      final bytes = await pdfService.generateBatchBlankYellowFormsByNursesPdf(
        nurses: multiCamp.nurseProfiles,
        camp: multiCamp,
        doctor: null, // doctors checklist on each copy
        blankDoctorLines: false,
        page1Layout: BlankFormPage1Layout.grid,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(bytes.isNotEmpty, true);
      final file = File('test_samples/05_Blank_YellowForms_AllNursesBatch_SeparateCopies.pdf');
      file.writeAsBytesSync(bytes);
      expect(file.existsSync(), true);
      expect(file.lengthSync(), greaterThan(100000));
    });

    test('6. Single Doctor & Single Nurse Camp', () async {
      final bytes = await pdfService.generatePatientRegistrationFormPdf(
        camp: soloCamp,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(bytes.isNotEmpty, true);
      final file = File('test_samples/06_Blank_YellowForm_SingleDoc_SingleNurse.pdf');
      file.writeAsBytesSync(bytes);
      expect(file.existsSync(), true);
      expect(file.lengthSync(), greaterThan(50000));
    });

    test('7. Multi-Doctor Checklist & Single Specific Nurse', () async {
      final bytes = await pdfService.generatePatientRegistrationFormPdf(
        camp: multiCamp,
        doctor: null, // checklist
        blankDoctorLines: false,
        nurse: multiCamp.nurseProfiles.first, // specific nurse
        blankNurseLines: false,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(bytes.isNotEmpty, true);
      final file = File('test_samples/07_Blank_YellowForm_MultiDocChecklist_SpecificNurse.pdf');
      file.writeAsBytesSync(bytes);
      expect(file.existsSync(), true);
      expect(file.lengthSync(), greaterThan(50000));
    });

    test('8. Specific Doctor & Multi-Nurse Checklist', () async {
      final bytes = await pdfService.generatePatientRegistrationFormPdf(
        camp: multiCamp,
        doctor: multiCamp.doctorProfiles.first, // specific doctor
        blankDoctorLines: false,
        nurse: null, // checklist
        blankNurseLines: false,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(bytes.isNotEmpty, true);
      final file = File('test_samples/08_Blank_YellowForm_SpecificDoctor_MultiNurseChecklist.pdf');
      file.writeAsBytesSync(bytes);
      expect(file.existsSync(), true);
      expect(file.lengthSync(), greaterThan(50000));
    });

    test('9. Open Field Blank Lines (हस्तलिखित / Manual On-Site Signing)', () async {
      final bytes = await pdfService.generatePatientRegistrationFormPdf(
        camp: openFieldCamp,
        blankDoctorLines: true,
        blankNurseLines: true,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(bytes.isNotEmpty, true);
      final file = File('test_samples/09_Blank_YellowForm_BlankDoctor_BlankNurse.pdf');
      file.writeAsBytesSync(bytes);
      expect(file.existsSync(), true);
      expect(file.lengthSync(), greaterThan(50000));
    });

    test('10. Pre-Numbered Sequential Tokens (5 Forms, 10 Pages with QR)', () async {
      final bytes = await pdfService.generatePreNumberedBlankFormsPdf(
        camp: multiCamp,
        startSequence: 1,
        count: 5,
        doctor: null, // checklist
        blankDoctorLines: false,
        nurse: null, // checklist
        blankNurseLines: false,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(bytes.isNotEmpty, true);
      final file = File('test_samples/10_Blank_YellowForms_PreNumbered_Tokens_00001_to_00005.pdf');
      file.writeAsBytesSync(bytes);
      expect(file.existsSync(), true);
      expect(file.lengthSync(), greaterThan(150000));
    });
  });

  group('Section B: Follow-Up Encounter Slips (1 Page A4)', () {
    test('11. Follow-Up: Multi-Doctor Checklist & Multi-Nurse Checklist', () async {
      final bytes = await pdfService.generateBlankFollowUpSlipPdf(
        camp: multiCamp,
        doctor: null, // checklist
        blankDoctorLines: false,
        nurse: null, // checklist
        blankNurseLines: false,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(bytes.isNotEmpty, true);
      final file = File('test_samples/11_Blank_FollowUpSlip_MultiDocChecklist_MultiNurseChecklist.pdf');
      file.writeAsBytesSync(bytes);
      expect(file.existsSync(), true);
      expect(file.lengthSync(), greaterThan(50000));
    });

    test('12. Follow-Up: Specific Doctor & Specific Nurse', () async {
      final bytes = await pdfService.generateBlankFollowUpSlipPdf(
        camp: multiCamp,
        doctor: multiCamp.doctorProfiles.first,
        blankDoctorLines: false,
        nurse: multiCamp.nurseProfiles.first,
        blankNurseLines: false,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(bytes.isNotEmpty, true);
      final file = File('test_samples/12_Blank_FollowUpSlip_SpecificDoctor_SpecificNurse.pdf');
      file.writeAsBytesSync(bytes);
      expect(file.existsSync(), true);
      expect(file.lengthSync(), greaterThan(50000));
    });

    test('13. Follow-Up: All Assigned Doctors Batch (Separate 1-page copies)', () async {
      final bytes = await pdfService.generateBatchBlankFollowUpSlipsPdf(
        doctors: multiCamp.doctorProfiles,
        camp: multiCamp,
        nurse: null,
        blankNurseLines: false,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(bytes.isNotEmpty, true);
      final file = File('test_samples/13_Blank_FollowUpSlips_AllDoctorsBatch_SeparateCopies.pdf');
      file.writeAsBytesSync(bytes);
      expect(file.existsSync(), true);
      expect(file.lengthSync(), greaterThan(80000));
    });

    test('14. Follow-Up: All Assigned Nurses Batch (Separate 1-page copies)', () async {
      final bytes = await pdfService.generateBatchBlankFollowUpSlipsByNursesPdf(
        nurses: multiCamp.nurseProfiles,
        camp: multiCamp,
        doctor: null,
        blankDoctorLines: false,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(bytes.isNotEmpty, true);
      final file = File('test_samples/14_Blank_FollowUpSlips_AllNursesBatch_SeparateCopies.pdf');
      file.writeAsBytesSync(bytes);
      expect(file.existsSync(), true);
      expect(file.lengthSync(), greaterThan(80000));
    });

    test('15. Follow-Up: Blank Lines for Manual Entry', () async {
      final bytes = await pdfService.generateBlankFollowUpSlipPdf(
        camp: openFieldCamp,
        blankDoctorLines: true,
        blankNurseLines: true,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(bytes.isNotEmpty, true);
      final file = File('test_samples/15_Blank_FollowUpSlip_BlankDoctor_BlankNurse.pdf');
      file.writeAsBytesSync(bytes);
      expect(file.existsSync(), true);
      expect(file.lengthSync(), greaterThan(50000));
    });

    test('16. Follow-Up: Pre-Numbered Sequential Tokens (5 Slips with QR)', () async {
      final bytes = await pdfService.generatePreNumberedBlankFollowUpSlipsPdf(
        camp: multiCamp,
        startSequence: 1,
        count: 5,
        doctor: null,
        blankDoctorLines: false,
        nurse: null,
        blankNurseLines: false,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(bytes.isNotEmpty, true);
      final file = File('test_samples/16_Blank_FollowUpSlips_PreNumbered_Tokens_00001_to_00005.pdf');
      file.writeAsBytesSync(bytes);
      expect(file.existsSync(), true);
      expect(file.lengthSync(), greaterThan(100000));
    });
  });

  group('Section C: Universal Blank Forms (No Active Camp Required)', () {
    test('17. Universal Yellow Form (Two-Column Grid Layout) with camp: null', () async {
      final bytes = await pdfService.generatePatientRegistrationFormPdf(
        camp: null,
        doctor: null,
        nurse: null,
        blankNurseLines: true,
        blankDoctorLines: true,
        allDoctorsChecklist: false,
        allNursesChecklist: false,
        page1Layout: BlankFormPage1Layout.grid,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(bytes.isNotEmpty, true);
      final file = File('test_samples/17_Blank_Universal_YellowForm_TwoColumnGrid.pdf');
      file.writeAsBytesSync(bytes);
      expect(file.existsSync(), true);
      expect(file.lengthSync(), greaterThan(50000));
    });

    test('18. Universal Yellow Form (Classic Layout) with camp: null', () async {
      final bytes = await pdfService.generatePatientRegistrationFormPdf(
        camp: null,
        doctor: null,
        nurse: null,
        blankNurseLines: true,
        blankDoctorLines: true,
        allDoctorsChecklist: false,
        allNursesChecklist: false,
        page1Layout: BlankFormPage1Layout.classic,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(bytes.isNotEmpty, true);
      final file = File('test_samples/18_Blank_Universal_YellowForm_Classic.pdf');
      file.writeAsBytesSync(bytes);
      expect(file.existsSync(), true);
      expect(file.lengthSync(), greaterThan(50000));
    });

    test('19. Universal Follow-Up Encounter Slip with camp: null', () async {
      final bytes = await pdfService.generateBlankFollowUpSlipPdf(
        camp: null,
        doctor: null,
        blankDoctorLines: true,
        nurse: null,
        blankNurseLines: true,
        organizationName: 'Women For Society (SoDeSI Nepal)',
      );

      expect(bytes.isNotEmpty, true);
      final file = File('test_samples/19_Blank_Universal_FollowUpSlip.pdf');
      file.writeAsBytesSync(bytes);
      expect(file.existsSync(), true);
      expect(file.lengthSync(), greaterThan(50000));
    });
  });
}
