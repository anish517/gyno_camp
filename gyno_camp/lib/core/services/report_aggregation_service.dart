import '../../models/camp_model.dart';
import '../../models/camp_report_summary_model.dart';
import '../../models/clinical_visit_model.dart';
import '../../models/patient_model.dart';

class ReportAggregationService {
  static final RegExp _dosageInstructionPattern = RegExp(
    r'^\d*\s*(tab|tabs|tablet|tablets|cap|caps|capsule|capsules|pill|pills|drop|drops|puff|puffs|tsp|tbsp|sachet|amp|ampoule)?\s*(daily|once daily|twice daily|od|bd|bid|tds|tid|qid|hs|sos|prn|stat|po|per day|times a day|a day)$',
    caseSensitive: false,
  );

  static bool isDosageInstruction(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return true;
    return _dosageInstructionPattern.hasMatch(trimmed);
  }

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
    final districtCounts = <String, int>{};

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

      // District
      final district = p.district.trim();
      if (district.isNotEmpty) {
        districtCounts[district] = (districtCounts[district] ?? 0) + 1;
      } else {
        districtCounts['Unspecified'] = (districtCounts['Unspecified'] ?? 0) + 1;
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

    // Map patient UUIDs and lowercase patientIds to canonical patient key so
    // patients with multiple visits (Initial + Follow-Up) are not double-counted
    // in patient-level prevalence distributions.
    final uuidToCanonicalKey = <String, String>{};
    for (final p in patients) {
      final canon = p.patientId.trim().toLowerCase();
      uuidToCanonicalKey[canon] = canon;
      if (p.id.trim().isNotEmpty) {
        uuidToCanonicalKey[p.id.trim().toLowerCase()] = canon;
      }
    }

    final latestVisitPerPatient = <String, ClinicalVisitModel>{};
    for (final v in visits) {
      final rawKey = v.patientId.trim().toLowerCase();
      final canonKey = uuidToCanonicalKey[rawKey] ?? (rawKey.isNotEmpty ? rawKey : v.id);
      final prev = latestVisitPerPatient[canonKey];
      if (prev == null || !v.visitDate.isBefore(prev.visitDate)) {
        latestVisitPerPatient[canonKey] = v;
      }
    }

    final deduplicatedVisits = latestVisitPerPatient.values.toList();

    for (final v in deduplicatedVisits) {
      // Anterior
      if (v.popAnteriorStage != null) {
        final ant = v.popAnteriorStage!.clamp(0, 3);
        anteriorStages[ant] = (anteriorStages[ant] ?? 0) + 1;
      }

      // Middle
      if (v.popMiddleStage != null) {
        final mid = v.popMiddleStage!.clamp(0, 4);
        middleStages[mid] = (middleStages[mid] ?? 0) + 1;
      }

      // Posterior
      if (v.popPosteriorStage != null) {
        final pos = v.popPosteriorStage!.clamp(0, 3);
        posteriorStages[pos] = (posteriorStages[pos] ?? 0) + 1;
      }

      // Highest
      if (v.highestPopStage != null) {
        final highest = v.highestPopStage!.clamp(0, 4);
        highestPopStages[highest] = (highestPopStages[highest] ?? 0) + 1;

        if (highest >= 2) {
          significantPopCount++;
        }
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
        final hasSize = v.pessarySize != null && v.pessarySize!.trim().isNotEmpty;
        final label = hasSize
            ? '${v.pessaryType!.trim()} (${v.formattedPessarySize})'
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

      // Medications (deduplicated so customMedication copied from OCR never double-counts)
      for (final cleanMed in v.uniqueAllMedications) {
        if (!isDosageInstruction(cleanMed)) {
          medicationDispensed[cleanMed] = (medicationDispensed[cleanMed] ?? 0) + 1;
          totalPrescriptions++;
        }
      }
    }

    final totalVisits = deduplicatedVisits.length;
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

    // Level of Treatment Distribution
    int councilLevelCount = 0;
    int fullCheckUpCount = 0;
    int unassignedTreatmentLevelCount = 0;

    for (final p in patients) {
      final v = latestVisitPerPatient[p.patientId.trim().toLowerCase()] ??
          latestVisitPerPatient[p.id.trim().toLowerCase()];
      final level = (v?.treatmentLevel?.trim().isNotEmpty == true)
          ? v!.treatmentLevel!.trim()
          : (p.treatmentLevel?.trim() ?? '');
      if (level == 'counseling' || level == 'council_level') {
        councilLevelCount++;
      } else if (level == 'gyno_checkup' || level == 'full_check_up') {
        fullCheckUpCount++;
      } else {
        unassignedTreatmentLevelCount++;
      }
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
      totalVisitsRecorded: totalVisits,
      ageGroups: ageGroups,
      maritalStatusCounts: maritalStatusCounts,
      wardCounts: wardCounts,
      districtCounts: districtCounts,
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
      councilLevelCount: councilLevelCount,
      fullCheckUpCount: fullCheckUpCount,
      unassignedTreatmentLevelCount: unassignedTreatmentLevelCount,
      patients: patients,
      visits: visits,
    );
  }
}
