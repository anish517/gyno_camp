import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/models/camp_report_summary_model.dart';
import 'package:gyno_camp/repositories/reporting_repository.dart';
import 'package:gyno_camp/viewmodels/reporting_viewmodel.dart';

class MockReportingRepository implements IReportingRepository {
  bool shouldThrowOnSummary = false;
  bool shouldThrowOnPdf = false;
  bool shouldThrowOnExcel = false;
  final List<String> auditedExports = [];

  @override
  Future<CampReportSummaryModel> getCampSummary({String? campId, String generatedBy = 'Data Analyst'}) async {
    if (shouldThrowOnSummary) throw Exception('Database read error');
    return CampReportSummaryModel.empty(generatedBy: generatedBy);
  }

  @override
  Future<Uint8List> generatePdfReport(CampReportSummaryModel summary) async {
    if (shouldThrowOnPdf) throw Exception('PDF generator crashed');
    return Uint8List.fromList([37, 80, 68, 70, 45]);
  }

  @override
  Future<List<int>> generateExcelReport(CampReportSummaryModel summary) async {
    if (shouldThrowOnExcel) throw Exception('Excel generator crashed');
    return [80, 75, 3, 4];
  }

  @override
  Future<String> saveReportToFile({
    required List<int> bytes,
    required String filename,
    String? targetDirectoryPath,
  }) async {
    return '/mock/reports/$filename';
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
  }) async {
    auditedExports.add('$format:$campCode:$totalPatients');
  }
}

void main() {
  group('ReportingViewModel Tests', () {
    late MockReportingRepository mockRepo;
    late ReportingViewModel viewModel;

    setUp(() {
      mockRepo = MockReportingRepository();
      viewModel = ReportingViewModel(reportingRepository: mockRepo);
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('initial state has no summary and is not loading', () {
      expect(viewModel.state.isLoading, isFalse);
      expect(viewModel.state.hasSummary, isFalse);
      expect(viewModel.state.isExportingPdf, isFalse);
      expect(viewModel.state.isExportingExcel, isFalse);
      expect(viewModel.state.lastExportPath, isNull);
    });

    test('loadSummary populates summary and resets loading state', () async {
      await viewModel.loadSummary(campId: 'camp-01');

      expect(viewModel.state.isLoading, isFalse);
      expect(viewModel.state.hasSummary, isTrue);
      expect(viewModel.state.selectedCampId, 'camp-01');
      expect(viewModel.state.errorMessage, isNull);
    });

    test('loadSummary captures errors gracefully', () async {
      mockRepo.shouldThrowOnSummary = true;
      await viewModel.loadSummary(campId: 'camp-01');

      expect(viewModel.state.isLoading, isFalse);
      expect(viewModel.state.hasSummary, isFalse);
      expect(viewModel.state.errorMessage, contains('Failed to aggregate'));
    });

    test('exportPdf generates report, saves file, and records audit trail', () async {
      await viewModel.loadSummary(campId: 'KTM01');

      final path = await viewModel.exportPdf(
        userId: 'usr-1',
        userName: 'Analyst 1',
        userRole: 'DATA_ANALYST',
        deviceId: 'dev-1',
      );

      expect(path, isNotNull);
      expect(path, contains('.pdf'));
      expect(viewModel.state.isExportingPdf, isFalse);
      expect(viewModel.state.lastExportPath, equals(path));
      expect(viewModel.state.lastExportFormat, 'PDF');
      expect(viewModel.state.successMessage, contains('PDF report generated'));
      expect(mockRepo.auditedExports.length, 1);
      expect(mockRepo.auditedExports.first, startsWith('PDF:'));
    });

    test('exportExcel generates spreadsheet and records audit trail', () async {
      await viewModel.loadSummary(campId: 'PKR01');

      final path = await viewModel.exportExcel(
        userId: 'usr-1',
        userName: 'Analyst 1',
        userRole: 'DATA_ANALYST',
        deviceId: 'dev-1',
      );

      expect(path, isNotNull);
      expect(path, contains('.xlsx'));
      expect(viewModel.state.isExportingExcel, isFalse);
      expect(viewModel.state.lastExportPath, equals(path));
      expect(viewModel.state.lastExportFormat, 'EXCEL');
      expect(viewModel.state.successMessage, contains('Excel workbook generated'));
      expect(mockRepo.auditedExports.length, 1);
      expect(mockRepo.auditedExports.first, startsWith('EXCEL:'));
    });

    test('exportPdf handles generation failures gracefully', () async {
      await viewModel.loadSummary(campId: 'KTM01');
      mockRepo.shouldThrowOnPdf = true;

      final path = await viewModel.exportPdf();

      expect(path, isNull);
      expect(viewModel.state.isExportingPdf, isFalse);
      expect(viewModel.state.errorMessage, contains('PDF export failed'));
    });
  });
}
