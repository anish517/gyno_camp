import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/ocr_form_service.dart';

const String _page1 = """
GYNOCAMP CLINICAL INTAKE FORM (YELLOW FORM)
Patient Name: Kamala Thapa
Age: 38 Years
Relative: Ram Bahadur Thapa (Husband)
Mobile: 9841234567
District: Sindhupalchok
Municipality: Melamchi Rural Municipality
Ward: 05
Marital Status: [X] Married
[X] Something hanging out / Prolapse
[X] Discharge and/or Itching (chilaune)
[X] Abdominal / Back pain (dhaad dukhne)
[X] Menstrual Problem (mahina)
Deliveries: 4
Living Children: 3
Abortions: 1
""";

const String _page2 = """
Anterior Compartment Stage: 2
Middle Compartment Stage: 3
Posterior Compartment Stage: 1
Pelvic Floor Tone: Weak
Blood Pressure: 140/90 mmHg
Pulse Rate: 82 bpm
SpO2: 97%
Blood Glucose: 185 mg/dL
Urine Test: Normal
Pregnancy Test: Neg
[X] POP (Stage 3)
[X] hypertension
[X] diabetes mellitus
[X] Metronidazole 400mg
[X] Fluconazole 150mg
Surgical Referral: Scheer Memorial Hospital
Follow-up: GynaeSupport Nurse
""";

const String _blank = 'The weather today is sunny with mild winds.';

