import 'package:flutter/foundation.dart';
import '../core/constants/app_constants.dart';
import '../core/database/database_service.dart';
import '../core/database/database_tables.dart';
import '../core/services/excel_report_service.dart';
import '../core/services/file_download_helper.dart';
import '../core/services/pdf_report_service.dart';
import '../core/services/report_aggregation_service.dart';
import '../models/camp_model.dart';
import '../models/camp_report_summary_model.dart';
import '../models/clinical_visit_model.dart';
import '../models/patient_model.dart';
import 'audit_repository.dart';

abstract class IReportingRepository {
  Future<CampReportSummaryModel> getCampSummary({
    String? campId,
    String generatedBy = 'Data Analyst',
    DateTime? startDate,
    DateTime? endDate,
    String? doctorFilter,
  });
  Future<Uint8List> generatePdfReport(CampReportSummaryModel summary);
  Future<Uint8List> generateIndividualPatientPdf({
    required PatientModel patient,
    ClinicalVisitModel? visit,
    List<ClinicalVisitModel>? allVisits,
    CampModel? camp,
    String organizationName = 'Nepal Gyno Health Outreach Network',
  });
  Future<List<int>> generateExcelReport(CampReportSummaryModel summary);
  Future<String> saveReportToFile({
    required List<int> bytes,
    required String filename,
    String? targetDirectoryPath,
  });
  Future<void> auditReportExport({
    required String userId,
    required String userName,
    required String userRole,
    required String deviceId,
    required String format, // 'PDF' or 'EXCEL'
    required String campCode,
    required int totalPatients,
    required String filePath,
  });
}

class ReportingRepository implements IReportingRepository {
  final DatabaseService _databaseService;
  final ReportAggregationService _aggregationService;
  final PdfReportService _pdfReportService;
  final ExcelReportService _excelReportService;
  final AuditRepository _auditRepository;

  ReportingRepository({
    DatabaseService? databaseService,
    ReportAggregationService? aggregationService,
    PdfReportService? pdfReportService,
    ExcelReportService? excelReportService,
    AuditRepository? auditRepository,
  })  : _databaseService = databaseService ?? DatabaseService(),
        _aggregationService = aggregationService ?? ReportAggregationService(),
        _pdfReportService = pdfReportService ?? PdfReportService(),
        _excelReportService = excelReportService ?? ExcelReportService(),
        _auditRepository = auditRepository ?? AuditRepository();

