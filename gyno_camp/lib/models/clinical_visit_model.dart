import 'dart:convert';
import '../core/constants/clinical_constants.dart';

class ClinicalVisitModel {
  final String id;
  final String patientId; // References PatientModel.patientId
  final String campId;
  final DateTime visitDate;

  // Obstetric History (Anamnesis Top)
  final int? deliveries; // Parity
  final int? livingChildren;
  final int? abortions;

  // 9 Structured Complaints (Stored as structured JSON map)
  // Each entry has: {duration: '<1month', details: '...', remarks: '...'}
  final Map<String, dynamic> anamnesisComplaints;

  // Physical Examination (Page 2 Top)
  final bool uterusInside;
  final String? vulvaRemarks;
  final String? vaginaRemarks;
  final String? cervixRemarks;
  final String? uterusRemarks;
  final String pelvicFloorTone; // 'normal', 'weak', 'hypertonic'

  // POP Staging (Pelvic Organ Prolapse)
  final int popAnteriorStage; // 0 - 3
  final int popMiddleStage; // 0 - 4
  final int popPosteriorStage; // 0 - 3
  final int highestPopStage; // Auto-computed 0 - 4

  // Lab Tests & Vitals (Page 2 Middle)
  final String? urineTest; // 'normal', 'pos'
  final String? pregnancyTest; // 'neg', 'pos'
  final int? systolicBp;
  final int? diastolicBp;
  final int? pulse;
  final int? spo2;
  final int? glucose;
  final String? ecgNotes;

  // Diagnoses & Treatment (Page 2 Middle & Bottom)
  final List<String> diagnoses;
  final List<String> counseling;
  final String? pessaryType; // 'ring', 'ring with support', 'ring with knob'
  final String? pessarySize;
  final String? surgicalReferral; // 'Scheer Memorial', 'Model Hosp', 'loc government'
  final List<String> medications;
  final String? customMedication;

  // Outtake & Follow-up (Page 2 Bottom)
  final bool followUpNeeded;
  final String? followUpDestination; // 'Health Post', 'GynaeSupport Nurse'
  final String? outtakeNotes;

  // Metadata
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String createdByUserId;
  final String tenantId;
  final bool isSynced;

  const ClinicalVisitModel({
    required this.id,
    required this.patientId,
    required this.campId,
    required this.visitDate,
    this.deliveries,
    this.livingChildren,
    this.abortions,
    this.anamnesisComplaints = const {},
    this.uterusInside = true,
    this.vulvaRemarks,
    this.vaginaRemarks,
    this.cervixRemarks,
    this.uterusRemarks,
    this.pelvicFloorTone = ClinicalConstants.pelvicFloorNormal,
    this.popAnteriorStage = 0,
    this.popMiddleStage = 0,
    this.popPosteriorStage = 0,
    this.highestPopStage = 0,
    this.urineTest,
    this.pregnancyTest,
    this.systolicBp,
    this.diastolicBp,
    this.pulse,
    this.spo2,
    this.glucose,
    this.ecgNotes,
    this.diagnoses = const [],
    this.counseling = const [],
    this.pessaryType,
    this.pessarySize,
    this.surgicalReferral,
    this.medications = const [],
    this.customMedication,
    this.followUpNeeded = false,
    this.followUpDestination,
    this.outtakeNotes,
    required this.createdAt,
    this.updatedAt,
    required this.createdByUserId,
    this.tenantId = 'tenant_bir_hospital',
    this.isSynced = false,
  });

