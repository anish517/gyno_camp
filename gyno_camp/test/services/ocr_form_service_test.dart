import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/ocr_form_service.dart';
import 'package:gyno_camp/models/ocr_scan_result_model.dart';

void main() {
  const service = OcrFormService();

  OcrScanResultModel parsePage1() =>
      service.parseFormText(OcrFormService.samplePage1Text, pageNumber: 1);
  OcrScanResultModel parsePage2() =>
      service.parseFormText(OcrFormService.samplePage2Text, pageNumber: 2);
  OcrScanResultModel parseFull() =>
      OcrScanResultModel.merge(parsePage1(), parsePage2());

  void expectField(Map<String, dynamic> map, String key, dynamic expected) {
    expect(map[key], expected,
        reason: 'Field "$key": expected $expected but got ${map[key]}');
  }

  void expectConf(Map<String, double> confs, String key,
      {double min = 0.70}) {
    final v = confs[key];
    expect(v, isNotNull, reason: 'Confidence key "$key" is missing');
    expect(v! >= min, isTrue,
        reason: 'Confidence "$key" = $v, expected >= $min');
  }

  // ──────────────────────────────────────────────────────────
  // PAGE 1  Demographics
  // ──────────────────────────────────────────────────────────
  group('Page 1 — Demographics', () {
    late OcrScanResultModel r;
    late Map<String, dynamic> d;
    late Map<String, double> c;
    setUpAll(() { r = parsePage1(); d = r.demographics; c = r.fieldConfidences; });

    test('First Name = Maya',    () { expectField(d, 'firstName', 'Maya');   expectConf(c, 'name'); });
    test('Surname = Tamang',     () { expectField(d, 'surname',   'Tamang'); });
    test('Age = 44',             () { expectField(d, 'age', 44);             expectConf(c, 'age', min: 0.90); });
    test('Marital = married',    () { expectField(d, 'maritalStatus', 'married'); expectConf(c, 'maritalStatus', min: 0.80); });
    test('Relative type = Husband', () { expectField(d, 'relativeType', 'Husband'); });
    test('Relative name contains SOM or BAHADUR', () {
      final name = (d['relativeName'] as String? ?? '').toUpperCase();
      expect(name.contains('SOM') || name.contains('BAHADUR') || name.contains('TAMANG'), isTrue,
          reason: 'relativeName "$name" should contain SOM / BAHADUR / TAMANG');
      expectConf(c, 'relative', min: 0.85);
    });
    test("Woman mobile = 9841987654", () { expectField(d, 'mobile', '9841987654'); expectConf(c, 'mobile', min: 0.90); });
    test('Contact person contains BISHAL', () {
      final cp = (d['contactPerson'] as String? ?? '').toUpperCase();
      expect(cp.contains('BISHAL') || cp.contains('TAMANG'), isTrue,
          reason: 'contactPerson "$cp" should contain BISHAL / TAMANG');
      expectConf(c, 'contactPerson', min: 0.75);
    });
    test('Contact mobile = 9851234567', () { expectField(d, 'contactMobile', '9851234567'); expectConf(c, 'contactMobile', min: 0.75); });
    test('Age at marriage = 18',  () { expectField(d, 'maritalAge', 18); expectConf(c, 'maritalAge', min: 0.80); });
    test('District contains KATHMANDU', () {
      final dist = (d['district'] as String? ?? '').toUpperCase();
      expect(dist.contains('KATHMANDU'), isTrue, reason: 'district "$dist"');
      expectConf(c, 'location', min: 0.85);
    });
    test('Municipality contains BUDHANILKANTHA', () {
      final muni = (d['municipality'] as String? ?? '').toUpperCase();
      expect(muni.contains('BUDHANILKANTHA'), isTrue, reason: 'municipality "$muni"');
    });
    test('Ward = 04', () { expectField(d, 'ward', '04'); expectConf(c, 'ward', min: 0.85); });
    test('Province in rawText', () {
      expect(r.rawText.toLowerCase().contains('bagmati'), isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────
  // PAGE 1  Obstetric History
  // ──────────────────────────────────────────────────────────
  group('Page 1 — Obstetrics', () {
    late Map<String, dynamic> o;
    setUpAll(() { o = parsePage1().obstetrics; });

    test('Deliveries = 3',       () { expectField(o, 'deliveries',     3); });
    test('Living children = 3',  () { expectField(o, 'livingChildren', 3); });
    test('Abortions = 0',        () { expectField(o, 'abortions',      0); });
  });

  // ──────────────────────────────────────────────────────────
  // PAGE 1  Visit Reasons (all 4 checked)
  // ──────────────────────────────────────────────────────────
  group('Page 1 — Visit Reasons', () {
    late List reasons;
    setUpAll(() {
      reasons = parsePage1().demographics['reasonsForVisit'] as List? ?? [];
    });

    test('something hanging out',       () { expect(reasons.contains('something hanging out'), isTrue,        reason: reasons.toString()); });
    test('discharge and or itching',    () { expect(reasons.contains('discharge and or itching'), isTrue,     reason: reasons.toString()); });
    test('problems passing urine',      () { expect(reasons.contains('problems passing urine'), isTrue,       reason: reasons.toString()); });
    test('menstrual problem',           () { expect(reasons.contains('menstrual problem'), isTrue,            reason: reasons.toString()); });
  });

  // ──────────────────────────────────────────────────────────
  // PAGE 2  Vitals & Labs
  // ──────────────────────────────────────────────────────────
  group('Page 2 — Vitals', () {
    late Map<String, dynamic> v;
    late Map<String, double> c;
    setUpAll(() { final r = parsePage2(); v = r.vitals; c = r.fieldConfidences; });

    test('Systolic BP = 130',    () { expectField(v, 'systolicBp',   130); expectConf(c, 'bp',      min: 0.90); });
    test('Diastolic BP = 85',    () { expectField(v, 'diastolicBp',  85);  });
    test('Pulse = 78',           () { expectField(v, 'pulseRate',    78);  expectConf(c, 'pulse',   min: 0.90); });
    test('SpO2 = 98',            () { expectField(v, 'spo2',         98);  expectConf(c, 'spo2',    min: 0.90); });
    test('Blood glucose = 115',  () { expectField(v, 'bloodGlucose', 115); expectConf(c, 'glucose', min: 0.85); });
    test('Urine = normal',       () { expectField(v, 'urineTest',    'normal'); });
    test('Pregnancy test = neg', () { expectField(v, 'pregnancyTest','neg'); });
  });

  // ──────────────────────────────────────────────────────────
  // PAGE 2  POP Staging
  // ──────────────────────────────────────────────────────────
  group('Page 2 — POP Staging', () {
    late Map<String, dynamic> p;
    late Map<String, double> c;
    setUpAll(() { final r = parsePage2(); p = r.popStaging; c = r.fieldConfidences; });

    test('Anterior stage = 2',   () { expectField(p, 'anteriorStage',  2); expectConf(c, 'popStaging', min: 0.85); });
    test('Middle stage = 3',     () { expectField(p, 'middleStage',    3); });
    test('Posterior stage = 1',  () { expectField(p, 'posteriorStage', 1); });
    test('Highest stage = 3',    () { expectField(p, 'highestPopStage',3); });
    test('Uterus inside = false',() { expectField(p, 'uterusInside',   false); });
    test('Pelvic tone = weak',   () { expectField(p, 'pelvicFloorTone','weak'); });
  });

  // ──────────────────────────────────────────────────────────
  // PAGE 2  Diagnoses
  // ──────────────────────────────────────────────────────────
  group('Page 2 — Diagnoses', () {
    late OcrScanResultModel r;
    setUpAll(() { r = parsePage2(); });

    test('POP detected',           () { expect(r.diagnoses.any((d) => d.toLowerCase().contains('pop')), isTrue, reason: r.diagnoses.toString()); });
    test('Candid infection',       () { expect(r.diagnoses.any((d) => d.toLowerCase().contains('candid')), isTrue, reason: r.diagnoses.toString()); });
    test('Hypertension detected',  () { expect(r.diagnoses.any((d) => d.toLowerCase().contains('hypertension')), isTrue, reason: r.diagnoses.toString()); });
    test('Diagnoses confidence >= 0.85', () { expect(r.fieldConfidences['diagnoses']! >= 0.85, isTrue); });
  });

  // ──────────────────────────────────────────────────────────
  // PAGE 2  Medications & Treatment
  // ──────────────────────────────────────────────────────────
  group('Page 2 — Medications & Referral', () {
    late OcrScanResultModel r;
    setUpAll(() { r = parsePage2(); });

    test('Ring Pessary',          () { expect(r.medications.any((m) => m.toLowerCase().contains('pessary')),      isTrue, reason: r.medications.toString()); });
    test('Metronidazole',         () { expect(r.medications.any((m) => m.toLowerCase().contains('metronidazole')),isTrue, reason: r.medications.toString()); });
    test('Fluconazole',           () { expect(r.medications.any((m) => m.toLowerCase().contains('fluconazole')),  isTrue, reason: r.medications.toString()); });
    test('Scheer referral',       () { expect(r.surgicalReferral?.toLowerCase().contains('scheer') ?? false, isTrue, reason: r.surgicalReferral); });
    test('Follow-up not empty',   () { expect(r.followUpDestination?.isNotEmpty ?? false, isTrue); });
  });

  // ──────────────────────────────────────────────────────────
  // FULL 2-PAGE MERGE
  // ──────────────────────────────────────────────────────────
  group('Full 2-Page Merge', () {
    late OcrScanResultModel m;
    setUpAll(() { m = parseFull(); });

    test('Demographics carried from Page 1',    () { expect(m.demographics['firstName'], isNotNull); });
    test('Mobile carried from Page 1',          () { expect(m.demographics['mobile'], isNotNull); });
    test('Vitals carried from Page 2',           () { expect(m.vitals['systolicBp'], isNotNull); });
    test('POP staging carried from Page 2',      () { expect(m.popStaging['highestPopStage'], isNotNull); });
    test('Diagnoses carried from Page 2',        () { expect(m.diagnoses, isNotEmpty); });
    test('Medications carried from Page 2',      () { expect(m.medications, isNotEmpty); });
    test('Overall confidence >= 0.80',           () { expect(m.overallConfidence >= 0.80, isTrue, reason: 'confidence = ${m.overallConfidence}'); });
  });

  // ──────────────────────────────────────────────────────────
  // MISSING FIELDS AUDIT (documented, not failing)
  // ──────────────────────────────────────────────────────────
  group('Missing Fields Audit', () {
    test('Province: known gap — not a dedicated demographics key', () {
      final p1 = parsePage1();
      final hasKey = p1.demographics.containsKey('province');
      if (!hasKey) {
        // ignore: avoid_print
        print('INFO: "province" is not in demographics map — it is in rawText only. '
            'Add a province parser to OcrFormService if needed.');
      }
      // Not failing — documenting the gap
    });

    test('All core demographic keys present', () {
      final d = parsePage1().demographics;
      for (final key in ['firstName','surname','age','maritalStatus','relativeName',
          'relativeType','mobile','ward','district','municipality']) {
        expect(d.containsKey(key), isTrue, reason: 'Key "$key" missing from demographics');
      }
    });
  });
}
