import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/constants/app_constants.dart';
import '../models/camp_model.dart';
import '../models/camp_report_summary_model.dart';
import '../models/clinical_visit_model.dart';
import '../models/patient_model.dart';
import '../repositories/reporting_repository.dart';

class ReportingState {
  final bool isLoading;
  final bool isExportingPdf;
  final bool isExportingExcel;
  final String? selectedCampId;
  final CampReportSummaryModel? summary;
  final CampReportSummaryModel? unfilteredSummary;
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
    this.unfilteredSummary,
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
    bool clearSelectedCampId = false,
    CampReportSummaryModel? summary,
    CampReportSummaryModel? unfilteredSummary,
    bool clearUnfilteredSummary = false,
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
      selectedCampId: clearSelectedCampId ? null : (selectedCampId ?? this.selectedCampId),
      summary: summary ?? this.summary,
      unfilteredSummary: clearUnfilteredSummary ? null : (unfilteredSummary ?? this.unfilteredSummary),
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
    DateTime? startDate,
    DateTime? endDate,
    String? doctorFilter,
    String? diagnosisFilter,
    String? popStageFilter,
    String? treatmentFilter,
    String? complaintFilter,
  }) async {
    state = state.copyWith(isLoading: true, clearFeedback: true);
    try {
      final res = await reportingRepository.getCampSummary(
        campId: campId,
        generatedBy: generatedBy,
        startDate: startDate,
        endDate: endDate,
        doctorFilter: doctorFilter,
        diagnosisFilter: diagnosisFilter,
        popStageFilter: popStageFilter,
        treatmentFilter: treatmentFilter,
        complaintFilter: complaintFilter,
      );
      if (!mounted) return;

      final bool hasFilters = startDate != null ||
          endDate != null ||
          (doctorFilter != null && doctorFilter.isNotEmpty && doctorFilter != 'all') ||
          (diagnosisFilter != null && diagnosisFilter.isNotEmpty && diagnosisFilter != 'all') ||
          (popStageFilter != null && popStageFilter.isNotEmpty && popStageFilter != 'all') ||
          (treatmentFilter != null && treatmentFilter.isNotEmpty && treatmentFilter != 'all') ||
          (complaintFilter != null && complaintFilter.isNotEmpty && complaintFilter != 'all');

      CampReportSummaryModel? newUnfiltered = state.unfilteredSummary;
      if (!hasFilters || state.selectedCampId != campId || newUnfiltered == null) {
        if (!hasFilters) {
          newUnfiltered = res;
        } else {
          newUnfiltered = await reportingRepository.getCampSummary(
            campId: campId,
            generatedBy: generatedBy,
          );
        }
      }

      state = state.copyWith(
        isLoading: false,
        selectedCampId: campId,
        clearSelectedCampId: campId == null || campId == 'all',
        summary: res,
        unfilteredSummary: newUnfiltered,
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

  Future<String?> exportIndividualPatientPdf({
    required PatientModel patient,
    ClinicalVisitModel? visit,
    List<ClinicalVisitModel>? allVisits,
    CampModel? camp,
    String userId = 'usr-analyst',
    String userName = 'Data Analyst',
    String userRole = AppConstants.roleDataAnalyst,
    String deviceId = 'dev-field',
    String? targetDirectoryPath,
  }) async {
    state = state.copyWith(isExportingPdf: true, clearFeedback: true);
    try {
      final bytes = await reportingRepository.generateIndividualPatientPdf(
        patient: patient,
        visit: visit,
        allVisits: allVisits,
        camp: camp,
      );

      final dateStr = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final filename = 'Patient_${patient.patientId}_Summary_$dateStr.pdf';

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
        campCode: camp?.campCode ?? patient.campCode,
        totalPatients: 1,
        filePath: savedPath,
      );

      if (!mounted) return savedPath;
      state = state.copyWith(
        isExportingPdf: false,
        lastExportPath: savedPath,
        lastExportFormat: 'PDF',
        successMessage: 'Patient summary generated: $filename',
      );
      return savedPath;
    } catch (e) {
      if (!mounted) return null;
      state = state.copyWith(
        isExportingPdf: false,
        errorMessage: 'Individual export failed: $e',
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
