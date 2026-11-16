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
    List<String>? allowedCampIds,
    String generatedBy = 'Data Analyst',
    DateTime? startDate,
    DateTime? endDate,
    String? doctorFilter,
    String? nurseFilter,
    String? diagnosisFilter,
    String? popStageFilter,
    String? treatmentFilter,
    String? complaintFilter,
    String? visitReasonFilter,
    String? treatmentLevelFilter,
  });
  Future<Uint8List> generatePdfReport(CampReportSummaryModel summary);
  Future<Uint8List> generateIndividualPatientPdf({
    required PatientModel patient,
    ClinicalVisitModel? visit,
    List<ClinicalVisitModel>? allVisits,
    CampModel? camp,
    String organizationName = AppConstants.defaultOrganizationName,
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
    List<String>? allowedCampIds,
    String generatedBy = 'Data Analyst',
    DateTime? startDate,
    DateTime? endDate,
    String? doctorFilter,
    String? nurseFilter,
    String? diagnosisFilter,
    String? popStageFilter,
    String? treatmentFilter,
    String? complaintFilter,
    String? visitReasonFilter,
    String? treatmentLevelFilter,
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

    if (allowedCampIds != null && allowedCampIds.isEmpty) {
      return CampReportSummaryModel.empty(generatedBy: generatedBy);
    }

    // Build date range WHERE clause using clinical encounter dates (intake_date / visit_date)
    // with fallback to created_at
    String? patientDateWhere;
    String? visitDateWhere;
    final List<dynamic> dateArgs = [];
    final startIso = startDate != null
        ? DateTime(startDate.year, startDate.month, startDate.day).toIso8601String()
        : null;
    final endIso = endDate != null
        ? DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59).toIso8601String()
        : null;
    if (startIso != null && endIso != null) {
      patientDateWhere = 'COALESCE(intake_date, created_at) >= ? AND COALESCE(intake_date, created_at) <= ?';
      visitDateWhere = 'COALESCE(visit_date, created_at) >= ? AND COALESCE(visit_date, created_at) <= ?';
      dateArgs.addAll([startIso, endIso]);
    } else if (startIso != null) {
      patientDateWhere = 'COALESCE(intake_date, created_at) >= ?';
      visitDateWhere = 'COALESCE(visit_date, created_at) >= ?';
      dateArgs.add(startIso);
    } else if (endIso != null) {
      patientDateWhere = 'COALESCE(intake_date, created_at) <= ?';
      visitDateWhere = 'COALESCE(visit_date, created_at) <= ?';
      dateArgs.add(endIso);
    }

    // Fetch Patients (with optional camp + date filter)
    final List<Map<String, dynamic>> patientRows;
    if (campId != null && campId != 'all') {
      final campFilter = patientDateWhere != null ? 'camp_id = ? AND $patientDateWhere' : 'camp_id = ?';
      final campArgs = [campId, ...dateArgs];
      patientRows = await db.query(
        DatabaseTables.tablePatients,
        where: campFilter,
        whereArgs: campArgs,
        orderBy: 'created_at ASC',
      );
    } else if (allowedCampIds != null) {
      final placeholders = List.filled(allowedCampIds.length, '?').join(', ');
      final campFilter = patientDateWhere != null
          ? 'camp_id IN ($placeholders) AND $patientDateWhere'
          : 'camp_id IN ($placeholders)';
      final campArgs = [...allowedCampIds, ...dateArgs];
      patientRows = await db.query(
        DatabaseTables.tablePatients,
        where: campFilter,
        whereArgs: campArgs,
        orderBy: 'created_at ASC',
      );
    } else {
      final baseFilter = 'camp_id IN (SELECT id FROM ${DatabaseTables.tableCamps})';
      final fullFilter = patientDateWhere != null ? '$baseFilter AND $patientDateWhere' : baseFilter;
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
      final visitFilter = visitDateWhere != null ? 'camp_id = ? AND $visitDateWhere' : 'camp_id = ?';
      final visitArgs = [campId, ...dateArgs];
      visitRows = await db.query(
        DatabaseTables.tableClinicalVisits,
        where: visitFilter,
        whereArgs: visitArgs,
        orderBy: 'created_at ASC',
      );
    } else if (allowedCampIds != null) {
      final placeholders = List.filled(allowedCampIds.length, '?').join(', ');
      final visitFilter = visitDateWhere != null
          ? 'camp_id IN ($placeholders) AND $visitDateWhere'
          : 'camp_id IN ($placeholders)';
      final visitArgs = [...allowedCampIds, ...dateArgs];
      visitRows = await db.query(
        DatabaseTables.tableClinicalVisits,
        where: visitFilter,
        whereArgs: visitArgs,
        orderBy: 'created_at ASC',
      );
    } else {
      final baseFilter = 'camp_id IN (SELECT id FROM ${DatabaseTables.tableCamps})';
      final fullFilter = visitDateWhere != null ? '$baseFilter AND $visitDateWhere' : baseFilter;
      visitRows = await db.query(
        DatabaseTables.tableClinicalVisits,
        where: fullFilter,
        whereArgs: dateArgs.isNotEmpty ? dateArgs : null,
        orderBy: 'created_at ASC',
      );
    }
    List<ClinicalVisitModel> visits = visitRows.map((r) => ClinicalVisitModel.fromMap(r)).toList();

    bool patientMatchesVisitIds(PatientModel p, Set<String> visitPatientKeys) {
      return visitPatientKeys.contains(p.patientId.trim().toLowerCase()) ||
          (p.id.trim().isNotEmpty && visitPatientKeys.contains(p.id.trim().toLowerCase()));
    }

    bool visitMatchesPatientKeys(ClinicalVisitModel v, Set<String> patientKeys) {
      return patientKeys.contains(v.patientId.trim().toLowerCase());
    }

    ClinicalVisitModel? findLatestVisitForPatient(PatientModel p, List<ClinicalVisitModel> visitList) {
      final pId = p.patientId.trim().toLowerCase();
      final pUuid = p.id.trim().toLowerCase();
      ClinicalVisitModel? latest;
      for (final v in visitList) {
        final vKey = v.patientId.trim().toLowerCase();
        if (vKey == pId || (pUuid.isNotEmpty && vKey == pUuid)) {
          if (latest == null || !v.visitDate.isBefore(latest.visitDate)) {
            latest = v;
          }
        }
      }
      return latest;
    }

    // If a date filter was applied, keep visits whose patient matched intake_date or vice versa
    if (startIso != null || endIso != null) {
      final pKeys = <String>{
        for (final p in patients) ...[
          p.patientId.trim().toLowerCase(),
          if (p.id.trim().isNotEmpty) p.id.trim().toLowerCase(),
        ]
      };
      visits = visits.where((v) => visitMatchesPatientKeys(v, pKeys)).toList();
    }

    // Apply Doctor Filter if requested
    if (doctorFilter != null && doctorFilter.trim().isNotEmpty && doctorFilter != 'all') {
      bool docNamesMatch(String a, String b) {
        final cleanA = a.replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim().toLowerCase();
        final cleanB = b.replaceAll(RegExp(r'^(Dr\.?\s*)+', caseSensitive: false), '').trim().toLowerCase();
        if (cleanA.isEmpty || cleanB.isEmpty) return false;
        return cleanA == cleanB || cleanA.contains(cleanB) || cleanB.contains(cleanA);
      }

      final matchingVisits = visits.where((v) {
        final primaryMatch = v.primaryDoctorName != null && docNamesMatch(v.primaryDoctorName!, doctorFilter);
        final attendingMatch = v.attendingDoctorNames.any((d) => docNamesMatch(d, doctorFilter));
        return primaryMatch || attendingMatch;
      }).toList();

      final matchingPatientKeys = matchingVisits.map((v) => v.patientId.trim().toLowerCase()).toSet();
      visits = matchingVisits;
      patients = patients.where((p) => patientMatchesVisitIds(p, matchingPatientKeys)).toList();
    }

    // Apply Nurse Filter if requested (visit-based only, no solo-nurse-queue fallback)
    if (nurseFilter != null && nurseFilter.trim().isNotEmpty && nurseFilter != 'all') {
      bool nurseNamesMatch(String a, String b) {
        final cleanA = NurseProfile.stripPrefixes(a).toLowerCase().trim();
        final cleanB = NurseProfile.stripPrefixes(b).toLowerCase().trim();
        if (cleanA.isEmpty || cleanB.isEmpty) return false;
        return cleanA == cleanB || cleanA.contains(cleanB) || cleanB.contains(cleanA);
      }

      final matchingVisits = visits.where((v) {
        final primaryMatch = v.primaryNurseName != null && nurseNamesMatch(v.primaryNurseName!, nurseFilter);
        final attendingMatch = v.attendingNurseNames.any((n) => nurseNamesMatch(n, nurseFilter));
        return primaryMatch || attendingMatch;
      }).toList();

      final matchingPatientKeys = matchingVisits.map((v) => v.patientId.trim().toLowerCase()).toSet();
      visits = matchingVisits;
      patients = patients.where((p) => patientMatchesVisitIds(p, matchingPatientKeys)).toList();
    }

    // Apply Diagnosis Filter if requested (dynamic substring match)
    if (diagnosisFilter != null && diagnosisFilter.trim().isNotEmpty && diagnosisFilter != 'all') {
      final dxLower = diagnosisFilter.trim().toLowerCase();
      final matchingVisits = visits.where((v) {
        return v.diagnoses.any((d) {
          final dLower = d.trim().toLowerCase();
          return dLower == dxLower || dLower.contains(dxLower) || dxLower.contains(dLower);
        });
      }).toList();
      final matchingPatientKeys = matchingVisits.map((v) => v.patientId.trim().toLowerCase()).toSet();
      visits = matchingVisits;
      patients = patients.where((p) => patientMatchesVisitIds(p, matchingPatientKeys)).toList();
    }

    // Apply POP Staging Filter if requested
    if (popStageFilter != null && popStageFilter.trim().isNotEmpty && popStageFilter != 'all') {
      final matchingVisits = visits.where((v) {
        if (popStageFilter == '0') return v.highestPopStage == 0;
        if (popStageFilter == '1') return v.highestPopStage == 1;
        if (popStageFilter == '2') return v.highestPopStage == 2;
        if (popStageFilter == '3') return v.highestPopStage == 3;
        if (popStageFilter == '4') return v.highestPopStage == 4;
        if (popStageFilter == '2+' || popStageFilter == 'significant') return v.highestPopStage >= 2;
        if (popStageFilter == '3+') return v.highestPopStage >= 3;
        return true;
      }).toList();
      final matchingPatientKeys = matchingVisits.map((v) => v.patientId.trim().toLowerCase()).toSet();
      visits = matchingVisits;
      patients = patients.where((p) => patientMatchesVisitIds(p, matchingPatientKeys)).toList();
    }

    // Apply Treatment Filter if requested
    if (treatmentFilter != null && treatmentFilter.trim().isNotEmpty && treatmentFilter != 'all') {
      final matchingVisits = visits.where((v) {
        if (treatmentFilter == 'pessary') {
          return (v.pessaryType != null && v.pessaryType!.trim().isNotEmpty) ||
              (v.pessarySize != null && v.pessarySize!.trim().isNotEmpty);
        }
        if (treatmentFilter == 'surgery') {
          return (v.surgicalReferral != null && v.surgicalReferral!.trim().isNotEmpty) ||
              v.surgeryDone == true;
        }
        if (treatmentFilter == 'counseling') {
          return v.counseling.isNotEmpty;
        }
        if (treatmentFilter == 'medications') {
          return v.medications.isNotEmpty || (v.customMedication != null && v.customMedication!.trim().isNotEmpty);
        }
        if (treatmentFilter.startsWith('med:')) {
          final targetMed = treatmentFilter.substring(4).toLowerCase().trim();
          final hasStandard = v.medications.any((m) => m.toLowerCase().contains(targetMed));
          final hasCustom = v.customMedication?.toLowerCase().contains(targetMed) ?? false;
          return hasStandard || hasCustom;
        }
        if (treatmentFilter.startsWith('hosp:')) {
          final targetHosp = treatmentFilter.substring(5).toLowerCase().trim();
          return v.surgicalReferral?.toLowerCase().contains(targetHosp) ?? false;
        }
        return true;
      }).toList();
      final matchingPatientKeys = matchingVisits.map((v) => v.patientId.trim().toLowerCase()).toSet();
      visits = matchingVisits;
      patients = patients.where((p) => patientMatchesVisitIds(p, matchingPatientKeys)).toList();
    }

    // Apply Visit Reason Filter if requested (Station 1 intake reason)
    if (visitReasonFilter != null && visitReasonFilter.trim().isNotEmpty && visitReasonFilter != 'all') {
      final target = visitReasonFilter.trim().toLowerCase();
      patients = patients.where((p) {
        final reasons = p.reasonsForVisit.map((r) => r.toLowerCase().trim()).toList();
        if (reasons.any((r) => r == target || r.contains(target) || target.contains(r))) return true;
        if (target == 'prolapse' || target.contains('hanging') || target.contains('खस्ने') || target.contains('खसेको')) {
          return reasons.any((r) => r.contains('hanging') || r.contains('prolapse') || r.contains('खस्ने') || r.contains('खसेको'));
        }
        if (target == 'discharge' || target.contains('itching') || target.contains('स्राव') || target.contains('चिलाउने') || target.contains('सेतो')) {
          return reasons.any((r) => r.contains('discharge') || r.contains('itching') || r.contains('स्राव') || r.contains('चिलाउने') || r.contains('सेतो'));
        }
        if (target == 'urine' || target.contains('dysuria') || target.contains('पिसाब')) {
          return reasons.any((r) => r.contains('urine') || r.contains('dysuria') || r.contains('पिसाब'));
        }
        if (target == 'stool' || target.contains('bowel') || target.contains('constipation') || target.contains('दिसा')) {
          return reasons.any((r) => r.contains('stool') || r.contains('bowel') || r.contains('constipation') || r.contains('दिसा'));
        }
        if (target == 'pain' || target.contains('दुखाई') || target.contains('दुख्ने') || target.contains('तल्लो पेट')) {
          return reasons.any((r) => r.contains('pain') || r.contains('दुखाई') || r.contains('दुख्ने') || r.contains('तल्लो पेट'));
        }
        if (target == 'menstrual' || target.contains('महिनावारी') || target.contains('bleeding')) {
          return reasons.any((r) => r.contains('menstrual') || r.contains('महिनावारी') || r.contains('bleeding'));
        }
        if (target == 'infertility' || target.contains('बाँझोपन') || target.contains('निःसन्तान')) {
          return reasons.any((r) => r.contains('infertility') || r.contains('बाँझोपन') || r.contains('निःसन्तान'));
        }
        if (target == 'checkup' || target.contains('routine') || target.contains('जाँच')) {
          return reasons.any((r) => r.contains('checkup') || r.contains('routine') || r.contains('जाँच'));
        }
        return false;
      }).toList();

      final matchingPatientKeys = <String>{
        for (final p in patients) ...[
          p.patientId.trim().toLowerCase(),
          if (p.id.trim().isNotEmpty) p.id.trim().toLowerCase(),
        ]
      };
      visits = visits.where((v) => visitMatchesPatientKeys(v, matchingPatientKeys)).toList();
    }

    // Apply Chief Complaint Filter if requested (Clinical Anamnesis / Exam Symptoms)
    if (complaintFilter != null && complaintFilter.trim().isNotEmpty && complaintFilter != 'all') {
      final target = complaintFilter.trim().toLowerCase();

      final matchingPatients = patients.where((p) {
        final visit = findLatestVisitForPatient(p, visits);
        if (visit == null) return false;
        final anamnesis = visit.anamnesisComplaints.toString().toLowerCase();
        final clinicalComplaints = (visit.anamnesisComplaints['clinicalComplaints'] as List?)
            ?.map((e) => e.toString().toLowerCase())
            .toList() ?? [];

        if (clinicalComplaints.any((c) => c == target || c.contains(target) || target.contains(c))) {
          return true;
        }

        if (target == 'something hanging out' || target == 'prolapse' || target == 'pelvic_organ_prolapse') {
          return anamnesis.contains('hanging') || anamnesis.contains('prolapse') || anamnesis.contains('खस्ने') || anamnesis.contains('pelvic_organ_prolapse');
        } else if (target == 'discharge and or itching' || target == 'discharge') {
          return anamnesis.contains('discharge') || anamnesis.contains('itching') || anamnesis.contains('स्राव') || anamnesis.contains('चिलाउने') || anamnesis.contains('सेतो');
        } else if (target == 'problems passing urine' || target == 'urine') {
          return anamnesis.contains('urine') || anamnesis.contains('dysuria') || anamnesis.contains('पिसाब');
        } else if (target == 'problems passing stool' || target == 'stool') {
          return anamnesis.contains('stool') || anamnesis.contains('bowel') || anamnesis.contains('constipation') || anamnesis.contains('दिसा');
        } else if (target == 'pain') {
          return anamnesis.contains('pain') || anamnesis.contains('दुखाई') || anamnesis.contains('दुख्ने') || anamnesis.contains('तल्लो पेट');
        } else if (target == 'menstrual problem' || target == 'menstrual' || target == 'menstrual_disorder') {
          return anamnesis.contains('menstrual') || anamnesis.contains('महिनावारी') || anamnesis.contains('bleeding') || anamnesis.contains('menstrual_disorder');
        } else if (target == 'infertility' || target == 'infertility_screening') {
          return anamnesis.contains('infertility') || anamnesis.contains('बाँझोपन') || anamnesis.contains('निःसन्तान') || anamnesis.contains('infertility_screening');
        } else if (target == 'checkup' || target == 'routine_checkup') {
          return anamnesis.contains('checkup') || anamnesis.contains('routine') || anamnesis.contains('जाँच') || anamnesis.contains('routine_checkup');
        } else if (target == 'gynaecological_oncology' || target == 'oncology' || target == 'cancer') {
          return anamnesis.contains('cancer') || anamnesis.contains('oncology') || anamnesis.contains('क्यान्सर') || anamnesis.contains('gynaecological_oncology');
        } else {
          return anamnesis.contains(target);
        }
      }).toList();

      final matchingPatientKeys = <String>{
        for (final p in matchingPatients) ...[
          p.patientId.trim().toLowerCase(),
          if (p.id.trim().isNotEmpty) p.id.trim().toLowerCase(),
        ]
      };
      patients = matchingPatients;
      visits = visits.where((v) => visitMatchesPatientKeys(v, matchingPatientKeys)).toList();
    }

    // Apply Level of Treatment Filter if requested (Council level vs Full check up vs None)
    if (treatmentLevelFilter != null && treatmentLevelFilter.trim().isNotEmpty && treatmentLevelFilter != 'all') {
      final target = treatmentLevelFilter.trim().toLowerCase();

      patients = patients.where((p) {
        final v = findLatestVisitForPatient(p, visits);
        final level = (v?.treatmentLevel?.trim().isNotEmpty == true)
            ? v!.treatmentLevel!.trim().toLowerCase()
            : (p.treatmentLevel?.trim().toLowerCase() ?? '');
        if (target == 'counseling' || target == 'council_level') {
          return level == 'counseling' || level == 'council_level';
        } else if (target == 'gyno_checkup' || target == 'full_check_up') {
          return level == 'gyno_checkup' || level == 'full_check_up';
        } else if (target == 'none' || target == 'unassigned') {
          return level.isEmpty;
        }
        return level == target;
      }).toList();

      final matchingPatientKeys = <String>{
        for (final p in patients) ...[
          p.patientId.trim().toLowerCase(),
          if (p.id.trim().isNotEmpty) p.id.trim().toLowerCase(),
        ]
      };
      visits = visits.where((v) => visitMatchesPatientKeys(v, matchingPatientKeys)).toList();
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
    String organizationName = AppConstants.defaultOrganizationName,
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
    final result = await FileDownloadHelper.saveAndDownloadFile(
      bytes: bytes,
      filename: filename,
      targetDirectoryPath: targetDirectoryPath,
    );
    return result.filePath ?? result.displayLocation;
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
