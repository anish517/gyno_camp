import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/constants/app_constants.dart';
import '../core/database/database_service.dart';
import '../core/database/database_tables.dart';
import '../core/services/excel_report_service.dart';
import '../core/services/pdf_report_service.dart';
import '../core/services/report_aggregation_service.dart';
import '../models/camp_model.dart';
import '../models/camp_report_summary_model.dart';
import '../models/clinical_visit_model.dart';
import '../models/patient_model.dart';
import 'audit_repository.dart';

abstract class IReportingRepository {
  Future<CampReportSummaryModel> getCampSummary({String? campId, String generatedBy = 'Data Analyst'});
  Future<Uint8List> generatePdfReport(CampReportSummaryModel summary);
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

    // Fetch Patients
    final List<Map<String, dynamic>> patientRows;
    if (campId != null && campId != 'all') {
      patientRows = await db.query(
        DatabaseTables.tablePatients,
        where: 'camp_id = ?',
        whereArgs: [campId],
        orderBy: 'created_at ASC',
      );
    } else {
      patientRows = await db.query(
        DatabaseTables.tablePatients,
        orderBy: 'created_at ASC',
      );
    }
    final patients = patientRows.map((r) => PatientModel.fromMap(r)).toList();

    // Fetch Clinical Visits
    final List<Map<String, dynamic>> visitRows;
    if (campId != null && campId != 'all') {
      visitRows = await db.query(
        DatabaseTables.tableClinicalVisits,
        where: 'camp_id = ?',
        whereArgs: [campId],
        orderBy: 'created_at ASC',
      );
    } else {
      visitRows = await db.query(
        DatabaseTables.tableClinicalVisits,
        orderBy: 'created_at ASC',
      );
    }
    final visits = visitRows.map((r) => ClinicalVisitModel.fromMap(r)).toList();

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
  Future<List<int>> generateExcelReport(CampReportSummaryModel summary) async {
    return _excelReportService.generateCampSummaryExcel(summary);
  }

  @override
  Future<String> saveReportToFile({
    required List<int> bytes,
    required String filename,
    String? targetDirectoryPath,
  }) async {
    String dirPath = targetDirectoryPath ?? '';
    if (dirPath.isEmpty) {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        dirPath = appDir.path;
      } catch (_) {
        // Fallback for non-GUI / headless test environments
        dirPath = Directory.systemTemp.path;
      }
    }

    final reportsDir = Directory(p.join(dirPath, 'gynocamp_reports'));
    if (!reportsDir.existsSync()) {
      reportsDir.createSync(recursive: true);
    }

    final file = File(p.join(reportsDir.path, filename));
    await file.writeAsBytes(bytes);
    return file.path;
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
