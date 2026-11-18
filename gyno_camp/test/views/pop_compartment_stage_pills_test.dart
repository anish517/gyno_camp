import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/theme/app_theme.dart';
import 'package:gyno_camp/models/camp_model.dart';
import 'package:gyno_camp/models/camp_report_summary_model.dart';
import 'package:gyno_camp/models/clinical_visit_model.dart';
import 'package:gyno_camp/models/lookup_item_model.dart';
import 'package:gyno_camp/models/patient_model.dart';
import 'package:gyno_camp/repositories/reporting_repository.dart';
import 'package:gyno_camp/viewmodels/reporting_viewmodel.dart';
import 'package:gyno_camp/views/reports/camp_report_view.dart';
import 'package:gyno_camp/views/shared/pop_compartment_stage_pills.dart';

class _PopMatrixReportingRepo implements IReportingRepository {
  final CampReportSummaryModel summary;
  _PopMatrixReportingRepo(this.summary);

  @override
  Future<CampReportSummaryModel> getCampSummary({
    String? campId,
    List<String>? allowedCampIds,
    String? doctorFilter,
    String? nurseFilter,
    String generatedBy = 'Data Analyst',
    DateTime? startDate,
    DateTime? endDate,
    String? diagnosisFilter,
    String? popStageFilter,
    String? treatmentFilter,
    String? treatmentLevelFilter,
    String? complaintFilter,
    String? visitReasonFilter,
  }) async =>
      summary;

  @override
  Future<Uint8List> generatePdfReport(CampReportSummaryModel summary) async => Uint8List(0);

  @override
  Future<Uint8List> generateIndividualPatientPdf({
    required PatientModel patient,
    ClinicalVisitModel? visit,
    List<ClinicalVisitModel>? allVisits,
    CampModel? camp,
    String organizationName = 'Nepal Gyno Health Outreach Network',
  }) async =>
      Uint8List(0);

  @override
  Future<List<int>> generateExcelReport(CampReportSummaryModel summary) async => [];

  @override
  Future<String> saveReportToFile({
    required List<int> bytes,
    required String filename,
    String? targetDirectoryPath,
  }) async =>
      filename;

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
  testWidgets('PopCompartmentStagePills renders Stage 0..maxStage counts per compartment', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PopCompartmentStagePills(
            stageCounts: {0: 0, 1: 0, 2: 1, 3: 0},
            maxStage: 3,
          ),
        ),
      ),
    );

    expect(find.text('St 0: 0'), findsOneWidget);
    expect(find.text('St 1: 0'), findsOneWidget);
    expect(find.text('St 2: 1'), findsOneWidget);
    expect(find.text('St 3: 0'), findsOneWidget);
    expect(find.text('St 4: 0'), findsNothing);
  });

  testWidgets('PopCompartmentStagePills supports Stage 4 for apical compartment', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PopCompartmentStagePills(
            stageCounts: {0: 0, 1: 0, 2: 0, 3: 1, 4: 0},
            maxStage: 4,
          ),
        ),
      ),
    );

    expect(find.text('St 3: 1'), findsOneWidget);
    expect(find.text('St 4: 0'), findsOneWidget);
  });

  test('LookupItemModel.bilingualLabel omits duplicate Nepali labels matching labelEn', () {
    const identicalMed = LookupItemModel(
      id: 'med-2',
      category: 'medicine',
      code: 'estradiol_creme',
      labelEn: 'estradiol crème',
      labelNe: 'Estradiol Crème',
    );
    const blankNe = LookupItemModel(
      id: 'med-custom',
      category: 'medicine',
      code: 'calcium',
      labelEn: 'Calcium + Vit D3',
      labelNe: '   ',
    );
    const bilingual = LookupItemModel(
      id: 'diag-1',
      category: 'diagnosis',
      code: 'pop',
      labelEn: 'Pelvic Organ Prolapse',
      labelNe: 'आङ खस्ने',
    );

    expect(identicalMed.bilingualLabel, 'estradiol crème');
    expect(blankNe.bilingualLabel, 'Calcium + Vit D3');
    expect(bilingual.bilingualLabel, 'Pelvic Organ Prolapse (आङ खस्ने)');
  });

  testWidgets('CampReportView shows Highest stage filter label and per-compartment Stage pills in POP Staging tab', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final summary = CampReportSummaryModel(
      campId: 'camp-1',
      campCode: '123',
      campName: '1st testing camp',
      district: 'Dhankuta',
      municipality: 'Dhankuta Mun',
      venue: 'Hosp. Hall',
      startDate: DateTime(2026, 7, 26),
      endDate: DateTime(2026, 8, 1),
      generatedAt: DateTime(2026, 8, 1),
      generatedBy: 'Data Analyst',
      totalPatientsRegistered: 1,
      totalVisitsRecorded: 1,
      ageGroups: const {'51-65': 1},
      maritalStatusCounts: const {'married': 1},
      wardCounts: const {'05': 1},
      anteriorStages: const {0: 0, 1: 0, 2: 1, 3: 0},
      middleStages: const {0: 0, 1: 0, 2: 0, 3: 1, 4: 0},
      posteriorStages: const {0: 0, 1: 1, 2: 0, 3: 0},
      highestPopStages: const {0: 0, 1: 0, 2: 0, 3: 1, 4: 0},
      significantPopCount: 1,
      significantPopPercentage: 100.0,
      diagnosisCounts: const {},
      hypertensionCount: 0,
      hyperglycemiaCount: 0,
      urinePositiveCount: 0,
      pregnancyPositiveCount: 0,
      pessaryCounts: const {},
      totalPessariesInserted: 1,
      pelvicFloorCounselingCount: 1,
      surgicalReferralCounts: const {},
      totalSurgicalReferrals: 0,
      followUpDestinationCounts: const {},
      medicationDispensedCounts: const {},
      totalPrescriptionsCount: 1,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          reportingRepositoryProvider.overrideWithValue(_PopMatrixReportingRepo(summary)),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const CampReportView(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('POP Prolapse Stage (Highest):'), findsOneWidget);
    expect(find.text('All POP Stages (Highest)'), findsOneWidget);

    await tester.tap(find.text('Treatment'));
    await tester.pumpAndSettle();
    expect(find.text('• Specific Counseling: 1 counseled'), findsOneWidget);

    await tester.tap(find.text('POP Staging'));
    await tester.pumpAndSettle();

    expect(find.text('Compartment Prolapse Breakdown (Station 2)'), findsOneWidget);
    expect(find.text('1 case (100.0%)'), findsNWidgets(3));
    expect(find.text('St 2: 1'), findsOneWidget);
    expect(find.text('St 3: 1'), findsOneWidget);
    expect(find.text('St 1: 1'), findsOneWidget);
    expect(find.text('St 4: 0'), findsOneWidget);
  });
}
