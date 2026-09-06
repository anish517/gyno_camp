import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/clinical_validation_service.dart';

void main() {
  group('ClinicalValidationService Tests', () {
    test('Systolic BP validation handles normal, warning, and error thresholds', () {
      // Normal range
      final normalResult = ClinicalValidationService.validateSystolicBp(120);
      expect(normalResult.isValid, isTrue);
      expect(normalResult.hasWarning, isFalse);
      expect(normalResult.isNormal, isTrue);

      // Warning: Hypotension (< 90)
      final lowWarning = ClinicalValidationService.validateSystolicBp(85);
      expect(lowWarning.isValid, isTrue);
      expect(lowWarning.hasWarning, isTrue);
      expect(lowWarning.isWarning, isTrue);
      expect(lowWarning.messageEn, contains('Hypotension'));

      // Warning: Hypertension (> 160)
      final highWarning = ClinicalValidationService.validateSystolicBp(170);
      expect(highWarning.isValid, isTrue);
      expect(highWarning.hasWarning, isTrue);
      expect(highWarning.messageEn, contains('Hypertension'));

      // Error: Impossible / Typo (< 60 or > 260)
      final tooLow = ClinicalValidationService.validateSystolicBp(40);
      expect(tooLow.isValid, isFalse);
      expect(tooLow.isError, isTrue);

      final tooHigh = ClinicalValidationService.validateSystolicBp(300);
      expect(tooHigh.isValid, isFalse);
      expect(tooHigh.isError, isTrue);
    });

    test('Diastolic BP validation checks thresholds and comparison with systolic', () {
      // Normal
      final normal = ClinicalValidationService.validateDiastolicBp(80, systolic: 120);
      expect(normal.isValid, isTrue);
      expect(normal.isNormal, isTrue);

      // Error: Diastolic >= Systolic
      final inverted = ClinicalValidationService.validateDiastolicBp(120, systolic: 110);
      expect(inverted.isValid, isFalse);
      expect(inverted.isError, isTrue);
      expect(inverted.messageEn, contains('cannot be equal to or higher'));

      // Warning: Low (< 60)
      final low = ClinicalValidationService.validateDiastolicBp(55, systolic: 100);
      expect(low.isWarning, isTrue);

      // Warning: High (> 100)
      final high = ClinicalValidationService.validateDiastolicBp(105, systolic: 145);
      expect(high.isWarning, isTrue);

      // Error: Improbable (< 30 or > 150)
      final err = ClinicalValidationService.validateDiastolicBp(20, systolic: 80);
      expect(err.isError, isTrue);
    });

    test('Pulse validation handles bradycardia, tachycardia, and bounds', () {
      expect(ClinicalValidationService.validatePulse(72).isNormal, isTrue);

      // Bradycardia (< 50)
      final brady = ClinicalValidationService.validatePulse(45);
      expect(brady.isWarning, isTrue);
      expect(brady.messageEn, contains('Bradycardia'));

      // Tachycardia (> 110)
      final tachy = ClinicalValidationService.validatePulse(125);
      expect(tachy.isWarning, isTrue);
      expect(tachy.messageEn, contains('Tachycardia'));

      // Out of bounds (< 30 or > 220)
      expect(ClinicalValidationService.validatePulse(25).isError, isTrue);
      expect(ClinicalValidationService.validatePulse(240).isError, isTrue);
    });

    test('SpO2 validation flags hypoxia and impossible values', () {
      expect(ClinicalValidationService.validateSpO2(98).isNormal, isTrue);

      // Hypoxia warning (< 90%)
      final hypoxia = ClinicalValidationService.validateSpO2(88);
      expect(hypoxia.isWarning, isTrue);
      expect(hypoxia.messageEn, contains('Hypoxia'));

      // Out of bounds (< 50 or > 100)
      expect(ClinicalValidationService.validateSpO2(45).isError, isTrue);
      expect(ClinicalValidationService.validateSpO2(105).isError, isTrue);
    });

    test('Blood glucose validation checks hypoglycemia and hyperglycemia', () {
      expect(ClinicalValidationService.validateGlucose(95).isNormal, isTrue);

      // Hypoglycemia (< 70)
      final hypo = ClinicalValidationService.validateGlucose(60);
      expect(hypo.isWarning, isTrue);
      expect(hypo.messageEn, contains('Hypoglycemia'));

      // Hyperglycemia (> 200)
      final hyper = ClinicalValidationService.validateGlucose(250);
      expect(hyper.isWarning, isTrue);
      expect(hyper.messageEn, contains('Hyperglycemia'));

      // Typo/Error (< 20 or > 600)
      expect(ClinicalValidationService.validateGlucose(15).isError, isTrue);
      expect(ClinicalValidationService.validateGlucose(750).isError, isTrue);
    });

    test('Obstetric count validation flags living children > deliveries', () {
      final valid = ClinicalValidationService.validateObstetricCounts(
        deliveries: 3,
        livingChildren: 3,
      );
      expect(valid.isNormal, isTrue);

      final invalid = ClinicalValidationService.validateObstetricCounts(
        deliveries: 2,
        livingChildren: 3,
      );
      expect(invalid.isError, isTrue);
      expect(invalid.messageEn, contains('Living children count cannot exceed total deliveries'));
    });
  });
}
