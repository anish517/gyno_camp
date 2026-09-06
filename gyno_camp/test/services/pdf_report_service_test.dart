import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/pdf_report_service.dart';
import 'package:gyno_camp/core/services/report_aggregation_service.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/camp_report_summary_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/patient_model.dart';

void main() {
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
  });
}