  /// Automatically computes the Highest POP Stage from anterior, middle, and posterior
  static int computeHighestPopStage(int anterior, int middle, int posterior) {
    int highest = anterior;
    if (middle > highest) highest = middle;
    if (posterior > highest) highest = posterior;
    if (highest > ClinicalConstants.maxStageHighest) highest = ClinicalConstants.maxStageHighest;
    return highest;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'patient_id': patientId,
      'camp_id': campId,
      'visit_date': visitDate.toIso8601String(),
      'deliveries': deliveries,
      'living_children': livingChildren,
      'abortions': abortions,
      'anamnesis_json': jsonEncode(anamnesisComplaints),
      'uterus_inside': uterusInside ? 1 : 0,
      'vulva_remarks': vulvaRemarks,
      'vagina_remarks': vaginaRemarks,
      'cervix_remarks': cervixRemarks,
      'uterus_remarks': uterusRemarks,
      'pelvic_floor_tone': pelvicFloorTone,
      'pop_anterior_stage': popAnteriorStage,
      'pop_middle_stage': popMiddleStage,
      'pop_posterior_stage': popPosteriorStage,
      'highest_pop_stage': highestPopStage,
      'urine_test': urineTest,
      'pregnancy_test': pregnancyTest,
      'systolic_bp': systolicBp,
      'diastolic_bp': diastolicBp,
      'pulse': pulse,
      'spo2': spo2,
      'glucose': glucose,
      'ecg_notes': ecgNotes,
      'diagnoses': diagnoses.join(','),
      'counseling': counseling.join(','),
      'pessary_type': pessaryType,
      'pessary_size': pessarySize,
      'surgical_referral': surgicalReferral,
      'medications': medications.join(','),
      'custom_medication': customMedication,
      'follow_up_needed': followUpNeeded ? 1 : 0,
      'follow_up_destination': followUpDestination,
      'outtake_notes': outtakeNotes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'created_by_user_id': createdByUserId,
      'tenant_id': tenantId,
      'is_synced': isSynced ? 1 : 0,
    };
  }

  factory ClinicalVisitModel.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> complaints = {};
    if (map['anamnesis_json'] != null && (map['anamnesis_json'] as String).isNotEmpty) {
      try {
        complaints = jsonDecode(map['anamnesis_json'] as String) as Map<String, dynamic>;
      } catch (_) {}
    }

    return ClinicalVisitModel(
      id: map['id'] as String,
      patientId: map['patient_id'] as String,
      campId: map['camp_id'] as String,
      visitDate: DateTime.tryParse(map['visit_date'] as String? ?? '') ?? DateTime.now(),
      deliveries: map['deliveries'] as int?,
      livingChildren: map['living_children'] as int?,
      abortions: map['abortions'] as int?,
      anamnesisComplaints: complaints,
      uterusInside: (map['uterus_inside'] is int)
          ? (map['uterus_inside'] as int) == 1
          : (map['uterus_inside'] as bool? ?? true),
      vulvaRemarks: map['vulva_remarks'] as String?,
      vaginaRemarks: map['vagina_remarks'] as String?,
      cervixRemarks: map['cervix_remarks'] as String?,
      uterusRemarks: map['uterus_remarks'] as String?,
      pelvicFloorTone: map['pelvic_floor_tone'] as String? ?? ClinicalConstants.pelvicFloorNormal,
      popAnteriorStage: map['pop_anterior_stage'] as int? ?? 0,
      popMiddleStage: map['pop_middle_stage'] as int? ?? 0,
      popPosteriorStage: map['pop_posterior_stage'] as int? ?? 0,
      highestPopStage: map['highest_pop_stage'] as int? ?? 0,
      urineTest: map['urine_test'] as String?,
      pregnancyTest: map['pregnancy_test'] as String?,
      systolicBp: map['systolic_bp'] as int?,
      diastolicBp: map['diastolic_bp'] as int?,
      pulse: map['pulse'] as int?,
      spo2: map['spo2'] as int?,
      glucose: map['glucose'] as int?,
      ecgNotes: map['ecg_notes'] as String?,
      diagnoses: map['diagnoses'] != null && (map['diagnoses'] as String).isNotEmpty
          ? (map['diagnoses'] as String).split(',')
          : [],
      counseling: map['counseling'] != null && (map['counseling'] as String).isNotEmpty
          ? (map['counseling'] as String).split(',')
          : [],
      pessaryType: map['pessary_type'] as String?,
      pessarySize: map['pessary_size'] as String?,
      surgicalReferral: map['surgical_referral'] as String?,
      medications: map['medications'] != null && (map['medications'] as String).isNotEmpty
          ? (map['medications'] as String).split(',')
          : [],
      customMedication: map['custom_medication'] as String?,
      followUpNeeded: (map['follow_up_needed'] is int)
          ? (map['follow_up_needed'] as int) == 1
          : (map['follow_up_needed'] as bool? ?? false),
      followUpDestination: map['follow_up_destination'] as String?,
      outtakeNotes: map['outtake_notes'] as String?,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: map['updated_at'] != null ? DateTime.tryParse(map['updated_at'] as String) : null,
      createdByUserId: map['created_by_user_id'] as String? ?? '',
      tenantId: map['tenant_id'] as String? ?? 'tenant_bir_hospital',
      isSynced: (map['is_synced'] is int)
          ? (map['is_synced'] as int) == 1
          : (map['is_synced'] as bool? ?? false),
    );
  }
}
