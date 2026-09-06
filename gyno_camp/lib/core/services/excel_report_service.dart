import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import '../../models/camp_report_summary_model.dart';
import '../../models/clinical_visit_model.dart';

class ExcelReportService {
  List<int> generateCampSummaryExcel(CampReportSummaryModel summary) {
    final excel = Excel.createExcel();
    final dateFormatter = DateFormat('yyyy-MM-dd');
    final timeFormatter = DateFormat('yyyy-MM-dd HH:mm');

    // 1. Sheet: Camp_Summary
    final summarySheet = excel['Camp_Summary'];
    summarySheet.appendRow([
      TextCellValue('GYNOCAMP HEALTH CLINICAL SUMMARY REPORT'),
    ]);
    summarySheet.appendRow([
      TextCellValue('Camp Name:'),
      TextCellValue(summary.campName),
      TextCellValue('Camp Code:'),
      TextCellValue(summary.campCode),
    ]);
    summarySheet.appendRow([
      TextCellValue('Venue:'),
      TextCellValue(summary.venue),
      TextCellValue('District:'),
      TextCellValue(summary.district),
      TextCellValue('Municipality:'),
      TextCellValue(summary.municipality),
    ]);
    summarySheet.appendRow([
      TextCellValue('Start Date:'),
      TextCellValue(dateFormatter.format(summary.startDate)),
      TextCellValue('End Date:'),
      TextCellValue(dateFormatter.format(summary.endDate)),
      TextCellValue('Generated At:'),
      TextCellValue(timeFormatter.format(summary.generatedAt)),
    ]);
    summarySheet.appendRow([TextCellValue('')]);

    // KPI Summary
    summarySheet.appendRow([TextCellValue('KEY PERFORMANCE INDICATORS (KPI)')]);
    summarySheet.appendRow([
      TextCellValue('Metric'),
      TextCellValue('Value'),
      TextCellValue('Unit / Context'),
    ]);
    summarySheet.appendRow([
      TextCellValue('Total Registered Patients'),
      IntCellValue(summary.totalPatientsRegistered),
      TextCellValue('Patients'),
    ]);
    summarySheet.appendRow([
      TextCellValue('Total Clinical Examinations'),
      IntCellValue(summary.totalVisitsRecorded),
      TextCellValue('Yellow Forms Completed'),
    ]);
    summarySheet.appendRow([
      TextCellValue('Clinically Significant Prolapse (POP Stage >= 2)'),
      IntCellValue(summary.significantPopCount),
      TextCellValue('${summary.significantPopPercentage}% of examined'),
    ]);
    summarySheet.appendRow([
      TextCellValue('Total Surgical Referrals'),
      IntCellValue(summary.totalSurgicalReferrals),
      TextCellValue('Referred for specialized surgery'),
    ]);
    summarySheet.appendRow([
      TextCellValue('Total Pessaries Fitted'),
      IntCellValue(summary.totalPessariesInserted),
      TextCellValue('Fitted on-site'),
    ]);
    summarySheet.appendRow([
      TextCellValue('Pelvic Floor Exercises Counseled'),
      IntCellValue(summary.pelvicFloorCounselingCount),
      TextCellValue('Patients instructed'),
    ]);
    summarySheet.appendRow([TextCellValue('')]);

    // POP Staging Matrix
    summarySheet.appendRow([TextCellValue('PELVIC ORGAN PROLAPSE (POP) STAGING MATRIX')]);
    summarySheet.appendRow([
      TextCellValue('Compartment / Anatomical Site'),
      TextCellValue('Stage 0'),
      TextCellValue('Stage 1'),
      TextCellValue('Stage 2'),
      TextCellValue('Stage 3'),
      TextCellValue('Stage 4'),
    ]);
    summarySheet.appendRow([
      TextCellValue('Anterior Compartment (Cystocele)'),
      IntCellValue(summary.anteriorStages[0] ?? 0),
      IntCellValue(summary.anteriorStages[1] ?? 0),
      IntCellValue(summary.anteriorStages[2] ?? 0),
      IntCellValue(summary.anteriorStages[3] ?? 0),
      TextCellValue('N/A'),
    ]);
    summarySheet.appendRow([
      TextCellValue('Middle Compartment (Uterine/Apex Prolapse)'),
      IntCellValue(summary.middleStages[0] ?? 0),
      IntCellValue(summary.middleStages[1] ?? 0),
      IntCellValue(summary.middleStages[2] ?? 0),
      IntCellValue(summary.middleStages[3] ?? 0),
      IntCellValue(summary.middleStages[4] ?? 0),
    ]);
    summarySheet.appendRow([
      TextCellValue('Posterior Compartment (Rectocele)'),
      IntCellValue(summary.posteriorStages[0] ?? 0),
      IntCellValue(summary.posteriorStages[1] ?? 0),
      IntCellValue(summary.posteriorStages[2] ?? 0),
      IntCellValue(summary.posteriorStages[3] ?? 0),
      TextCellValue('N/A'),
    ]);
    summarySheet.appendRow([
      TextCellValue('Overall Highest POP Stage (Baden-Walker / POP-Q)'),
      IntCellValue(summary.highestPopStages[0] ?? 0),
      IntCellValue(summary.highestPopStages[1] ?? 0),
      IntCellValue(summary.highestPopStages[2] ?? 0),
      IntCellValue(summary.highestPopStages[3] ?? 0),
      IntCellValue(summary.highestPopStages[4] ?? 0),
    ]);
    summarySheet.appendRow([TextCellValue('')]);

    // Demographics
    summarySheet.appendRow([TextCellValue('DEMOGRAPHIC AGE DISTRIBUTION')]);
    summarySheet.appendRow([
      TextCellValue('Age Bucket'),
      TextCellValue('Patient Count'),
      TextCellValue('Percentage'),
    ]);
    for (final e in summary.ageGroups.entries) {
      final pct = summary.totalPatientsRegistered > 0
          ? double.parse(((e.value / summary.totalPatientsRegistered) * 100).toStringAsFixed(1))
          : 0.0;
      summarySheet.appendRow([
        TextCellValue(e.key),
        IntCellValue(e.value),
        DoubleCellValue(pct),
      ]);
    }

    // 2. Sheet: Patient_Register
    final registerSheet = excel['Patient_Register'];
    registerSheet.appendRow([
      TextCellValue('Patient ID'),
      TextCellValue('First Name'),
      TextCellValue('Surname'),
      TextCellValue('Age'),
      TextCellValue('Mobile Phone'),
      TextCellValue('Ward'),
      TextCellValue('Marital Status'),
      TextCellValue('Relative Name'),
      TextCellValue('Highest POP Stage'),
      TextCellValue('Diagnoses List'),
      TextCellValue('Prescribed Medications'),
      TextCellValue('Pessary Inserted'),
      TextCellValue('Surgical Referral'),
      TextCellValue('Follow-up Destination'),
      TextCellValue('Intake Date'),
    ]);

    // Build visit lookup by patientId
    final visitByPatientId = <String, ClinicalVisitModel>{};
    for (final v in summary.visits) {
      visitByPatientId[v.patientId] = v;
    }

    for (final p in summary.patients) {
      final v = visitByPatientId[p.patientId];
      registerSheet.appendRow([
        TextCellValue(p.patientId),
        TextCellValue(p.firstName),
        TextCellValue(p.surname),
        IntCellValue(p.age),
        TextCellValue(p.mobile),
        TextCellValue(p.ward),
        TextCellValue(p.maritalStatus),
        TextCellValue(p.spouseOrFatherName ?? ''),
        IntCellValue(v?.highestPopStage ?? 0),
        TextCellValue(v?.diagnoses.join(', ') ?? 'None'),
        TextCellValue(v?.medications.join(', ') ?? 'None'),
        TextCellValue(v?.pessaryType ?? 'None'),
        TextCellValue(v?.surgicalReferral ?? 'None'),
        TextCellValue(v?.followUpDestination ?? 'None'),
        TextCellValue(dateFormatter.format(p.intakeDate)),
      ]);
    }

    // 3. Sheet: Pathology_Prescriptions
    final pathologySheet = excel['Pathology_Prescriptions'];
    pathologySheet.appendRow([
      TextCellValue('GYNECOLOGICAL DIAGNOSES & PATHOLOGY FREQUENCY'),
    ]);
    pathologySheet.appendRow([
      TextCellValue('Condition / Diagnosis'),
      TextCellValue('Case Count'),
      TextCellValue('Prevalence Rate (%)'),
    ]);
    for (final e in summary.diagnosisCounts.entries) {
      final pct = summary.totalVisitsRecorded > 0
          ? double.parse(((e.value / summary.totalVisitsRecorded) * 100).toStringAsFixed(1))
          : 0.0;
      pathologySheet.appendRow([
        TextCellValue(e.key),
        IntCellValue(e.value),
        DoubleCellValue(pct),
      ]);
    }
    pathologySheet.appendRow([TextCellValue('')]);

    pathologySheet.appendRow([
      TextCellValue('MEDICATION DISPENSING & PHARMACY INVENTORY'),
    ]);
    pathologySheet.appendRow([
      TextCellValue('Medication Name'),
      TextCellValue('Prescriptions Dispensed'),
    ]);
    for (final e in summary.medicationDispensedCounts.entries) {
      pathologySheet.appendRow([
        TextCellValue(e.key),
        IntCellValue(e.value),
      ]);
    }
    pathologySheet.appendRow([TextCellValue('')]);

    pathologySheet.appendRow([
      TextCellValue('SURGICAL REFERRAL DESTINATIONS'),
    ]);
    pathologySheet.appendRow([
      TextCellValue('Hospital / Destination'),
      TextCellValue('Referral Count'),
    ]);
    for (final e in summary.surgicalReferralCounts.entries) {
      pathologySheet.appendRow([
        TextCellValue(e.key),
        IntCellValue(e.value),
      ]);
    }

    // Delete default Sheet1 if exists
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final bytes = excel.encode();
    return bytes ?? <int>[];
  }
}
