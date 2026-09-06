import 'camp_model.dart';
import 'clinical_visit_model.dart';
import 'patient_model.dart';

class CampReportSummaryModel {
  final String campId;
  final String campCode;
  final String campName;
  final String district;
  final String municipality;
  final String venue;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime generatedAt;
  final String generatedBy;

  // General Counts
  final int totalPatientsRegistered;
  final int totalVisitsRecorded;

  // Demographics
  final Map<String, int> ageGroups; // '<20', '20-35', '36-50', '51-65', '>65'
  final Map<String, int> maritalStatusCounts; // 'married', 'widow', 'unmarried', 'divorced'
  final Map<String, int> wardCounts; // '01', '02', etc.

  // POP Staging (Pelvic Organ Prolapse)
  final Map<int, int> anteriorStages; // 0..3
  final Map<int, int> middleStages; // 0..4
  final Map<int, int> posteriorStages; // 0..3
  final Map<int, int> highestPopStages; // 0..4
  final int significantPopCount; // Highest POP >= 2
  final double significantPopPercentage;

  // Clinical Diagnoses
  final Map<String, int> diagnosisCounts; // Top diagnoses and frequencies

  // Lab & Vitals Alerts
  final int hypertensionCount;
  final int hyperglycemiaCount;
  final int urinePositiveCount;
  final int pregnancyPositiveCount;

  // Interventions & Referrals
  final Map<String, int> pessaryCounts;
  final int totalPessariesInserted;
  final int pelvicFloorCounselingCount;
  final Map<String, int> surgicalReferralCounts; // Hospital destination -> count
  final int totalSurgicalReferrals;
  final Map<String, int> followUpDestinationCounts;

  // Pharmacy & Prescriptions
  final Map<String, int> medicationDispensedCounts; // Medicine name -> count
  final int totalPrescriptionsCount;

  // Individual Patient Records (for register sheet)
  final List<PatientModel> patients;
  final List<ClinicalVisitModel> visits;

  const CampReportSummaryModel({
    required this.campId,
    required this.campCode,
    required this.campName,
    required this.district,
    required this.municipality,
    required this.venue,
    required this.startDate,
    required this.endDate,
    required this.generatedAt,
    required this.generatedBy,
    required this.totalPatientsRegistered,
    required this.totalVisitsRecorded,
    required this.ageGroups,
    required this.maritalStatusCounts,
    required this.wardCounts,
    required this.anteriorStages,
    required this.middleStages,
    required this.posteriorStages,
    required this.highestPopStages,
    required this.significantPopCount,
    required this.significantPopPercentage,
    required this.diagnosisCounts,
    required this.hypertensionCount,
    required this.hyperglycemiaCount,
    required this.urinePositiveCount,
    required this.pregnancyPositiveCount,
    required this.pessaryCounts,
    required this.totalPessariesInserted,
    required this.pelvicFloorCounselingCount,
    required this.surgicalReferralCounts,
    required this.totalSurgicalReferrals,
    required this.followUpDestinationCounts,
    required this.medicationDispensedCounts,
    required this.totalPrescriptionsCount,
    this.patients = const [],
    this.visits = const [],
  });

  factory CampReportSummaryModel.empty({
    CampModel? camp,
    String generatedBy = 'Data Analyst',
  }) {
    final now = DateTime.now();
    return CampReportSummaryModel(
      campId: camp?.id ?? 'all',
      campCode: camp?.campCode ?? 'ALL',
      campName: camp?.name ?? 'All Camp Records',
      district: camp?.district ?? 'Nepal',
      municipality: camp?.municipality ?? 'Central Region',
      venue: camp?.venue ?? 'Health Facilities',
      startDate: camp?.startDate ?? now,
      endDate: camp?.endDate ?? now,
      generatedAt: now,
      generatedBy: generatedBy,
      totalPatientsRegistered: 0,
      totalVisitsRecorded: 0,
      ageGroups: {'<20': 0, '20-35': 0, '36-50': 0, '51-65': 0, '>65': 0},
      maritalStatusCounts: {},
      wardCounts: {},
      anteriorStages: {0: 0, 1: 0, 2: 0, 3: 0},
      middleStages: {0: 0, 1: 0, 2: 0, 3: 0, 4: 0},
      posteriorStages: {0: 0, 1: 0, 2: 0, 3: 0},
      highestPopStages: {0: 0, 1: 0, 2: 0, 3: 0, 4: 0},
      significantPopCount: 0,
      significantPopPercentage: 0.0,
      diagnosisCounts: {},
      hypertensionCount: 0,
      hyperglycemiaCount: 0,
      urinePositiveCount: 0,
      pregnancyPositiveCount: 0,
      pessaryCounts: {},
      totalPessariesInserted: 0,
      pelvicFloorCounselingCount: 0,
      surgicalReferralCounts: {},
      totalSurgicalReferrals: 0,
      followUpDestinationCounts: {},
      medicationDispensedCounts: {},
      totalPrescriptionsCount: 0,
      patients: const [],
      visits: const [],
    );
  }
}