  @override
  Future<CampReportSummaryModel> getCampSummary({
    String? campId,
    String generatedBy = 'Data Analyst',
    DateTime? startDate,
    DateTime? endDate,
    String? doctorFilter,
  }) async {
    final db = await _databaseService.database;

    CampModel? camp;
    if (campId != null && campId != 'all') {
      final campRows = await db.query(
        DatabaseTables.tableCamps,
        where: 'id = ?',
        whereArgs: [campId],
      );
      if (campRows.isNotEmpty) {
        camp = CampModel.fromMap(campRows.first);
      }
    }

    // Build date range WHERE clause
    String? dateWhere;
    final List<dynamic> dateArgs = [];
    if (startDate != null && endDate != null) {
      dateWhere = 'created_at >= ? AND created_at <= ?';
      dateArgs.addAll([startDate.toIso8601String(), endDate.copyWith(hour: 23, minute: 59, second: 59).toIso8601String()]);
    } else if (startDate != null) {
      dateWhere = 'created_at >= ?';
      dateArgs.add(startDate.toIso8601String());
    } else if (endDate != null) {
      dateWhere = 'created_at <= ?';
      dateArgs.add(endDate.copyWith(hour: 23, minute: 59, second: 59).toIso8601String());
    }

    // Fetch Patients (with optional camp + date filter)
    final List<Map<String, dynamic>> patientRows;
    if (campId != null && campId != 'all') {
      final campFilter = dateWhere != null ? 'camp_id = ? AND $dateWhere' : 'camp_id = ?';
      final campArgs = [campId, ...dateArgs];
      patientRows = await db.query(
        DatabaseTables.tablePatients,
        where: campFilter,
        whereArgs: campArgs,
        orderBy: 'created_at ASC',
      );
    } else {
      final baseFilter = 'camp_id IN (SELECT id FROM ${DatabaseTables.tableCamps})';
      final fullFilter = dateWhere != null ? '$baseFilter AND $dateWhere' : baseFilter;
      patientRows = await db.query(
        DatabaseTables.tablePatients,
        where: fullFilter,
        whereArgs: dateArgs.isNotEmpty ? dateArgs : null,
        orderBy: 'created_at ASC',
      );
    }
    List<PatientModel> patients = patientRows.map((r) => PatientModel.fromMap(r)).toList();

    // Fetch Clinical Visits
    final List<Map<String, dynamic>> visitRows;
    if (campId != null && campId != 'all') {
      final visitFilter = dateWhere != null ? 'camp_id = ? AND $dateWhere' : 'camp_id = ?';
      final visitArgs = [campId, ...dateArgs];
      visitRows = await db.query(
        DatabaseTables.tableClinicalVisits,
        where: visitFilter,
        whereArgs: visitArgs,
        orderBy: 'created_at ASC',
      );
    } else {
      final baseFilter = 'camp_id IN (SELECT id FROM ${DatabaseTables.tableCamps})';
      final fullFilter = dateWhere != null ? '$baseFilter AND $dateWhere' : baseFilter;
      visitRows = await db.query(
        DatabaseTables.tableClinicalVisits,
        where: fullFilter,
        whereArgs: dateArgs.isNotEmpty ? dateArgs : null,
        orderBy: 'created_at ASC',
      );
    }
    List<ClinicalVisitModel> visits = visitRows.map((r) => ClinicalVisitModel.fromMap(r)).toList();

    // Apply Doctor Filter if requested
    if (doctorFilter != null && doctorFilter.trim().isNotEmpty && doctorFilter != 'all') {
      final docLower = doctorFilter.trim().toLowerCase();
      final matchingVisits = visits.where((v) {
        final primaryMatch = v.primaryDoctorName?.toLowerCase().contains(docLower) ?? false;
        final attendingMatch = v.attendingDoctorNames.any((d) => d.toLowerCase().contains(docLower));
        return primaryMatch || attendingMatch;
      }).toList();

      final matchingPatientIds = matchingVisits.map((v) => v.patientId).toSet();
      final campDoctorMatch = camp != null && (
        camp.doctorNames.any((d) => d.toLowerCase().contains(docLower)) ||
        camp.doctorName.toLowerCase().contains(docLower)
      );

      if (!campDoctorMatch) {
        visits = matchingVisits;
        patients = patients.where((p) => matchingPatientIds.contains(p.patientId)).toList();
      }
    }

    return _aggregationService.aggregate(
      camp: camp,
      patients: patients,
      visits: visits,
      generatedBy: generatedBy,
    );
  }

  @override
  Future<Uint8List> generatePdfReport(CampReportSummaryModel summary) async {
    return _pdfReportService.generateCampSummaryPdf(summary);
  }

  @override
  Future<Uint8List> generateIndividualPatientPdf({
    required PatientModel patient,
    ClinicalVisitModel? visit,
    List<ClinicalVisitModel>? allVisits,
    CampModel? camp,
    String organizationName = 'Nepal Gyno Health Outreach Network',
  }) async {
    return _pdfReportService.generateIndividualPatientPdf(
      patient: patient,
      visit: visit,
      allVisits: allVisits,
      camp: camp,
      organizationName: organizationName,
    );
  }

  @override
  Future<List<int>> generateExcelReport(CampReportSummaryModel summary) async {
    return _excelReportService.generateCampSummaryExcel(summary);
  }

  @override
  Future<String> saveReportToFile({
    required List<int> bytes,
    required String filename,
    String? targetDirectoryPath,
  }) async {
    return FileDownloadHelper.saveAndDownloadFile(
      bytes: bytes,
      filename: filename,
      targetDirectoryPath: targetDirectoryPath,
    );
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
    final action = format.toUpperCase() == 'PDF'
        ? AppConstants.auditActionReportPdfExport
        : AppConstants.auditActionReportExcelExport;

    await _auditRepository.logActivity(
      userId: userId,
      userName: userName,
      userRole: userRole,
      action: action,
      entityType: 'CampReport',
      entityId: campCode,
      detailsJson: '{"format":"$format","campCode":"$campCode","patients":$totalPatients,"path":"$filePath"}',
      deviceId: deviceId,
    );
  }
}
