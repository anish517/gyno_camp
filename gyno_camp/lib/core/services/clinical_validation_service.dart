import '../constants/clinical_constants.dart';

enum ValidationSeverity {
  normal,
  warning,
  error;

  bool get isNormal => this == ValidationSeverity.normal;
  bool get isWarning => this == ValidationSeverity.warning;
  bool get isError => this == ValidationSeverity.error;
}

class ValidationResult {
  final ValidationSeverity severity;
  final String? messageEn;
  final String? messageNe;

  const ValidationResult({
    required this.severity,
    this.messageEn,
    this.messageNe,
  });

  const ValidationResult.normal()
      : severity = ValidationSeverity.normal,
        messageEn = null,
        messageNe = null;

  bool get isValid => severity != ValidationSeverity.error;
  bool get hasWarning => severity == ValidationSeverity.warning;
  bool get isNormal => severity.isNormal;
  bool get isWarning => severity.isWarning;
  bool get isError => severity.isError;
}

class ClinicalValidationService {
  /// Validates Systolic Blood Pressure (mmHg)
  static ValidationResult validateSystolicBp(int? systolic) {
    if (systolic == null) return const ValidationResult.normal();

    if (systolic < ClinicalConstants.minSystolicError || systolic > ClinicalConstants.maxSystolicError) {
      return ValidationResult(
        severity: ValidationSeverity.error,
        messageEn: 'Systolic BP ($systolic) is physiologically improbable. Check for typo.',
        messageNe: 'सिस्टोलिक रक्तचाप ($systolic) सम्भव देखिँदैन। कृपया पुनः जाँच्नुहोस्।',
      );
    }

    if (systolic < ClinicalConstants.minSystolicWarning) {
      return ValidationResult(
        severity: ValidationSeverity.warning,
        messageEn: 'Low Systolic BP ($systolic mmHg) - Hypotension warning.',
        messageNe: 'कम सिस्टोलिक रक्तचाप ($systolic mmHg) - न्यून रक्तचाप।',
      );
    }

    if (systolic > ClinicalConstants.maxSystolicWarning) {
      return ValidationResult(
        severity: ValidationSeverity.warning,
        messageEn: 'High Systolic BP ($systolic mmHg) - Stage 2 Hypertension warning.',
        messageNe: 'उच्च सिस्टोलिक रक्तचाप ($systolic mmHg) - उच्च रक्तचाप।',
      );
    }

    return const ValidationResult.normal();
  }

  /// Validates Diastolic Blood Pressure (mmHg)
  static ValidationResult validateDiastolicBp(int? diastolic, {int? systolic}) {
    if (diastolic == null) return const ValidationResult.normal();

    if (diastolic < ClinicalConstants.minDiastolicError || diastolic > ClinicalConstants.maxDiastolicError) {
      return ValidationResult(
        severity: ValidationSeverity.error,
        messageEn: 'Diastolic BP ($diastolic) is out of plausible medical range.',
        messageNe: 'डायस्टोलिक रक्तचाप ($diastolic) अस्वाभाविक छ।',
      );
    }

    if (systolic != null && diastolic >= systolic) {
      return const ValidationResult(
        severity: ValidationSeverity.error,
        messageEn: 'Diastolic BP cannot be equal to or higher than Systolic BP.',
        messageNe: 'डायस्टोलिक रक्तचाप सिस्टोलिक भन्दा बढी वा बराबर हुन सक्दैन।',
      );
    }

    if (diastolic < ClinicalConstants.minDiastolicWarning) {
      return ValidationResult(
        severity: ValidationSeverity.warning,
        messageEn: 'Low Diastolic BP ($diastolic mmHg).',
        messageNe: 'कम डायस्टोलिक रक्तचाप ($diastolic mmHg)।',
      );
    }

    if (diastolic > ClinicalConstants.maxDiastolicWarning) {
      return ValidationResult(
        severity: ValidationSeverity.warning,
        messageEn: 'High Diastolic BP ($diastolic mmHg) - Hypertension warning.',
        messageNe: 'उच्च डायस्टोलिक रक्तचाप ($diastolic mmHg)।',
      );
    }

    return const ValidationResult.normal();
  }

