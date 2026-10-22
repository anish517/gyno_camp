import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gyno_camp/core/database/database_service.dart';
import 'package:gyno_camp/core/services/ocr_form_service.dart';
import 'package:gyno_camp/core/services/pdf_report_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/ocr_scan_result_model.dart';
import 'package:gyno_camp/repositories/audit_repository.dart';
import 'package:gyno_camp/repositories/ocr_repository.dart';
import 'package:gyno_camp/repositories/patient_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('OCR Form Round-Trip: Blank Forms, Filled Forms, Detection & SQLite Storage Verification', () {
    late Database testDb;
    late DatabaseService dbService;
    late AuditRepository auditRepo;
    late PatientRepository patientRepo;
    late OcrRepository ocrRepo;
    final pdfService = PdfReportService();
    const ocrService = OcrFormService();
    final outDir = Directory('test_samples/roundtrip');

    final testCamp = CampModel(
      id: 'camp-ktm-01',
      campCode: 'KTM01',
      name: 'Budhanilkantha Outreach Gyno Camp',
      province: 'Bagmati',
      district: 'Kathmandu',
      municipality: 'Budhanilkantha',
      ward: '04',
      venue: 'Budhanilkantha Health Center',
      startDate: DateTime(2026, 9, 6),
      endDate: DateTime(2026, 9, 8),
      status: CampStatus.open,
      tenantId: 'tenant_mohp_nepal',
      organizationName: 'Ministry of Health & Population - Nepal Rural Health',
      createdAt: DateTime(2026, 9, 1),
    );

    const testDoctor = DoctorProfile(
      name: 'Sagar Sharma',
      nmcNumber: '333/333',
    );

    const testNurse = NurseProfile(
      name: 'Sita Sharma',
      registrationNumber: '112233',
    );

    setUp(() async {
      if (!outDir.existsSync()) {
        outDir.createSync(recursive: true);
      }
      testDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      dbService = DatabaseService();
      await dbService.initializeTestDb(testDb);
      auditRepo = AuditRepository(databaseService: dbService);
      patientRepo = PatientRepository(databaseService: dbService, auditRepository: auditRepo);
      ocrRepo = OcrRepository(
        ocrService: ocrService,
        patientRepository: patientRepo,
        auditRepository: auditRepo,
      );
    });

    tearDown(() async {
      await testDb.close();
    });

    Future<({String page1, String page2})> extractPdfPages(File pdfFile) async {
      final txtPath = pdfFile.path.replaceAll('.pdf', '.txt');
      final proc = await Process.run('C:\\Program Files\\Git\\mingw64\\bin\\pdftotext.exe', [
        '-layout',
        '-enc',
        'UTF-8',
        pdfFile.path,
        txtPath,
      ]);
      expect(proc.exitCode, 0, reason: 'pdftotext must succeed on ${pdfFile.path}');
      final rawAll = File(txtPath).readAsStringSync();
      final pages = rawAll.split(RegExp(r'[\x0c\f]')).where((p) => p.trim().isNotEmpty).toList();
      expect(pages.length, greaterThanOrEqualTo(2), reason: 'PDF must have at least 2 pages');
      return (page1: pages[0], page2: pages[1]);
    }

    test('1. Blank Forms: Generate Grid and Classic Blank Forms and Verify No Hallucinated Data', () async {
      // A. Generate Blank Grid Form
      final blankGridBytes = await pdfService.generatePatientRegistrationFormPdf(
        camp: testCamp,
        doctor: testDoctor,
        nurse: testNurse,
        page1Layout: BlankFormPage1Layout.grid,
        organizationName: 'Ministry of Health & Population - Nepal Rural Health',
      );
      final blankGridPdf = File('${outDir.path}/blank_form_grid.pdf');
      blankGridPdf.writeAsBytesSync(blankGridBytes);
      expect(blankGridPdf.existsSync(), true);

      // B. Generate Blank Classic Form
      final blankClassicBytes = await pdfService.generatePatientRegistrationFormPdf(
        camp: testCamp,
        doctor: testDoctor,
        nurse: testNurse,
        page1Layout: BlankFormPage1Layout.classic,
        organizationName: 'Ministry of Health & Population - Nepal Rural Health',
      );
      final blankClassicPdf = File('${outDir.path}/blank_form_classic.pdf');
      blankClassicPdf.writeAsBytesSync(blankClassicBytes);
      expect(blankClassicPdf.existsSync(), true);

      // Extract and Parse Blank Grid Form
      final gridPages = await extractPdfPages(blankGridPdf);
      final scanGridP1 = ocrService.parseFormText(gridPages.page1, pageNumber: 1);
      final scanGridP2 = ocrService.parseFormText(gridPages.page2, pageNumber: 2);
      final scanGridMerged = OcrScanResultModel.merge(scanGridP1, scanGridP2);

      // Verification: Blank form must have no hallucinated patient names or abnormal findings
      expect(scanGridMerged.demographics['firstName'], isNull, reason: 'Blank form should not detect firstName');
      expect(scanGridMerged.demographics['surname'], isNull, reason: 'Blank form should not detect surname');
      expect(scanGridMerged.vitals['systolicBp'], isNull, reason: 'Blank form should not detect BP');
      expect(scanGridMerged.vitals['bloodGlucose'], isNull, reason: 'Blank form should not detect Glucose');
      expect(scanGridMerged.popStaging['highestPopStage'], 0, reason: 'Blank form highest POP should default to 0');
      expect(scanGridMerged.diagnoses, isEmpty, reason: 'Blank form should have no confirmed diagnoses');
      expect(scanGridMerged.medications, isEmpty, reason: 'Blank form should have no prescribed medications');
      expect(scanGridMerged.ringPessary, false, reason: 'Blank form should not have ring pessary fitted');
    });

    // Diverse Test Cases for Round-Trip
    final cases = <({
      String name,
      PatientModel patient,
      ClinicalVisitModel visit,
    })>[
      (
        name: 'Case1_Maya_Tamang_POP_Stage3_Ring65',
        patient: PatientModel(
          id: 'pat-rt-01',
          patientId: 'GC-KTM01-2026-00001',
          campId: 'camp-ktm-01',
          campCode: 'KTM01',
          intakeDate: DateTime(2026, 9, 6),
          firstName: 'Maya',
          surname: 'Tamang',
          age: 44,
          spouseOrFatherName: 'Som Bahadur Tamang',
          relationshipType: 'Husband',
          mobile: '9841987654',
          province: 'Bagmati',
          district: 'Kathmandu',
          municipality: 'Budhanilkantha',
          ward: '04',
          contactPerson: 'Bishal Tamang',
          contactMobile: '9851234567',
          maritalStatus: 'married',
          maritalAge: 18,
          reasonsForVisit: ['something hanging out', 'discharge and or itching'],
          consentTreatment: true,
          consentStoreMedicalInfo: true,
          createdAt: DateTime(2026, 9, 6),
          createdByUserId: 'usr-nurse-1',
          createdByDeviceId: 'dev-01',
          tenantId: 'tenant_mohp_nepal',
          isSynced: false,
        ),
        visit: ClinicalVisitModel(
          id: 'vis-rt-01',
          patientId: 'GC-KTM01-2026-00001',
          campId: 'camp-ktm-01',
          visitDate: DateTime(2026, 9, 6),
          deliveries: 3,
          livingChildren: 3,
          abortions: 0,
          anamnesisComplaints: {
            'complaintsDuration': '> 1 year',
            'clinicalComplaints': ['prolapse', 'discharge'],
          },
          uterusInside: false,
          pelvicFloorTone: 'hypertonic',
          popAnteriorStage: 2,
          popMiddleStage: 3,
          popPosteriorStage: 1,
          highestPopStage: 3,
          cervixRemarks: 'Erosion',
          vaginaRemarks: 'Mild discharge',
          systolicBp: 130,
          diastolicBp: 85,
          pulse: 78,
          spo2: 98,
          glucose: 115,
          urineTest: 'normal',
          pregnancyTest: 'neg',
          ecgNotes: 'Not Done',
          diagnoses: ['POP', 'candid infection'],
          medications: ['clotrimazol (canesten)', 'metronidazol'],
          pessaryType: 'ring',
          pessarySize: '65',
          counseling: ['weak pelvic floor', 'POP'],
          surgicalReferral: 'Scheer Memorial Hospital',
          followUpNeeded: true,
          followUpDestination: 'GynaeSupport Nurse',
          outtakeNotes: 'Fitted size 65mm ring pessary.',
          primaryDoctorName: 'Dr. Sagar Sharma',
          primaryNurseName: 'Sita Sharma',
          createdAt: DateTime(2026, 9, 6),
          createdByUserId: 'usr-doc-01',
        ),
      ),
      (
        name: 'Case2_Sunita_Thapa_Unmarried_Stage0',
        patient: PatientModel(
          id: 'pat-rt-02',
          patientId: 'GC-KTM01-2026-00002',
          campId: 'camp-ktm-01',
          campCode: 'KTM01',
          intakeDate: DateTime(2026, 9, 6),
          firstName: 'Sunita',
          surname: 'Thapa',
          age: 19,
          spouseOrFatherName: 'Ram Bahadur Thapa',
          relationshipType: 'Father',
          mobile: '9841122334',
          province: 'Bagmati',
          district: 'Lalitpur',
          municipality: 'Lalitpur',
          ward: '02',
          contactPerson: 'Gita Thapa',
          contactMobile: '9851998877',
          maritalStatus: 'unmarried',
          reasonsForVisit: ['menstrual problem', 'discharge and or itching'],
          consentTreatment: true,
          consentStoreMedicalInfo: true,
          createdAt: DateTime(2026, 9, 6),
          createdByUserId: 'usr-nurse-1',
          createdByDeviceId: 'dev-01',
          tenantId: 'tenant_mohp_nepal',
          isSynced: false,
        ),
        visit: ClinicalVisitModel(
          id: 'vis-rt-02',
          patientId: 'GC-KTM01-2026-00002',
          campId: 'camp-ktm-01',
          visitDate: DateTime(2026, 9, 6),
          deliveries: 0,
          livingChildren: 0,
          abortions: 0,
          anamnesisComplaints: {
            'complaintsDuration': '< 1month',
            'clinicalComplaints': ['menstrual', 'discharge'],
          },
          uterusInside: true,
          pelvicFloorTone: 'normal',
          popAnteriorStage: 0,
          popMiddleStage: 0,
          popPosteriorStage: 0,
          highestPopStage: 0,
          systolicBp: 110,
          diastolicBp: 70,
          pulse: 72,
          spo2: 99,
          glucose: 95,
          urineTest: 'normal',
          pregnancyTest: 'neg',
          ecgNotes: 'Normal Sinus',
          diagnoses: ['bacterial vaginosis', 'menstrual disorder'],
          medications: ['metronidazol', 'medroxyprogesterone'],
          counseling: ['abdominal pain'],
          followUpNeeded: true,
          followUpDestination: 'Health Post',
          primaryDoctorName: 'Dr. Sagar Sharma',
          primaryNurseName: 'Sita Sharma',
          createdAt: DateTime(2026, 9, 6),
          createdByUserId: 'usr-doc-01',
        ),
      ),
      (
        name: 'Case3_Parbati_BK_Widow_POP_Stage4_SupportRing',
        patient: PatientModel(
          id: 'pat-rt-03',
          patientId: 'GC-KTM01-2026-00003',
          campId: 'camp-ktm-01',
          campCode: 'KTM01',
          intakeDate: DateTime(2026, 9, 6),
          firstName: 'Parbati',
          surname: 'BK',
          age: 56,
          spouseOrFatherName: 'Late Dal Bahadur BK',
          relationshipType: 'Husband',
          mobile: '9849554433',
          province: 'Gandaki',
          district: 'Kaski',
          municipality: 'Pokhara',
          ward: '07',
          maritalStatus: 'widow',
          maritalAge: 16,
          reasonsForVisit: ['something hanging out', 'problems passing urine'],
          consentTreatment: true,
          consentStoreMedicalInfo: true,
          createdAt: DateTime(2026, 9, 6),
          createdByUserId: 'usr-nurse-1',
          createdByDeviceId: 'dev-01',
          tenantId: 'tenant_mohp_nepal',
          isSynced: false,
        ),
        visit: ClinicalVisitModel(
          id: 'vis-rt-03',
          patientId: 'GC-KTM01-2026-00003',
          campId: 'camp-ktm-01',
          visitDate: DateTime(2026, 9, 6),
          deliveries: 5,
          livingChildren: 4,
          abortions: 1,
          anamnesisComplaints: {
            'complaintsDuration': '> 5 years',
            'clinicalComplaints': ['prolapse', 'urine'],
          },
          uterusInside: false,
          pelvicFloorTone: 'weak',
          popAnteriorStage: 3,
          popMiddleStage: 4,
          popPosteriorStage: 2,
          highestPopStage: 4,
          cervixRemarks: 'Erosion',
          vaginaRemarks: 'Atrophic',
          systolicBp: 150,
          diastolicBp: 95,
          pulse: 84,
          spo2: 96,
          glucose: 165,
          urineTest: 'pos',
          pregnancyTest: 'neg',
          ecgNotes: 'Abnormal',
          diagnoses: ['POP', 'cystitis', 'atrophy vagina'],
          medications: ['nitrofurantoine', 'estradiol crème'],
          pessaryType: 'ring with support',
          pessarySize: '70',
          counseling: ['POP', 'weak pelvic floor'],
          surgicalReferral: 'Model Hospital',
          followUpNeeded: true,
          followUpDestination: 'Health Post',
          primaryDoctorName: 'Dr. Sagar Sharma',
          primaryNurseName: 'Sita Sharma',
          createdAt: DateTime(2026, 9, 6),
          createdByUserId: 'usr-doc-01',
        ),
      ),
      (
        name: 'Case4_Geeta_Gurung_Divorced_Infection_PositivePreg',
        patient: PatientModel(
          id: 'pat-rt-04',
          patientId: 'GC-KTM01-2026-00004',
          campId: 'camp-ktm-01',
          campCode: 'KTM01',
          intakeDate: DateTime(2026, 9, 6),
          firstName: 'Geeta',
          surname: 'Gurung',
          age: 38,
          spouseOrFatherName: 'Man Bahadur Gurung',
          relationshipType: 'Father',
          mobile: '9860112233',
          province: 'Bagmati',
          district: 'Chitwan',
          municipality: 'Bharatpur',
          ward: '05',
          maritalStatus: 'divorced',
          reasonsForVisit: ['discharge and or itching', 'pain'],
          consentTreatment: true,
          consentStoreMedicalInfo: true,
          createdAt: DateTime(2026, 9, 6),
          createdByUserId: 'usr-nurse-1',
          createdByDeviceId: 'dev-01',
          tenantId: 'tenant_mohp_nepal',
          isSynced: false,
        ),
        visit: ClinicalVisitModel(
          id: 'vis-rt-04',
          patientId: 'GC-KTM01-2026-00004',
          campId: 'camp-ktm-01',
          visitDate: DateTime(2026, 9, 6),
          deliveries: 2,
          livingChildren: 2,
          abortions: 0,
          anamnesisComplaints: {
            'complaintsDuration': '< 1 year',
            'clinicalComplaints': ['discharge', 'lower_abdomen_pain'],
          },
          uterusInside: true,
          pelvicFloorTone: 'normal',
          popAnteriorStage: 1,
          popMiddleStage: 1,
          popPosteriorStage: 1,
          highestPopStage: 1,
          systolicBp: 120,
          diastolicBp: 80,
          pulse: 76,
          spo2: 98,
          glucose: 105,
          urineTest: 'normal',
          pregnancyTest: 'pos',
          ecgNotes: 'Normal Sinus',
          diagnoses: ['pregnancy', 'trichomonas', 'PID'],
          medications: ['ciproflox', 'doxycycline'],
          surgicalReferral: 'Local Government Hospital',
          followUpNeeded: true,
          followUpDestination: 'Health Post',
          primaryDoctorName: 'Dr. Sagar Sharma',
          primaryNurseName: 'Sita Sharma',
          createdAt: DateTime(2026, 9, 6),
          createdByUserId: 'usr-doc-01',
        ),
      ),
      (
        name: 'Case5_Radha_Chaudhary_Married_StressIncontinence_KnobRing',
        patient: PatientModel(
          id: 'pat-rt-05',
          patientId: 'GC-KTM01-2026-00005',
          campId: 'camp-ktm-01',
          campCode: 'KTM01',
          intakeDate: DateTime(2026, 9, 6),
          firstName: 'Radha',
          surname: 'Chaudhary',
          age: 48,
          spouseOrFatherName: 'Ram Chandra Chaudhary',
          relationshipType: 'Husband',
          mobile: '9801234567',
          province: 'Madhesh',
          district: 'Parsa',
          municipality: 'Birgunj',
          ward: '03',
          maritalStatus: 'married',
          maritalAge: 19,
          reasonsForVisit: ['something hanging out', 'problems passing urine'],
          consentTreatment: true,
          consentStoreMedicalInfo: true,
          createdAt: DateTime(2026, 9, 6),
          createdByUserId: 'usr-nurse-1',
          createdByDeviceId: 'dev-01',
          tenantId: 'tenant_mohp_nepal',
          isSynced: false,
        ),
        visit: ClinicalVisitModel(
          id: 'vis-rt-05',
          patientId: 'GC-KTM01-2026-00005',
          campId: 'camp-ktm-01',
          visitDate: DateTime(2026, 9, 6),
          deliveries: 4,
          livingChildren: 3,
          abortions: 1,
          anamnesisComplaints: {
            'complaintsDuration': '> 1 year',
            'clinicalComplaints': ['prolapse', 'urine'],
          },
          uterusInside: false,
          pelvicFloorTone: 'hypertonic',
          popAnteriorStage: 2,
          popMiddleStage: 2,
          popPosteriorStage: 3,
          highestPopStage: 3,
          systolicBp: 135,
          diastolicBp: 85,
          pulse: 80,
          spo2: 97,
          glucose: 120,
          urineTest: 'normal',
          pregnancyTest: 'neg',
          ecgNotes: 'Normal Sinus',
          diagnoses: ['POP', 'stress incontinence', 'hypertonic pelvic floor muscle'],
          medications: ['mirasin', 'clobetasol'],
          pessaryType: 'ring with knob',
          pessarySize: '65',
          counseling: ['stress incontinence', 'weak pelvic floor'],
          surgicalReferral: 'Scheer Memorial Hospital',
          followUpNeeded: true,
          followUpDestination: 'GynaeSupport Nurse',
          primaryDoctorName: 'Dr. Sagar Sharma',
          primaryNurseName: 'Sita Sharma',
          createdAt: DateTime(2026, 9, 6),
          createdByUserId: 'usr-doc-01',
        ),
      ),
    ];

    for (final tc in cases) {
      test('Generate, Detect, Commit to SQLite & Verify: ${tc.name}', () async {
        // Step 1: Generate PDF Form
        final pdfBytes = await pdfService.generatePatientRegistrationFormPdf(
          patient: tc.patient,
          camp: testCamp,
          visit: tc.visit,
          doctor: testDoctor,
          nurse: testNurse,
          organizationName: 'Ministry of Health & Population - Nepal Rural Health',
        );
        final pdfFile = File('${outDir.path}/${tc.name}.pdf');
        pdfFile.writeAsBytesSync(pdfBytes);
        expect(pdfFile.existsSync(), true, reason: 'PDF must be written');

        // Step 2: Extract text layer using pdftotext
        final pages = await extractPdfPages(pdfFile);

        // Step 3: Parse Page 1 & Page 2 with OcrFormService
        final p1Result = ocrService.parseFormText(pages.page1, pageNumber: 1);
        final p2Result = ocrService.parseFormText(pages.page2, pageNumber: 2);
        final scan = OcrScanResultModel.merge(p1Result, p2Result);

        // Step 4: Verify OCR Detection Accuracy
        // Demographics
        expect(scan.demographics['firstName'], tc.patient.firstName);
        expect(scan.demographics['surname'], tc.patient.surname);
        expect(scan.demographics['age'], tc.patient.age);
        expect(scan.demographics['maritalStatus'], tc.patient.maritalStatus);
        expect(scan.demographics['ward'], tc.patient.ward);
        expect(scan.demographics['mobile'], tc.patient.mobile);

        // Vitals
        expect(scan.vitals['systolicBp'], tc.visit.systolicBp);
        expect(scan.vitals['diastolicBp'], tc.visit.diastolicBp);
        expect(scan.vitals['pulseRate'], tc.visit.pulse);
        expect(scan.vitals['spo2'], tc.visit.spo2);
        expect(scan.vitals['bloodGlucose'], tc.visit.glucose);
        expect(scan.vitals['urineTest'], tc.visit.urineTest);
        expect(scan.vitals['pregnancyTest'], tc.visit.pregnancyTest);

        // POP Staging & Pelvic Floor
        expect(scan.popStaging['anteriorStage'], tc.visit.popAnteriorStage);
        expect(scan.popStaging['middleStage'], tc.visit.popMiddleStage);
        expect(scan.popStaging['posteriorStage'], tc.visit.popPosteriorStage);
        expect(scan.popStaging['highestPopStage'], tc.visit.highestPopStage);
        expect(scan.popStaging['uterusInside'], tc.visit.uterusInside);
        expect(scan.popStaging['pelvicFloorTone'], tc.visit.pelvicFloorTone);

        // Diagnoses (all ground truth diagnoses should be detected)
        for (final diag in tc.visit.diagnoses) {
          expect(scan.diagnoses, contains(diag), reason: 'Diagnosis "$diag" should be detected');
        }

        // Medications (all prescribed medications should be detected)
        for (final med in tc.visit.medications) {
          expect(scan.medications, contains(med), reason: 'Medication "$med" should be detected');
        }

        // Pessary
        if (tc.visit.pessaryType != null) {
          expect(scan.ringPessary, true);
          expect(scan.pessaryType, tc.visit.pessaryType);
          expect(scan.ringPessarySize.toString(), tc.visit.pessarySize);
        }

        // Referrals
        if (tc.visit.surgicalReferral != null) {
          expect(scan.surgicalReferral, tc.visit.surgicalReferral);
        }

        // Step 5: Store in SQLite DB via OcrRepository
        final committedPatient = await ocrRepo.commitVerifiedScan(
          verifiedScan: scan,
          campId: testCamp.id,
          campCode: testCamp.campCode,
          userId: 'usr-nurse-1',
          userName: 'Sita Sharma',
          userRole: 'Nurse',
          deviceId: 'dev-field-tab-01',
          primaryDoctorName: testDoctor.displayName,
          primaryNurseName: testNurse.displayName,
        );

        // Step 6: Verify Database Storage Accuracy by reading back
        expect(committedPatient.patientId, tc.patient.patientId);
        expect(committedPatient.firstName, tc.patient.firstName);
        expect(committedPatient.surname, tc.patient.surname);
        expect(committedPatient.age, tc.patient.age);
        expect(committedPatient.ward, tc.patient.ward);
        expect(committedPatient.mobile, tc.patient.mobile);
        expect(committedPatient.maritalStatus, tc.patient.maritalStatus);

        final storedVisits = await patientRepo.getClinicalVisits(committedPatient.id);
        expect(storedVisits.length, 1, reason: 'Exactly one clinical visit should be saved');
        final sv = storedVisits.first;

        expect(sv.systolicBp, tc.visit.systolicBp);
        expect(sv.diastolicBp, tc.visit.diastolicBp);
        expect(sv.pulse, tc.visit.pulse);
        expect(sv.spo2, tc.visit.spo2);
        expect(sv.glucose, tc.visit.glucose);
        expect(sv.urineTest, tc.visit.urineTest);
        expect(sv.pregnancyTest, tc.visit.pregnancyTest);
        expect(sv.highestPopStage, tc.visit.highestPopStage);
        expect(sv.popAnteriorStage, tc.visit.popAnteriorStage);
        expect(sv.popMiddleStage, tc.visit.popMiddleStage);
        expect(sv.popPosteriorStage, tc.visit.popPosteriorStage);
        expect(sv.uterusInside, tc.visit.uterusInside);
        expect(sv.pelvicFloorTone, tc.visit.pelvicFloorTone);

        for (final diag in tc.visit.diagnoses) {
          expect(sv.diagnoses, contains(diag));
        }
        for (final med in tc.visit.medications) {
          expect(sv.medications, contains(med));
        }
        if (tc.visit.pessaryType != null) {
          expect(sv.pessaryType, tc.visit.pessaryType);
          expect(sv.pessarySize, '${tc.visit.pessarySize}mm');
        }
        if (tc.visit.surgicalReferral != null) {
          expect(sv.surgicalReferral, tc.visit.surgicalReferral);
        }
      });
    }
  });
}
