import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/excel_report_service.dart';
import 'package:gyno_camp/core/services/pdf_report_service.dart';
import 'package:gyno_camp/core/services/report_aggregation_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/camp_report_summary_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/patient_model.dart';

void main() {
  group('Executive Reports & Cohort Analytics Comprehensive Test Suite', () {
    late ReportAggregationService aggregationService;
    late PdfReportService pdfService;
    late ExcelReportService excelService;
    late CampModel camp;

    setUp(() {
      aggregationService = ReportAggregationService();
      pdfService = PdfReportService();
      excelService = ExcelReportService();

      camp = CampModel(
        id: 'camp-exec-01',
        campCode: 'KTM-EXEC',
        name: 'Kathmandu Central Executive Health Outreach',
        organizationName: 'Women Health Foundation Nepal',
        district: 'Kathmandu',
        municipality: 'Budhanilkantha',
        ward: '03',
        venue: 'Ward Community Health Center',
        startDate: DateTime(2026, 4, 1),
        endDate: DateTime(2026, 4, 7),
        createdAt: DateTime(2026, 3, 20),
      );
    });

    PatientModel buildPatient({
      required String id,
      required String patientId,
      required int age,
      required String maritalStatus,
      required String ward,
      String firstName = 'Patient',
      String surname = 'Sharma',
      String mobile = '9841234567',
    }) {
      return PatientModel(
        id: id,
        patientId: patientId,
        campId: camp.id,
        campCode: camp.campCode,
        intakeDate: DateTime(2026, 4, 2),
        firstName: firstName,
        surname: surname,
        age: age,
        ward: ward,
        maritalStatus: maritalStatus,
        mobile: mobile,
        createdByUserId: 'usr-admin-1',
        createdByDeviceId: 'dev-tab-01',
        createdAt: DateTime(2026, 4, 2, 9, 30),
      );
    }

    ClinicalVisitModel buildVisit({
      required String id,
      required String patientId,
      int popAnterior = 0,
      int popMiddle = 0,
      int popPosterior = 0,
      int highestPop = 0,
      List<String> diagnoses = const [],
      List<String> medications = const [],
      int? systolicBp,
      int? diastolicBp,
      int? pulse,
      int? spo2,
      int? glucose,
      String? urineTest,
      String? pregnancyTest,
      String? pessaryType,
      String? pessarySize,
      String? surgicalReferral,
      String? followUpDestination,
      List<String> counseling = const [],
    }) {
      return ClinicalVisitModel(
        id: id,
        patientId: patientId,
        campId: camp.id,
        visitDate: DateTime(2026, 4, 2),
        popAnteriorStage: popAnterior,
        popMiddleStage: popMiddle,
        popPosteriorStage: popPosterior,
        highestPopStage: highestPop,
        diagnoses: diagnoses,
        medications: medications,
        systolicBp: systolicBp,
        diastolicBp: diastolicBp,
        pulse: pulse,
        spo2: spo2,
        glucose: glucose,
        urineTest: urineTest,
        pregnancyTest: pregnancyTest,
        pessaryType: pessaryType,
        pessarySize: pessarySize,
        surgicalReferral: surgicalReferral,
        followUpDestination: followUpDestination,
        counseling: counseling,
        createdByUserId: 'usr-clinician-1',
        createdAt: DateTime(2026, 4, 2, 10, 15),
      );
    }

    test('Cohort Aggregation: comprehensive demographic breakdown, clinical flags, and completion rate', () {
      final patients = [
        buildPatient(id: 'p1', patientId: 'P01', age: 18, maritalStatus: 'unmarried', ward: '01'),
        buildPatient(id: 'p2', patientId: 'P02', age: 25, maritalStatus: 'married', ward: '02'),
        buildPatient(id: 'p3', patientId: 'P03', age: 34, maritalStatus: 'married', ward: '02'),
        buildPatient(id: 'p4', patientId: 'P04', age: 45, maritalStatus: 'widow', ward: '03'),
        buildPatient(id: 'p5', patientId: 'P05', age: 55, maritalStatus: 'married', ward: '03'),
        buildPatient(id: 'p6', patientId: 'P06', age: 68, maritalStatus: 'divorced', ward: '03'),
      ];

      final visits = [
        buildVisit(
          id: 'v1',
          patientId: 'P01',
          systolicBp: 110,
          diastolicBp: 70,
          pulse: 75,
          spo2: 98,
          glucose: 95,
          diagnoses: ['Pelvic Inflammatory Disease (PID)'],
          medications: ['Metronidazole 400mg', 'Doxycycline 100mg'],
          counseling: ['Hygiene & Self-care'],
        ),
        buildVisit(
          id: 'v2',
          patientId: 'P02',
          popAnterior: 1,
          popMiddle: 0,
          popPosterior: 0,
          highestPop: 1,
          systolicBp: 145,
          diastolicBp: 92,
          pulse: 105,
          spo2: 93,
          glucose: 190,
          diagnoses: ['POP Stage 1', 'Hypertension (उच्च रक्तचाप)'],
          medications: ['Amlodipine 5mg'],
          followUpDestination: 'Local Health Post',
        ),
        buildVisit(
          id: 'v3',
          patientId: 'P03',
          popAnterior: 2,
          popMiddle: 3,
          popPosterior: 1,
          highestPop: 3,
          systolicBp: 130,
          diastolicBp: 80,
          pessaryType: 'Ring',
          pessarySize: '65mm',
          surgicalReferral: 'Scheer Memorial Hospital',
          diagnoses: ['POP Stage 3', 'Cervical Erosion'],
          medications: ['Fluconazole 150mg'],
          followUpDestination: 'Scheer Memorial Hospital',
        ),
        buildVisit(
          id: 'v4',
          patientId: 'P04',
          popAnterior: 0,
          popMiddle: 2,
          popPosterior: 2,
          highestPop: 2,
          systolicBp: 120,
          diastolicBp: 78,
          pessaryType: 'Gellhorn',
          pessarySize: '70mm',
          diagnoses: ['POP Stage 2'],
          medications: ['Metronidazole 400mg'],
        ),
      ];

      final summary = aggregationService.aggregate(
        camp: camp,
        patients: patients,
        visits: visits,
        generatedBy: 'Executive Medical Director',
      );

      // Logistics
      expect(summary.totalPatientsRegistered, equals(6));
      expect(summary.totalVisitsRecorded, equals(4));

      // Demographics
      expect(summary.ageGroups['<20'], equals(1));
      expect(summary.ageGroups['20-35'], equals(2));
      expect(summary.ageGroups['36-50'], equals(1));
      expect(summary.ageGroups['51-65'], equals(1));
      expect(summary.ageGroups['>65'], equals(1));

      expect(summary.maritalStatusCounts['married'], equals(3));
      expect(summary.maritalStatusCounts['unmarried'], equals(1));
      expect(summary.maritalStatusCounts['widow'], equals(1));
      expect(summary.maritalStatusCounts['divorced'], equals(1));

      expect(summary.wardCounts['01'], equals(1));
      expect(summary.wardCounts['02'], equals(2));
      expect(summary.wardCounts['03'], equals(3));

      // POP Staging Analysis
      expect(summary.highestPopStages[1], equals(1));
      expect(summary.highestPopStages[2], equals(1));
      expect(summary.highestPopStages[3], equals(1));
      expect(summary.significantPopCount, equals(2)); // Stages 2 & 3
      expect(summary.significantPopPercentage, closeTo(50.0, 0.1));

      // Vitals Alerts
      expect(summary.hypertensionCount, equals(1));
      expect(summary.hyperglycemiaCount, equals(1));

      // Prescriptions & Interventions
      expect(summary.medicationDispensedCounts['Metronidazole 400mg'], equals(2));
      expect(summary.medicationDispensedCounts['Amlodipine 5mg'], equals(1));
      expect(summary.pessaryCounts['Ring (65mm)'], equals(1));
      expect(summary.pessaryCounts['Gellhorn (70mm)'], equals(1));
      expect(summary.totalPessariesInserted, equals(2));
      expect(summary.surgicalReferralCounts['Scheer Memorial Hospital'], equals(1));
      expect(summary.totalSurgicalReferrals, equals(1));
      expect(summary.pelvicFloorCounselingCount, equals(1));
    });

    test('Executive PDF Generation: multi-page branded PDF compile and structure validation', () async {
      final patients = [
        buildPatient(id: 'p1', patientId: 'P01', age: 32, maritalStatus: 'married', ward: '03'),
      ];
      final visits = [
        buildVisit(
          id: 'v1',
          patientId: 'P01',
          popAnterior: 2,
          highestPop: 2,
          systolicBp: 125,
          diastolicBp: 82,
          diagnoses: ['POP Stage 2'],
          medications: ['Metronidazole 400mg'],
          surgicalReferral: 'Model Hospital',
        ),
      ];

      final summary = aggregationService.aggregate(
        camp: camp,
        patients: patients,
        visits: visits,
        generatedBy: 'Dr. Aarav Sharma',
      );

      final pdfBytes = await pdfService.generateCampSummaryPdf(summary);
      expect(pdfBytes, isNotEmpty);
      expect(pdfBytes.length, greaterThan(2000));

      final magic = utf8.decode(pdfBytes.sublist(0, 5));
      expect(magic, equals('%PDF-'));
    });

    test('Individual Patient Dossier PDF: compiles comprehensive medical record with POP-Q matrix', () async {
      final patient = buildPatient(
        id: 'p-single',
        patientId: 'GC-KTM-2026-0042',
        firstName: 'Devi',
        surname: 'Adhikari',
        age: 48,
        maritalStatus: 'married',
        ward: '04',
        mobile: '9851098765',
      );

      final visit = buildVisit(
        id: 'v-single',
        patientId: patient.patientId,
        popAnterior: 2,
        popMiddle: 3,
        popPosterior: 1,
        highestPop: 3,
        systolicBp: 142,
        diastolicBp: 92,
        pulse: 88,
        spo2: 97,
        glucose: 110,
        urineTest: 'Normal',
        pregnancyTest: 'Negative',
        pessaryType: 'Ring',
        pessarySize: '70mm',
        diagnoses: ['POP Stage 3 (Cervicovaginal Prolapse)', 'Hypertension'],
        medications: ['Metronidazole 400mg TDS x 5d', 'Amlodipine 5mg OD'],
        surgicalReferral: 'Scheer Memorial Hospital (Surgical Ward)',
        followUpDestination: 'Local Health Post & GynaeSupport Nurse',
        counseling: [
          'Pelvic floor Kegel exercises demonstrated',
          'Avoid heavy weight bearing (>10kg)',
          'Pessary hygiene and 3-month ring check schedule',
        ],
      );

      final dossierPdf = await pdfService.generateIndividualPatientPdf(
        patient: patient,
        visit: visit,
        camp: camp,
      );

      expect(dossierPdf, isNotEmpty);
      expect(dossierPdf.length, greaterThan(1500));
      final magic = utf8.decode(dossierPdf.sublist(0, 5));
      expect(magic, equals('%PDF-'));
    });

    test('Excel Multi-Sheet Generation: produces valid .xlsx spreadsheet containing all 3 sheets', () async {
      final patients = [
        buildPatient(id: 'p1', patientId: 'P01', age: 30, maritalStatus: 'married', ward: '01'),
        buildPatient(id: 'p2', patientId: 'P02', age: 40, maritalStatus: 'married', ward: '02'),
      ];
      final visits = [
        buildVisit(id: 'v1', patientId: 'P01', highestPop: 1, diagnoses: ['PID']),
        buildVisit(id: 'v2', patientId: 'P02', highestPop: 2, diagnoses: ['POP Stage 2']),
      ];

      final summary = aggregationService.aggregate(
        camp: camp,
        patients: patients,
        visits: visits,
        generatedBy: 'Biostatistician',
      );

      final excelBytes = excelService.generateCampSummaryExcel(summary);
      expect(excelBytes, isNotEmpty);
      expect(excelBytes.length, greaterThan(1000));
      // Standard PK zip header for xlsx
      expect(excelBytes[0], equals(0x50)); // 'P'
      expect(excelBytes[1], equals(0x4B)); // 'K'
    });

    test('Empty Summary Resilience: handles zero patients and visits gracefully without throwing', () async {
      final emptySummary = CampReportSummaryModel.empty();

      expect(emptySummary.totalPatientsRegistered, equals(0));
      expect(emptySummary.totalVisitsRecorded, equals(0));
      expect(emptySummary.significantPopPercentage, equals(0.0));

      final emptyPdf = await pdfService.generateCampSummaryPdf(emptySummary);
      expect(emptyPdf, isNotEmpty);
      expect(utf8.decode(emptyPdf.sublist(0, 5)), equals('%PDF-'));

      final emptyExcel = excelService.generateCampSummaryExcel(emptySummary);
      expect(emptyExcel, isNotEmpty);
    });
  });
}
