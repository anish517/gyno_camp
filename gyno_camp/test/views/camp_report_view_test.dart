import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/camp_report_summary_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/repositories/reporting_repository.dart';
import 'package:gyno_camp/viewmodels/reporting_viewmodel.dart';
import 'package:gyno_camp/views/reports/camp_report_view.dart';

class FakeReportingRepository implements IReportingRepository {
  CampReportSummaryModel summary = CampReportSummaryModel(
    campId: 'camp-ui-01',
    campCode: 'KTM01',
    campName: 'Kathmandu Health Camp',
    district: 'Kathmandu',
    municipality: 'Budhanilkantha',
    venue: 'Health Post',
    startDate: DateTime(2026, 3, 1),
    endDate: DateTime(2026, 3, 5),
    generatedAt: DateTime.now(),
    generatedBy: 'Data Analyst',
    totalPatientsRegistered: 42,
    totalVisitsRecorded: 42,
    ageGroups: {'<20': 5, '20-35': 15, '36-50': 12, '51-65': 7, '>65': 3},
    maritalStatusCounts: {'married': 35, 'widow': 5, 'unmarried': 2},
    wardCounts: {'01': 20, '02': 22},
    anteriorStages: {0: 10, 1: 15, 2: 12, 3: 5},
    middleStages: {0: 15, 1: 12, 2: 10, 3: 4, 4: 1},
    posteriorStages: {0: 20, 1: 12, 2: 8, 3: 2},
    highestPopStages: {0: 8, 1: 14, 2: 12, 3: 6, 4: 2},
    significantPopCount: 20,
    significantPopPercentage: 47.6,
    diagnosisCounts: {'PID': 18, 'POP Stage 2': 12, 'Cervicitis': 8},
    hypertensionCount: 6,
    hyperglycemiaCount: 4,
    urinePositiveCount: 5,
    pregnancyPositiveCount: 2,
    pessaryCounts: {'Ring (65mm)': 8},
    totalPessariesInserted: 8,
    pelvicFloorCounselingCount: 25,
    surgicalReferralCounts: {'Scheer Memorial': 5, 'Model Hospital': 2},
    totalSurgicalReferrals: 7,
    followUpDestinationCounts: {'Health Post': 20},
    medicationDispensedCounts: {'Ciprofloxacin 500mg': 18, 'Metronidazole 400mg': 18},
    totalPrescriptionsCount: 36,
  );

  @override
  Future<CampReportSummaryModel> getCampSummary({String? campId, String generatedBy = 'Data Analyst'}) async {
    return summary;
  }

  @override
  Future<Uint8List> generatePdfReport(CampReportSummaryModel summary) async {
    return Uint8List.fromList([37, 80, 68, 70, 45]);
  }

  @override
  Future<Uint8List> generateIndividualPatientPdf({
    required PatientModel patient,
    ClinicalVisitModel? visit,
    CampModel? camp,
    String organizationName = 'Nepal Gyno Health Outreach Network',
  }) async {
    return Uint8List.fromList([37, 80, 68, 70, 45]);
  }

  @override
  Future<List<int>> generateExcelReport(CampReportSummaryModel summary) async {
    return [80, 75, 3, 4];
  }

  @override
  Future<String> saveReportToFile({
    required List<int> bytes,
    required String filename,
    String? targetDirectoryPath,
  }) async {
    return '/storage/emulated/0/Download/$filename';
  }

  @override
  Future<void> auditReportExport({
    required String userId,
    required String userName,
    required String userRole,
    required String deviceId,
    required String format,
    required String campCode,
    required int totalPatients,
    required String filePath,
  }) async {}
}

void main() {
  group('CampReportView Widget Tests', () {
    late FakeReportingRepository fakeRepo;

    setUp(() {
      fakeRepo = FakeReportingRepository();
    });

    testWidgets('renders KPI cards, demographic tabs, and export buttons', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reportingRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const CampReportView(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Camp Clinical Reports'), findsOneWidget);
      expect(find.text('Registered'), findsOneWidget);
      expect(find.text('42'), findsWidgets);
      expect(find.text('47.6%'), findsOneWidget);
      expect(find.text('Export PDF (पिडिएफ)'), findsOneWidget);
      expect(find.text('Export Excel (एक्सेल)'), findsOneWidget);
      expect(find.text('Demographics'), findsOneWidget);
      expect(find.text('POP Staging'), findsOneWidget);
      expect(find.text('Diagnoses'), findsOneWidget);
      expect(find.text('Treatment'), findsOneWidget);
    });

    testWidgets('switching tabs displays corresponding clinical sections', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reportingRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const CampReportView(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap POP Staging Tab
      await tester.tap(find.text('POP Staging'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Highest POP Stage (Baden-Walker / POP-Q)'), findsOneWidget);
      expect(find.textContaining('Clinically Significant Prolapse'), findsOneWidget);

      // Tap Diagnoses Tab
      await tester.tap(find.text('Diagnoses'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Ranked Pathologies Identified'), findsOneWidget);
      expect(find.text('PID'), findsOneWidget);

      // Tap Treatment Tab
      await tester.tap(find.text('Treatment'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Interventions & Referrals'), findsOneWidget);
      expect(find.text('• Pessaries Fitted: 8 patients'), findsOneWidget);
    });

    testWidgets('tapping Export PDF generates report and displays success banner', (WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reportingRepositoryProvider.overrideWithValue(fakeRepo),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const CampReportView(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Tap Export PDF button
      final pdfBtn = find.text('Export PDF (पिडिएफ)');
      expect(pdfBtn, findsOneWidget);
      await tester.tap(pdfBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('PDF report generated:'), findsOneWidget);
    });
  });
}