  /// Validates Pulse Rate (bpm)
  static ValidationResult validatePulse(int? pulse) {
    if (pulse == null) return const ValidationResult.normal();

    if (pulse < ClinicalConstants.minPulseError || pulse > ClinicalConstants.maxPulseError) {
      return ValidationResult(
        severity: ValidationSeverity.error,
        messageEn: 'Pulse ($pulse bpm) is outside believable limits. Check for entry error.',
        messageNe: 'नाडीको गति ($pulse bpm) अस्वाभाविक छ।',
      );
    }

    if (pulse < ClinicalConstants.minPulseWarning) {
      return ValidationResult(
        severity: ValidationSeverity.warning,
        messageEn: 'Bradycardia warning ($pulse bpm).',
        messageNe: 'नाडीको गति निकै सुस्त ($pulse bpm)।',
      );
    }

    if (pulse > ClinicalConstants.maxPulseWarning) {
      return ValidationResult(
        severity: ValidationSeverity.warning,
        messageEn: 'Tachycardia warning ($pulse bpm).',
        messageNe: 'नाडीको गति निकै तीव्र ($pulse bpm)।',
      );
    }

    return const ValidationResult.normal();
  }

  /// Validates Oxygen Saturation SpO2 (%)
  static ValidationResult validateSpO2(int? spo2) {
    if (spo2 == null) return const ValidationResult.normal();

    if (spo2 < ClinicalConstants.minSpO2Error || spo2 > ClinicalConstants.maxSpO2Error) {
      return ValidationResult(
        severity: ValidationSeverity.error,
        messageEn: 'SpO2 must be between 50% and 100%.',
        messageNe: 'अक्सिजन स्याचुरेसन ५०% देखि १००% बीच हुनुपर्छ।',
      );
    }

    if (spo2 < ClinicalConstants.minSpO2Warning) {
      return ValidationResult(
        severity: ValidationSeverity.warning,
        messageEn: 'Hypoxia warning: Oxygen saturation is low ($spo2%).',
        messageNe: 'अक्सिजनको मात्रा कम छ ($spo2%)।',
      );
    }

    return const ValidationResult.normal();
  }

  /// Validates Random Blood Glucose (mg/dL)
  static ValidationResult validateGlucose(int? glucose) {
    if (glucose == null) return const ValidationResult.normal();

    if (glucose < ClinicalConstants.minGlucoseError || glucose > ClinicalConstants.maxGlucoseError) {
      return ValidationResult(
        severity: ValidationSeverity.error,
        messageEn: 'Blood glucose ($glucose mg/dL) is outside valid testing limits.',
        messageNe: 'ग्लुकोज ($glucose mg/dL) अस्वाभाविक दायरामा छ।',
      );
    }

    if (glucose < ClinicalConstants.minGlucoseWarning) {
      return ValidationResult(
        severity: ValidationSeverity.warning,
        messageEn: 'Hypoglycemia warning: Low blood sugar ($glucose mg/dL).',
        messageNe: 'रगतमा चिनीको मात्रा न्यून ($glucose mg/dL)।',
      );
    }

    if (glucose > ClinicalConstants.maxGlucoseWarning) {
      return ValidationResult(
        severity: ValidationSeverity.warning,
        messageEn: 'Hyperglycemia warning: High blood sugar ($glucose mg/dL).',
        messageNe: 'रगतमा चिनीको मात्रा उच्च ($glucose mg/dL)।',
      );
    }

    return const ValidationResult.normal();
  }

  /// Validates obstetric counts
  static ValidationResult validateObstetricCounts({
    int? deliveries,
    int? livingChildren,
    int? abortions,
  }) {
    if (deliveries != null && livingChildren != null) {
      if (livingChildren > deliveries) {
        return const ValidationResult(
          severity: ValidationSeverity.error,
          messageEn: 'Living children count cannot exceed total deliveries.',
          messageNe: 'जीवित बच्चाको संख्या कुल सुत्केरी संख्या भन्दा बढी हुन सक्दैन।',
        );
      }
    }
    return const ValidationResult.normal();
  }
}
