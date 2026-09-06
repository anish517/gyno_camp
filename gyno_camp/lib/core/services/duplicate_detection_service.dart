import '../../models/patient_model.dart';
import '../constants/clinical_constants.dart';

enum DuplicateConfidence {
  none,
  medium,
  high;

  bool get isDuplicateFound => this != DuplicateConfidence.none;
}

class DuplicateCheckResult {
  final DuplicateConfidence confidence;
  final PatientModel? matchedPatient;
  final String? matchReasonEn;
  final String? matchReasonNe;

  const DuplicateCheckResult({
    required this.confidence,
    this.matchedPatient,
    this.matchReasonEn,
    this.matchReasonNe,
  });

  const DuplicateCheckResult.none()
      : confidence = DuplicateConfidence.none,
        matchedPatient = null,
        matchReasonEn = null,
        matchReasonNe = null;

  bool get hasDuplicate => confidence.isDuplicateFound;
  bool get isDuplicate => confidence.isDuplicateFound;
  String? get reason => matchReasonEn;
}

class DuplicateDetectionService {
  /// Evaluates new patient input against a list of existing patients
  static DuplicateCheckResult check({
    required List<PatientModel> existingPatients,
    required String firstName,
    required String surname,
    required int age,
    required String mobile,
    required String ward,
    String? spouseOrFatherName,
    String? maritalStatus,
  }) {
    final cleanPhone = mobile.trim();
    final cleanFirst = firstName.trim().toLowerCase();
    final cleanSur = surname.trim().toLowerCase();
    final cleanWard = ward.trim();
    final cleanSpouseOrFather = spouseOrFatherName?.trim().toLowerCase() ?? '';

    for (final existing in existingPatients) {
      // 1. Check exact mobile match
      if (cleanPhone.isNotEmpty && existing.mobile.trim().isNotEmpty && cleanPhone == existing.mobile.trim()) {
        return DuplicateCheckResult(
          confidence: DuplicateConfidence.high,
          matchedPatient: existing,
          matchReasonEn: 'Exact match on mobile number (${existing.mobile}). Patient already registered as ${existing.fullName} (ID: ${existing.patientId}).',
          matchReasonNe: 'मोबाइल नम्बर मिल्यो (${existing.mobile})। बिरामी पहिले नै ${existing.fullName} (ID: ${existing.patientId}) नाममा दर्ता भइसकेको छ।',
        );
      }

      // 2. Check Name + Ward + Age (±1)
      final existingFirst = existing.firstName.trim().toLowerCase();
      final existingSur = existing.surname.trim().toLowerCase();
      final nameMatches = cleanFirst == existingFirst && cleanSur == existingSur;
      final wardMatches = cleanWard.isNotEmpty && existing.ward.trim() == cleanWard;
      final ageClose = (existing.age - age).abs() <= 1;

      if (nameMatches && wardMatches && ageClose) {
        // Evaluate Spouse vs Father depending on marital status and age
        final isUnmarried = (maritalStatus ?? '').trim().toLowerCase() == 'unmarried';
        final isAdult = age >= ClinicalConstants.adultAgeThreshold;
        final relationField = isUnmarried
            ? "Father's/Guardian's name"
            : (isAdult ? "Husband's name" : "Father's name");
        final relationFieldNe = isUnmarried
            ? "बुबा वा संरक्षकको नाम"
            : (isAdult ? "श्रीमानको नाम" : "बुबाको नाम");

        final existingSpouseFather = (existing.spouseOrFatherName ?? '').trim().toLowerCase();

        if (cleanSpouseOrFather.isNotEmpty && existingSpouseFather.isNotEmpty) {
          if (cleanSpouseOrFather == existingSpouseFather) {
            return DuplicateCheckResult(
              confidence: DuplicateConfidence.high,
              matchedPatient: existing,
              matchReasonEn: 'Full match on Name, Ward, Age, and $relationField (${existing.spouseOrFatherName}). Patient ID: ${existing.patientId}.',
              matchReasonNe: 'नाम, वडा, उमेर र $relationFieldNe (${existing.spouseOrFatherName}) सबै मिल्यो। बिरामी ID: ${existing.patientId}।',
            );
          }
        } else {
          return DuplicateCheckResult(
            confidence: DuplicateConfidence.medium,
            matchedPatient: existing,
            matchReasonEn: 'Strong match on Name ($firstName $surname), Ward ($ward), and Age ($age). Please verify if same patient.',
            matchReasonNe: 'नाम ($firstName $surname), वडा ($ward) र उमेर ($age) मिल्दोजुल्दो छ। कृपया बिरामी पहिचान गर्नुहोस्।',
          );
        }
      }
    }

    return const DuplicateCheckResult.none();
  }
}
