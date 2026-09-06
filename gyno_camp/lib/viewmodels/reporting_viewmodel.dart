import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/constants/app_constants.dart';
import '../models/camp_report_summary_model.dart';
import '../repositories/reporting_repository.dart';

class ReportingState {
  final bool isLoading;
  final bool isExportingPdf;
  final bool isExportingExcel;
  final String? selectedCampId;
  final CampReportSummaryModel? summary;
  final String? lastExportPath;
  final String? lastExportFormat; // 'PDF' or 'EXCEL'
  final String? errorMessage;
  final String? successMessage;

  const ReportingState({
    this.isLoading = false,
    this.isExportingPdf = false,
    this.isExportingExcel = false,
    this.selectedCampId,
    this.summary,
    this.lastExportPath,
    this.lastExportFormat,
    this.errorMessage,
    this.successMessage,
  });

  bool get hasSummary => summary != null;

  ReportingState copyWith({
    bool? isLoading,
    bool? isExportingPdf,
    bool? isExportingExcel,
    String? selectedCampId,
    CampReportSummaryModel? summary,
    String? lastExportPath,
    String? lastExportFormat,
    String? errorMessage,
    String? successMessage,
    bool clearFeedback = false,
  }) {
    return ReportingState(
      isLoading: isLoading ?? this.isLoading,
      isExportingPdf: isExportingPdf ?? this.isExportingPdf,
      isExportingExcel: isExportingExcel ?? this.isExportingExcel,
      selectedCampId: selectedCampId ?? this.selectedCampId,
      summary: summary ?? this.summary,
      lastExportPath: lastExportPath ?? this.lastExportPath,
      lastExportFormat: lastExportFormat ?? this.lastExportFormat,
      errorMessage: clearFeedback ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearFeedback ? null : (successMessage ?? this.successMessage),
    );
  }
}

class ReportingViewModel extends StateNotifier<ReportingState> {
  final IReportingRepository reportingRepository;

  ReportingViewModel({required this.reportingRepository})
      : super(const ReportingState());

  Future<void> loadSummary({
    String? campId,
    String generatedBy = 'Data Analyst',
  }) async {
    state = state.copyWith(isLoading: true, clearFeedback: true);
    try {
      final res = await reportingRepository.getCampSummary(
        campId: campId,
        generatedBy: generatedBy,
      );
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        selectedCampId: campId,
        summary: res,
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to aggregate camp records: $e',
      );
    }
  }

  Future<String?> exportPdf({
    String userId = 'usr-analyst',
    String userName = 'Data Analyst',
    String userRole = AppConstants.roleDataAnalyst,
    String deviceId = 'dev-field',
    String? targetDirectoryPath,
  }) async {
    if (state.summary == null) {
      await loadSummary(campId: state.selectedCampId);
    }
    if (state.summary == null) return null;

    state = state.copyWith(isExportingPdf: true, clearFeedback: true);
    try {
      final summary = state.summary!;
      final bytes = await reportingRepository.generatePdfReport(summary);

      final dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final filename = 'Gynocamp_${summary.campCode}_Report_$dateStr.pdf';

      final savedPath = await reportingRepository.saveReportToFile(
        bytes: bytes,
        filename: filename,
        targetDirectoryPath: targetDirectoryPath,
      );

      await reportingRepository.auditReportExport(
        userId: userId,
        userName: userName,
        userRole: userRole,
        deviceId: deviceId,
        format: 'PDF',
        campCode: summary.campCode,
        totalPatients: summary.totalPatientsRegistered,
        filePath: savedPath,
      );

      if (!mounted) return savedPath;
      state = state.copyWith(
        isExportingPdf: false,
        lastExportPath: savedPath,
        lastExportFormat: 'PDF',
        successMessage: 'PDF report generated: $filename',
      );
      return savedPath;
    } catch (e) {
      if (!mounted) return null;
      state = state.copyWith(
        isExportingPdf: false,
        errorMessage: 'PDF export failed: $e',
      );
      return null;
    }
  }

  Future<String?> exportExcel({
    String userId = 'usr-analyst',
    String userName = 'Data Analyst',
    String userRole = AppConstants.roleDataAnalyst,
    String deviceId = 'dev-field',
    String? targetDirectoryPath,
  }) async {
    if (state.summary == null) {
      await loadSummary(campId: state.selectedCampId);
    }
    if (state.summary == null) return null;

    state = state.copyWith(isExportingExcel: true, clearFeedback: true);
    try {
      final summary = state.summary!;
      final bytes = await reportingRepository.generateExcelReport(summary);

      final dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final filename = 'Gynocamp_${summary.campCode}_Register_$dateStr.xlsx';

      final savedPath = await reportingRepository.saveReportToFile(
        bytes: bytes,
        filename: filename,
        targetDirectoryPath: targetDirectoryPath,
      );

      await reportingRepository.auditReportExport(
        userId: userId,
        userName: userName,
        userRole: userRole,
        deviceId: deviceId,
        format: 'EXCEL',
        campCode: summary.campCode,
        totalPatients: summary.totalPatientsRegistered,
        filePath: savedPath,
      );

      if (!mounted) return savedPath;
      state = state.copyWith(
        isExportingExcel: false,
        lastExportPath: savedPath,
        lastExportFormat: 'EXCEL',
        successMessage: 'Excel workbook generated: $filename',
      );
      return savedPath;
    } catch (e) {
      if (!mounted) return null;
      state = state.copyWith(
        isExportingExcel: false,
        errorMessage: 'Excel export failed: $e',
      );
      return null;
    }
  }

  void clearFeedback() {
    state = state.copyWith(clearFeedback: true);
  }
}

// Providers
final reportingRepositoryProvider = Provider<IReportingRepository>((ref) {
  return ReportingRepository();
});

final reportingViewModelProvider =
    StateNotifierProvider<ReportingViewModel, ReportingState>((ref) {
  final repo = ref.watch(reportingRepositoryProvider);
  return ReportingViewModel(reportingRepository: repo);
});
