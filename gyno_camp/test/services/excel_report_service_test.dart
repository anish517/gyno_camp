import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/excel_report_service.dart';
import 'package:gyno_camp/core/services/report_aggregation_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/camp_report_summary_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/patient_model.dart';

void main() {
  group('ExcelReportService Tests', () {
    late ExcelReportService excelService;
    late ReportAggregationService aggregationService;

    setUp(() {
      excelService = ExcelReportService();
      aggregationService = ReportAggregationService();
    });

    test('generates valid multi-sheet .xlsx workbook containing all 3 sheets', () {
      final camp = CampModel(
        id: 'camp-excel-01',
        campCode: 'PKR01',
        name: 'Pokhara Women Health Camp',
        district: 'Kaski',
        municipality: 'Pokhara',
        ward: '08',
        venue: 'Western Regional Hospital',
        startDate: DateTime(2026, 4, 1),
        endDate: DateTime(2026, 4, 3),
        createdAt: DateTime(2026, 4, 1),
      );

      final patient = PatientModel(
        id: 'p1',
        patientId: 'GC-PKR01-2026-0001',
        campId: camp.id,
        campCode: camp.campCode,
        intakeDate: DateTime(2026, 4, 1),
        firstName: 'Geeta',
        surname: 'Gurung',
        age: 45,
        ward: '08',
        mobile: '9856000000',
        createdByUserId: 'usr-1',
        createdByDeviceId: 'dev-1',
        createdAt: DateTime.now(),
      );

      final visit = ClinicalVisitModel(
        id: 'v1',
        patientId: patient.patientId,
        campId: camp.id,
        visitDate: DateTime(2026, 4, 1),
        popAnteriorStage: 1,
        popMiddleStage: 2,
        highestPopStage: 2,
        diagnoses: ['POP Stage 2', 'Leukorrhea'],
        medications: ['Metronidazole 400mg'],
        pessaryType: 'Ring with Support',
        pessarySize: '70mm',
        surgicalReferral: 'Model Hospital',
        createdByUserId: 'usr-1',
        createdAt: DateTime.now(),
      );

      final summary = aggregationService.aggregate(
        camp: camp,
        patients: [patient],
        visits: [visit],
        generatedBy: 'Bikash Adhikari',
      );

      final bytes = excelService.generateCampSummaryExcel(summary);

      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(500));

      // Decode bytes and verify structure
      final decoded = Excel.decodeBytes(bytes);
      expect(decoded.tables.keys, contains('Camp_Summary'));
      expect(decoded.tables.keys, contains('Patient_Register'));
      expect(decoded.tables.keys, contains('Pathology_Prescriptions'));

      // Check rows in Camp_Summary
      final summarySheet = decoded.tables['Camp_Summary']!;
      expect(summarySheet.maxRows, greaterThanOrEqualTo(5));

      // Check rows in Patient_Register
      final registerSheet = decoded.tables['Patient_Register']!;
      expect(registerSheet.maxRows, greaterThanOrEqualTo(2)); // Header + 1 patient

      // Check rows in Pathology_Prescriptions
      final pathologySheet = decoded.tables['Pathology_Prescriptions']!;
      expect(pathologySheet.maxRows, greaterThanOrEqualTo(3));
    });

    test('generates valid workbook from empty summary', () {
      final emptySummary = CampReportSummaryModel.empty();
      final bytes = excelService.generateCampSummaryExcel(emptySummary);

      expect(bytes, isNotEmpty);
      final decoded = Excel.decodeBytes(bytes);
      expect(decoded.tables.keys, contains('Camp_Summary'));
      expect(decoded.tables.keys, contains('Patient_Register'));
      expect(decoded.tables.keys, contains('Pathology_Prescriptions'));
    });
  });
}