void main() {
  const service = OcrFormService();

  group('Demographics', () {
    late Map<String, dynamic> d;
    setUp(() => d = service.parseFormText(_page1, pageNumber: 1).demographics);

    test('firstName', () => expect(d['firstName'], 'Kamala'));
    test('surname', () => expect(d['surname'], 'Thapa'));
    test('age', () => expect(d['age'], 38));
    test('mobile', () => expect(d['mobile'], '9841234567'));
    test('ward zero-padded', () => expect(d['ward'], '05'));
    test('district not hardcoded Kathmandu', () => expect((d['district'] as String).toLowerCase(), contains('sindhupalchok')));
    test('municipality extracted', () => expect((d['municipality'] as String).toLowerCase(), contains('melamchi')));
    test('marital status', () => expect(d['maritalStatus'], 'married'));
    test('relative name — no bracket', () {
      final n = d['relativeName'] as String?;
      expect(n, isNotNull);
      expect(n, isNot(contains('(')));
    });
    test('relative type from bracket', () => expect(d['relativeType'], 'Husband'));
    test('null firstName on blank (no fake Sita)', () => expect(service.parseFormText(_blank).demographics['firstName'], isNull));
    test('null relativeName on blank (no fake Ram Bahadur)', () => expect(service.parseFormText(_blank).demographics['relativeName'], isNull));
  });

  group('Visit Reasons — exact model keys', () {
    late List<String> r;
    setUp(() => r = List<String>.from(service.parseFormText(_page1, pageNumber: 1).demographics['reasonsForVisit'] as List));

    test('prolapse key', () => expect(r, contains('something hanging out')));
    test('discharge key', () => expect(r, contains('discharge and or itching')));
    test('pain key', () => expect(r, contains('pain')));
    test('menstrual key (was missing before fix)', () => expect(r, contains('menstrual problem')));
    test('no false urine', () => expect(r, isNot(contains('problems passing urine'))));
    test('no false infertility', () => expect(r, isNot(contains('infertility'))));
    test('no false checkup', () => expect(r, isNot(contains('checkup'))));
    test('blank form empty reasons', () => expect(
        List<String>.from(service.parseFormText(_blank).demographics['reasonsForVisit'] as List), isEmpty));
  });

  group('Obstetric History', () {
    late Map<String, dynamic> o;
    setUp(() => o = service.parseFormText(_page1, pageNumber: 1).obstetrics);
    test('deliveries', () => expect(o['deliveries'], 4));
    test('living children', () => expect(o['livingChildren'], 3));
    test('abortions', () => expect(o['abortions'], 1));
    test('living <= deliveries', () => expect(o['livingChildren'] as int, lessThanOrEqualTo(o['deliveries'] as int)));
  });

  group('Vitals', () {
    late Map<String, dynamic> v;
    setUp(() => v = service.parseFormText(_page2, pageNumber: 2).vitals);
    test('systolic 140', () => expect(v['systolicBp'], 140));
    test('diastolic 90', () => expect(v['diastolicBp'], 90));
    test('pulse 82', () => expect(v['pulseRate'], 82));
    test('SpO2 97', () => expect(v['spo2'], 97));
    test('glucose 185', () => expect(v['bloodGlucose'], 185));
    test('urine normal', () => expect(v['urineTest'], 'normal'));
    test('pregnancy neg', () => expect(v['pregnancyTest'], 'neg'));
  });

  group('POP Staging', () {
    late Map<String, dynamic> p;
    setUp(() => p = service.parseFormText(_page2, pageNumber: 2).popStaging);
    test('anterior 2', () => expect(p['anteriorStage'], 2));
    test('middle 3', () => expect(p['middleStage'], 3));
    test('posterior 1', () => expect(p['posteriorStage'], 1));
    test('highest 3', () => expect(p['highestPopStage'], 3));
    test('tone weak', () => expect(p['pelvicFloorTone'], 'weak'));
  });

  group('Diagnoses', () {
    late List<String> d;
    setUp(() => d = service.parseFormText(_page2, pageNumber: 2).diagnoses);
    test('POP', () => expect(d, contains('POP')));
    test('hypertension via BP>=140', () => expect(d, contains('hypertension')));
    test('diabetes via glucose>=180', () => expect(d, contains('diabetes mellitus')));
    test('blank form empty diagnoses (no fake POP)', () => expect(service.parseFormText(_blank).diagnoses, isEmpty));
  });

  group('Medications', () {
    late List<String> m;
    setUp(() => m = service.parseFormText(_page2, pageNumber: 2).medications);
    test('Metronidazole', () => expect(m, contains('Metronidazole')));
    test('Fluconazole', () => expect(m, contains('Fluconazole')));
    test('blank form empty meds (no fake Metronidazole)', () => expect(service.parseFormText(_blank).medications, isEmpty));
  });

  group('Referral', () {
    test('stage 3 => Scheer referral', () => expect(service.parseFormText(_page2, pageNumber: 2).surgicalReferral, contains('Scheer')));
    test('stage 1 => no referral', () => expect(service.parseFormText('Middle Compartment Stage: 1', pageNumber: 2).surgicalReferral, isNull));
  });

  group('Confidence', () {
    test('overall in 0-1', () {
      final r = service.parseFormText(_page1, pageNumber: 1);
      expect(r.overallConfidence, inInclusiveRange(0.0, 1.0));
    });
    test('mobile = HIGH', () => expect(service.parseFormText(_page1, pageNumber: 1).getConfidenceTier('mobile'), 'HIGH'));
    test('blank name = LOW', () => expect(service.parseFormText(_blank).getConfidenceTier('name'), 'LOW'));
  });

  group('Sample Form texts', () {
    test('samplePage1 reasons use new keys', () {
      final r = service.parseFormText(OcrFormService.samplePage1Text, pageNumber: 1);
      final reasons = List<String>.from(r.demographics['reasonsForVisit'] as List);
      expect(reasons, contains('something hanging out'));
      expect(reasons, isNot(contains('Something hanging out / Prolapse')));
    });
    test('samplePage1 relative name has no bracket', () {
      final r = service.parseFormText(OcrFormService.samplePage1Text, pageNumber: 1);
      expect(r.demographics['relativeName'], isNot(contains('(')));
    });
    test('samplePage2 vitals 130/85', () {
      final r = service.parseFormText(OcrFormService.samplePage2Text, pageNumber: 2);
      expect(r.vitals['systolicBp'], 130);
      expect(r.vitals['diastolicBp'], 85);
    });
  });

  group('Merge', () {
    test('P1 demo + P2 vitals', () {
      final p1 = service.parseFormText(_page1, pageNumber: 1);
      final p2 = service.parseFormText(_page2, pageNumber: 2);
      final m = service.mergeScans(p1, p2);
      expect(m.demographics['firstName'], p1.demographics['firstName']);
      expect(m.vitals['systolicBp'], p2.vitals['systolicBp']);
      expect(m.isDualPage, true);
      expect(m.pageNumber, 0);
    });
    test('isSimulated propagates from page2', () {
      final p1 = service.parseFormText(_page1, pageNumber: 1);
      final p2 = service.parseFormText(_page2, pageNumber: 2).copyWith(isSimulated: true);
      expect(service.mergeScans(p1, p2).isSimulated, true);
    });
    test('isSimulated false when both real', () {
      final p1 = service.parseFormText(_page1, pageNumber: 1);
      final p2 = service.parseFormText(_page2, pageNumber: 2);
      expect(service.mergeScans(p1, p2).isSimulated, false);
    });
  });

  group('Page-Aware Separation & Real Test Samples', () {
    test('pageNumber 1 only extracts demographics & obstetrics, vitals/pop/dx are empty', () {
      final p1 = service.parseFormText(_page1, pageNumber: 1);
      expect(p1.demographics['firstName'], 'Kamala');
      expect(p1.obstetrics['deliveries'], 4);
      expect(p1.vitals, isEmpty);
      expect(p1.popStaging, isEmpty);
      expect(p1.diagnoses, isEmpty);
      expect(p1.medications, isEmpty);
      expect(p1.surgicalReferral, isNull);
    });

    test('pageNumber 2 only extracts clinical vitals/pop/dx, demographics/obs are empty', () {
      final p2 = service.parseFormText(_page2, pageNumber: 2);
      expect(p2.demographics, isEmpty);
      expect(p2.obstetrics, isEmpty);
      expect(p2.vitals['systolicBp'], 140);
      expect(p2.popStaging['highestPopStage'], 3);
      expect(p2.diagnoses, contains('POP'));
      expect(p2.medications, contains('Metronidazole'));
    });

    test('Real test sample page 1 OCR text: LMP 2080 does not pollute parity, husband name matches, abortions O is 0', () {
      const realSampleP1Ocr = """
GYNOCAMP CLINICAL INTAKE FORM (PAGE 1)
PATIENT INFORMATION
Patient Name: Maya Tamang
Husband's Name: Som Bahadur Tamang
Mobile: 9841987654
District: Kathmandu
Age: 44
Ward No: 04
Presenting Complaints:
Discharge / itching
Abdominal pain
Obstetric History:
Gravida: 3 Para: 3
Living: 3
Abortions: O
LMP: 2080-05-18 (N.s.)
""";
      final res = service.parseFormText(realSampleP1Ocr, pageNumber: 1);
      expect(res.demographics['firstName'], 'Maya');
      expect(res.demographics['surname'], 'Tamang');
      expect(res.demographics['relativeName'], 'Som Bahadur Tamang');
      expect(res.demographics['relativeType'], 'Husband');
      // Deliveries must be 3, NOT 20 from LMP 2080!
      expect(res.obstetrics['deliveries'], 3);
      expect(res.obstetrics['livingChildren'], 3);
      // Abortions 'O' must be normalized to 0
      expect(res.obstetrics['abortions'], 0);
    });

    test('Real test sample page 2 OCR text: underscores and OCR letters in stages & pulse', () {
      const realSampleP2Ocr = """
GYNOCAMP CLINICAL ASSESSMENT & EXAMINATION (PAGE 2)
POP Staging (Pelvic Organ Prolapse)
Anterior: L, Middle: 3, Posterior: _l_ Highest Stage: 3_
Vitals
BP: 130/85 mmHg, Pulse: __7_8_ bpm, Sp02: 98%
Blood Glucose: 115 mg/dL, Urine: Normal, HCG: Neg
Diagnoses
[X] POP
[X] candid infection
[x] hypertension
Prescriptions
[x] Rin Pessar (05mm
[x] Me+ronidazo e 00m BD
[x] luconazole 150m s+a+
Referrals
Surgical Referral: Scheer Memorial Hospi+al
""";
      final res = service.parseFormText(realSampleP2Ocr, pageNumber: 2);
      expect(res.popStaging['anteriorStage'], 1);
      expect(res.popStaging['middleStage'], 3);
      expect(res.popStaging['posteriorStage'], 1);
      expect(res.popStaging['highestPopStage'], 3);
      expect(res.vitals['systolicBp'], 130);
      expect(res.vitals['diastolicBp'], 85);
      expect(res.vitals['pulseRate'], 78);
      expect(res.vitals['bloodGlucose'], 115);
      expect(res.diagnoses, contains('POP'));
      expect(res.diagnoses, contains('candid infection'));
      expect(res.diagnoses, contains('hypertension'));
      expect(res.medications, contains('Metronidazole'));
      expect(res.medications, contains('Fluconazole'));
      expect(res.surgicalReferral, contains('Scheer Memorial Hospital'));
    });
  });
}
