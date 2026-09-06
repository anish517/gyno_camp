import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/ocr_form_service.dart';

void main() {
  late OcrFormService service;

  setUp(() {
    service = const OcrFormService();
  });

  group('OcrFormService Tests', () {
    test('parseFormText parses Page 1 Demographics and Obstetric Anamnesis accurately', () {
      final result = service.parseFormText(OcrFormService.samplePage1Text, pageNumber: 1);

      expect(result.demographics['firstName'], 'Maya');
      expect(result.demographics['surname'], 'Tamang');
      expect(result.demographics['age'], 44);
      expect(result.demographics['mobile'], '9841987654');
      expect(result.demographics['ward'], '04');
      expect(result.demographics['relativeName'], 'Som Bahadur Tamang');
      expect(result.demographics['relativeType'], 'Husband');
      expect(result.demographics['maritalStatus'], 'married');

      final reasons = result.demographics['reasonsForVisit'] as List<String>;
      expect(reasons, contains('Something hanging out / Prolapse'));
      expect(reasons, contains('Discharge and/or itching'));
      expect(reasons, contains('Abdominal / Back pain'));

      expect(result.obstetrics['deliveries'], 3);
      expect(result.obstetrics['livingChildren'], 3);
      expect(result.obstetrics['abortions'], 0);

      expect(result.getConfidenceTier('mobile'), 'HIGH');
      expect(result.getConfidenceTier('ward'), 'HIGH');
      expect(result.overallConfidence, greaterThanOrEqualTo(0.80));
    });

    test('parseFormText parses Page 2 POP Staging, Vitals and Diagnoses accurately', () {
      final result = service.parseFormText(OcrFormService.samplePage2Text, pageNumber: 2);

      // POP Staging
      expect(result.popStaging['anteriorStage'], 2);
      expect(result.popStaging['middleStage'], 3);
      expect(result.popStaging['posteriorStage'], 1);
      expect(result.popStaging['highestPopStage'], 3);
      expect(result.popStaging['uterusInside'], false);
      expect(result.popStaging['pelvicFloorTone'], 'weak');

      // Vitals
      expect(result.vitals['systolicBp'], 130);
      expect(result.vitals['diastolicBp'], 85);
      expect(result.vitals['pulseRate'], 78);
      expect(result.vitals['spo2'], 98);
      expect(result.vitals['bloodGlucose'], 115);
      expect(result.vitals['urineTest'], 'normal');
      expect(result.vitals['pregnancyTest'], 'neg');

      // Diagnoses
      expect(result.diagnoses, contains('POP'));
      expect(result.diagnoses, contains('candid infection'));
      expect(result.diagnoses, contains('hypertension'));

      // Medications & Referrals
      expect(result.medications, contains('Metronidazole'));
      expect(result.medications, contains('Fluconazole'));
      expect(result.surgicalReferral, 'Scheer Memorial Hospital');
      expect(result.followUpDestination, 'GynaeSupport Nurse');
    });

    test('parseFormText handles sparse or noisy text with sensible clinical defaults', () {
      const noisyText = 'Random paper text 123 456 invalid form sample';
      final result = service.parseFormText(noisyText, pageNumber: 0);

      expect(result.demographics['firstName'], isNotEmpty);
      expect(result.demographics['age'], 35);
      expect(result.vitals['systolicBp'], 120);
      expect(result.vitals['diastolicBp'], 80);
      expect(result.popStaging['highestPopStage'], isNotNull);
      expect(result.fieldConfidences.isNotEmpty, true);
    });
  });
}
