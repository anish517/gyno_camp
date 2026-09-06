import '../../models/camp_model.dart';
import '../../models/camp_report_summary_model.dart';
import '../../models/clinical_visit_model.dart';
import '../../models/patient_model.dart';

class ReportAggregationService {
  CampReportSummaryModel aggregate({
    CampModel? camp,
    required List<PatientModel> patients,
    required List<ClinicalVisitModel> visits,
    String generatedBy = 'Data Analyst',
  }) {
    final now = DateTime.now();

    // 1. Demographics
    final ageGroups = {'<20': 0, '20-35': 0, '36-50': 0, '51-65': 0, '>65': 0};
    final maritalStatusCounts = <String, int>{};
    final wardCounts = <String, int>{};

    for (final p in patients) {
      // Age group
      if (p.age < 20) {
        ageGroups['<20'] = (ageGroups['<20'] ?? 0) + 1;
      } else if (p.age <= 35) {
        ageGroups['20-35'] = (ageGroups['20-35'] ?? 0) + 1;
      } else if (p.age <= 50) {
        ageGroups['36-50'] = (ageGroups['36-50'] ?? 0) + 1;
      } else if (p.age <= 65) {
        ageGroups['51-65'] = (ageGroups['51-65'] ?? 0) + 1;
      } else {
        ageGroups['>65'] = (ageGroups['>65'] ?? 0) + 1;
      }

      // Marital status
      final mStatus = p.maritalStatus.trim().toLowerCase();
      final cleanMStatus = mStatus.isEmpty ? 'unspecified' : mStatus;
      maritalStatusCounts[cleanMStatus] = (maritalStatusCounts[cleanMStatus] ?? 0) + 1;

      // Ward
      final ward = p.ward.trim();
      if (ward.isNotEmpty) {
        wardCounts[ward] = (wardCounts[ward] ?? 0) + 1;
      }
    }

    // 2. POP Staging & Clinical Visits
    final anteriorStages = {0: 0, 1: 0, 2: 0, 3: 0};
    final middleStages = {0: 0, 1: 0, 2: 0, 3: 0, 4: 0};
    final posteriorStages = {0: 0, 1: 0, 2: 0, 3: 0};
    final highestPopStages = {0: 0, 1: 0, 2: 0, 3: 0, 4: 0};
    int significantPopCount = 0;

    final diagnosisCounts = <String, int>{};
    int hypertensionCount = 0;
    int hyperglycemiaCount = 0;
    int urinePositiveCount = 0;
    int pregnancyPositiveCount = 0;

    final pessaryCounts = <String, int>{};
    int totalPessaries = 0;
    int pelvicCounseling = 0;
    final surgicalReferrals = <String, int>{};
    final followUpDestinations = <String, int>{};
    final medicationDispensed = <String, int>{};
    int totalPrescriptions = 0;

    for (final v in visits) {
      // Anterior
      final ant = v.popAnteriorStage.clamp(0, 3);
      anteriorStages[ant] = (anteriorStages[ant] ?? 0) + 1;

      // Middle
      final mid = v.popMiddleStage.clamp(0, 4);
      middleStages[mid] = (middleStages[mid] ?? 0) + 1;

      // Posterior
      final pos = v.popPosteriorStage.clamp(0, 3);
      posteriorStages[pos] = (posteriorStages[pos] ?? 0) + 1;

      // Highest
      final highest = v.highestPopStage.clamp(0, 4);
      highestPopStages[highest] = (highestPopStages[highest] ?? 0) + 1;

      if (highest >= 2) {
        significantPopCount++;
      }

      // Diagnoses
      for (final d in v.diagnoses) {
        final cleanD = d.trim();
        if (cleanD.isNotEmpty) {
          diagnosisCounts[cleanD] = (diagnosisCounts[cleanD] ?? 0) + 1;
        }
      }

      // Vitals & Lab Alerts
      final isHyperBp = (v.systolicBp != null && v.systolicBp! >= 140) ||
          (v.diastolicBp != null && v.diastolicBp! >= 90);
      if (isHyperBp) hypertensionCount++;

      if (v.glucose != null && v.glucose! >= 140) hyperglycemiaCount++;
      if (v.urineTest?.trim().toLowerCase() == 'pos') urinePositiveCount++;
      if (v.pregnancyTest?.trim().toLowerCase() == 'pos') pregnancyPositiveCount++;

      // Pessaries
      if (v.pessaryType != null && v.pessaryType!.trim().isNotEmpty) {
        final label = v.pessarySize != null && v.pessarySize!.trim().isNotEmpty
            ? '${v.pessaryType!.trim()} (${v.pessarySize!.trim()})'
            : v.pessaryType!.trim();
        pessaryCounts[label] = (pessaryCounts[label] ?? 0) + 1;
        totalPessaries++;
      }

      // Counseling
      if (v.counseling.isNotEmpty) {
        pelvicCounseling++;
      }

      // Surgical referrals
      if (v.surgicalReferral != null && v.surgicalReferral!.trim().isNotEmpty) {
        final hosp = v.surgicalReferral!.trim();
        surgicalReferrals[hosp] = (surgicalReferrals[hosp] ?? 0) + 1;
      }

      // Follow-up
      if (v.followUpDestination != null && v.followUpDestination!.trim().isNotEmpty) {
        final dest = v.followUpDestination!.trim();
        followUpDestinations[dest] = (followUpDestinations[dest] ?? 0) + 1;
      }

      // Medications
      for (final med in v.medications) {
        final cleanMed = med.trim();
        if (cleanMed.isNotEmpty) {
          medicationDispensed[cleanMed] = (medicationDispensed[cleanMed] ?? 0) + 1;
          totalPrescriptions++;
        }
      }
      if (v.customMedication != null && v.customMedication!.trim().isNotEmpty) {
        final custom = v.customMedication!.trim();
        medicationDispensed[custom] = (medicationDispensed[custom] ?? 0) + 1;
        totalPrescriptions++;
      }
    }

    final totalVisits = visits.length;
    final significantPopPct = totalVisits > 0
        ? double.parse(((significantPopCount / totalVisits) * 100).toStringAsFixed(1))
        : 0.0;

    // Sort diagnoses by frequency descending
    final sortedDiagnoses = Map.fromEntries(
      diagnosisCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );

    // Sort medications by frequency descending
    final sortedMeds = Map.fromEntries(
      medicationDispensed.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );

    int totalSurgical = 0;
    for (final count in surgicalReferrals.values) {
      totalSurgical += count;
    }

    return CampReportSummaryModel(
      campId: camp?.id ?? 'all',
      campCode: camp?.campCode ?? 'ALL',
      campName: camp?.name ?? 'Comprehensive Health Camp Summary',
      district: camp?.district ?? 'Multiple Districts',
      municipality: camp?.municipality ?? 'Rural Health Clinics',
      venue: camp?.venue ?? 'Various Camp Centers',
      startDate: camp?.startDate ?? (patients.isNotEmpty ? patients.first.intakeDate : now),
      endDate: camp?.endDate ?? now,
      generatedAt: now,
      generatedBy: generatedBy,
      totalPatientsRegistered: patients.length,
      totalVisitsRecorded: visits.length,
      ageGroups: ageGroups,
      maritalStatusCounts: maritalStatusCounts,
      wardCounts: wardCounts,
      anteriorStages: anteriorStages,
      middleStages: middleStages,
      posteriorStages: posteriorStages,
      highestPopStages: highestPopStages,
      significantPopCount: significantPopCount,
      significantPopPercentage: significantPopPct,
      diagnosisCounts: sortedDiagnoses,
      hypertensionCount: hypertensionCount,
      hyperglycemiaCount: hyperglycemiaCount,
      urinePositiveCount: urinePositiveCount,
      pregnancyPositiveCount: pregnancyPositiveCount,
      pessaryCounts: pessaryCounts,
      totalPessariesInserted: totalPessaries,
      pelvicFloorCounselingCount: pelvicCounseling,
      surgicalReferralCounts: surgicalReferrals,
      totalSurgicalReferrals: totalSurgical,
      followUpDestinationCounts: followUpDestinations,
      medicationDispensedCounts: sortedMeds,
      totalPrescriptionsCount: totalPrescriptions,
      patients: patients,
      visits: visits,
    );
  }
}
