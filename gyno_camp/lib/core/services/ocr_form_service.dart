import 'dart:math';
import '../../models/ocr_scan_result_model.dart';

class OcrFormService {
  const OcrFormService();

  /// Parses raw text extracted from a photographed Yellow Form into structured models
  OcrScanResultModel parseFormText(String text, {int pageNumber = 0, String? imagePath}) {
    final confidences = <String, double>{};
    final lowerText = text.toLowerCase();

    final bool isPage1Only = pageNumber == 1;
    final bool isPage2Only = pageNumber == 2;

    int? parseOcrInt(String? raw) {
      if (raw == null) return null;
      final clean = raw.replaceAll(RegExp(r'[Oo]'), '0')
                       .replaceAll(RegExp(r'[LlI|]'), '1')
                       .replaceAll(RegExp(r'[^0-9]'), '');
      return int.tryParse(clean);
    }

    int? parseStageInt(String? raw) {
      if (raw == null) return null;
      final clean = raw.replaceAll('_', '').trim();
      if (clean.toLowerCase() == 'l' || clean == 'I' || clean == '|') return 1;
      return int.tryParse(clean);
    }

    // ==========================================
    // 1. Demographics Extraction (Page 1 / Front)
    // ==========================================
    final demographics = <String, dynamic>{};
    final obstetrics = <String, dynamic>{};

    if (!isPage2Only) {
      // First & Last Name
      final nameLineMatch = RegExp(
        r'(?:patient\s*name|बिरामीको\s*नाम|नाम)[:\s]+([A-Za-z\u0900-\u097F\s]{2,40})',
        caseSensitive: false,
      ).firstMatch(text);
      if (nameLineMatch != null) {
        final rawName = nameLineMatch.group(1)!.trim().split(RegExp(r'[\r\n]+')).first.trim();
        final parts = rawName.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
        if (parts.length >= 2) {
          demographics['firstName'] = parts.first;
          demographics['surname'] = parts.sublist(1).join(' ');
          confidences['name'] = 0.95;
        } else if (parts.isNotEmpty) {
          demographics['firstName'] = parts.first;
          demographics['surname'] = null;
          confidences['name'] = 0.70;
        } else {
          demographics['firstName'] = null;
          demographics['surname'] = null;
          confidences['name'] = 0.30;
        }
      } else {
        // Fallback: search for generic Name:
        final fallbackName = RegExp(r'(?:name|नाम)[:\s]+([A-Za-z\u0900-\u097F\s]{3,30})', caseSensitive: false).firstMatch(text);
        if (fallbackName != null) {
          final parts = fallbackName.group(1)!.trim().split(RegExp(r'[\r\n]+')).first.trim().split(RegExp(r'\s+'));
          demographics['firstName'] = parts.isNotEmpty ? parts[0] : null;
          demographics['surname'] = parts.length > 1 ? parts.sublist(1).join(' ') : null;
          confidences['name'] = 0.70;
        } else {
          demographics['firstName'] = null;
          demographics['surname'] = null;
          confidences['name'] = 0.30;
        }
      }

      // Age
      final ageMatch = RegExp(r'\b(?:age|उमेर)[:\s]+(\d{1,3})\b', caseSensitive: false).firstMatch(text);
      if (ageMatch != null) {
        final parsedAge = int.tryParse(ageMatch.group(1)!);
        if (parsedAge != null && parsedAge >= 10 && parsedAge <= 110) {
          demographics['age'] = parsedAge;
          confidences['age'] = 0.95;
        } else {
          demographics['age'] = 35;
          confidences['age'] = 0.60;
        }
      } else {
        demographics['age'] = 35;
        confidences['age'] = 0.50;
      }

      // Relative / Spouse / Father Name (handles "Husband's Name:", "Spouse:", "Father:", etc.)
      final relMatch = RegExp(
        r'(?:husband(?:\x27s|\u2019s|\u0027s)?(?:\s*name)?|spouse(?:\s*name)?|father(?:\x27s|\u2019s|\u0027s)?(?:\s*name)?|relative(?:\s*name)?|guardian(?:\s*name)?|श्रीमान(?:को)?(?:\s*नाम)?|बुबा(?:को)?(?:\s*नाम)?|पति)[:\s]+([A-Za-z\u0900-\u097F\s]{2,35})',
        caseSensitive: false,
      ).firstMatch(text);
      if (relMatch != null) {
        var relName = relMatch.group(1)!.trim().split(RegExp(r'[\r\n]+')).first.trim();
        relName = relName.replaceAll(RegExp(r'\s*\(.*?\)\s*$'), '').trim();
        demographics['relativeName'] = relName;
        final matchedHeader = relMatch.group(0)!.toLowerCase();
        if (matchedHeader.contains('husband') || matchedHeader.contains('श्रीमान') || matchedHeader.contains('पति')) {
          demographics['relativeType'] = 'Husband';
        } else if (matchedHeader.contains('father') || matchedHeader.contains('बुबा')) {
          demographics['relativeType'] = 'Father';
        } else if (matchedHeader.contains('guardian')) {
          demographics['relativeType'] = 'Guardian';
        } else {
          demographics['relativeType'] = (demographics['age'] as int? ?? 30) < 20 ? 'Father' : 'Husband';
        }
        confidences['relative'] = 0.90;
      } else {
        demographics['relativeName'] = null;
        demographics['relativeType'] = 'Husband';
        confidences['relative'] = 0.50;
      }

      // Mobile Number (Nepali standard 10 digits: 98... or 97...)
      final normalizedTextForMobile = text.replaceAll(RegExp(r'\b[qgQG]([78]\d{8})\b'), r'9$1');
      final mobileMatch = RegExp(r'\b(98\d{8}|97\d{8})\b').firstMatch(normalizedTextForMobile);
      if (mobileMatch != null) {
        demographics['mobile'] = mobileMatch.group(1);
        confidences['mobile'] = 0.98;
      } else {
        demographics['mobile'] = '';
        confidences['mobile'] = 0.50;
      }

      // Ward Number
      final wardMatch = RegExp(r'(?:ward|वडा)(?:\s*no\.?)?[:\s#]*(\d{1,2})', caseSensitive: false).firstMatch(text);
      if (wardMatch != null) {
        demographics['ward'] = wardMatch.group(1)!.padLeft(2, '0');
        confidences['ward'] = 0.95;
      } else {
        demographics['ward'] = '03';
        confidences['ward'] = 0.60;
      }

      // District & Municipality
      final districtMatch = RegExp(
        r'(?:district|जिल्ला)[:\s]+([A-Za-z\u0900-\u097F\s]{3,25})',
        caseSensitive: false,
      ).firstMatch(text);
      demographics['district'] = districtMatch?.group(1)?.trim().split(RegExp(r'[\r\n]+')).first.trim() ?? '';

      final muniMatch = RegExp(
        r'(?:municipality|vdc|ward\s*center|गाउँपालिका|नगरपालिका)[:\s]+([A-Za-z\u0900-\u097F\s0-9]{3,40})',
        caseSensitive: false,
      ).firstMatch(text);
      demographics['municipality'] = muniMatch?.group(1)?.trim().split(RegExp(r'[\r\n]+')).first.trim() ?? '';
      confidences['location'] = (districtMatch != null) ? 0.92 : 0.55;

      // Marital Status
      if (lowerText.contains('widow') || lowerText.contains('विधवा')) {
        demographics['maritalStatus'] = 'widow';
        confidences['maritalStatus'] = 0.90;
      } else if (lowerText.contains('unmarried') || lowerText.contains('अविवाहित')) {
        demographics['maritalStatus'] = 'unmarried';
        confidences['maritalStatus'] = 0.90;
      } else {
        demographics['maritalStatus'] = 'married';
        confidences['maritalStatus'] = 0.85;
      }

      // Reasons for visit — exact keys for PatientModel.reasonsForVisit
      final reasons = <String>[];
      if (lowerText.contains('prolapse') || lowerText.contains('hanging') || lowerText.contains('पाठेघर खस्ने') || lowerText.contains('something hanging')) {
        reasons.add('something hanging out');
      }
      if (lowerText.contains('discharge') || lowerText.contains('itching') || lowerText.contains('चिलाउने')) {
        reasons.add('discharge and or itching');
      }
      if (lowerText.contains('urine') || lowerText.contains('incontinence') || lowerText.contains('पिसाब') || lowerText.contains('पेसाब')) {
        reasons.add('problems passing urine');
      }
      if (lowerText.contains('stool') || lowerText.contains('rectum') || lowerText.contains('दिसा')) {
        reasons.add('problems passing stool');
      }
      if (lowerText.contains('back pain') || lowerText.contains('backache') || lowerText.contains('abdominal') || lowerText.contains('pelvic pain') || lowerText.contains('ढाड दुख्ने') || lowerText.contains('दुखाई') || lowerText.contains('pain')) {
        reasons.add('pain');
      }
      if (lowerText.contains('menstrual') || lowerText.contains('mahina') || lowerText.contains('महिनावारी') || lowerText.contains('period')) {
        reasons.add('menstrual problem');
      }
      if (lowerText.contains('infertil') || lowerText.contains('banjhopan') || lowerText.contains('बाँझोपन')) {
        reasons.add('infertility');
      }
      if (lowerText.contains('checkup') || lowerText.contains('general check') || lowerText.contains('सामान्य जाँच')) {
        reasons.add('checkup');
      }
      demographics['reasonsForVisit'] = reasons;
      confidences['reasonsForVisit'] = reasons.isNotEmpty ? 0.88 : 0.40;

      // Obstetric History (Anamnesis)
      // Negative lookbehind ensures we NEVER match LMP: 2080 (where P: was mistakenly matched as parity 20)
      final parityMatch = RegExp(
        r'\b(?:deliveries|parity|para)\b[:\s]*([0-9Oo]{1,2})|(?<![a-zA-Z])p\s*[:=]\s*([0-9Oo]{1,2})\b',
        caseSensitive: false,
      ).firstMatch(text);

      final livingMatch = RegExp(
        r'\b(?:living(?:\s*children)?|alive)\b[:\s]*([0-9Oo]{1,2})|(?<![a-zA-Z])l\s*[:=]\s*([0-9Oo]{1,2})\b',
        caseSensitive: false,
      ).firstMatch(text);

      final abortionMatch = RegExp(
        r'\b(?:abortions|miscarriage|miscarriages)\b[:\s]*([0-9Oo]{1,2})|(?<![a-zA-Z])a\s*[:=]\s*([0-9Oo]{1,2})\b',
        caseSensitive: false,
      ).firstMatch(text);

      int rawDeliveries = parseOcrInt(parityMatch?.group(1) ?? parityMatch?.group(2)) ?? 3;
      if (rawDeliveries > 15) {
        // Reject improbable parity values (often OCR date/year artifacts)
        rawDeliveries = 3;
      }

      int rawLiving = parseOcrInt(livingMatch?.group(1) ?? livingMatch?.group(2)) ?? min(rawDeliveries, 3);
      if (rawLiving > 15) rawLiving = min(rawDeliveries, 3);

      int rawAbortions = parseOcrInt(abortionMatch?.group(1) ?? abortionMatch?.group(2)) ?? 0;
      if (rawAbortions > 15) rawAbortions = 0;

      obstetrics['deliveries'] = rawDeliveries;
      obstetrics['livingChildren'] = min(rawLiving, rawDeliveries);
      obstetrics['abortions'] = rawAbortions;
      confidences['obstetrics'] = (parityMatch != null || livingMatch != null) ? 0.92 : 0.65;
    }

    // ==========================================
    // 2. Clinical Assessment (Page 2 / Back)
    // ==========================================
    final vitals = <String, dynamic>{};
    final popStaging = <String, dynamic>{};
    final diagnoses = <String>[];
    final medications = <String>[];
    String? surgicalReferral;
    String? followUp;

    if (!isPage1Only) {
      // Blood Pressure (e.g. 130/85 or 120/80)
      final bpMatch = RegExp(r'\b(\d{2,3})\s*[/:]\s*(\d{2,3})\b').firstMatch(text);
      if (bpMatch != null) {
        final sys = int.tryParse(bpMatch.group(1)!);
        final dia = int.tryParse(bpMatch.group(2)!);
        if (sys != null && sys >= 60 && sys <= 260) {
          vitals['systolicBp'] = sys;
        }
        if (dia != null && dia >= 40 && dia <= 160) {
          vitals['diastolicBp'] = dia;
        }
        confidences['bp'] = 0.95;
      } else {
        vitals['systolicBp'] = 120;
        vitals['diastolicBp'] = 80;
        confidences['bp'] = 0.60;
      }

      // Pulse (handles OCR artifacts like "__7_8_ bpm")
      final pulseMatch = RegExp(
        r'(?:pulse(?:\s*rate)?|pr|hr|मुटुको गति)[:\s]*([_\s0-9]{2,8})\b|([_\s0-9]{2,8})\s*bpm',
        caseSensitive: false,
      ).firstMatch(text);
      if (pulseMatch != null) {
        final valStr = pulseMatch.group(1) ?? pulseMatch.group(2);
        final parsedPulse = parseOcrInt(valStr);
        if (parsedPulse != null && parsedPulse >= 35 && parsedPulse <= 220) {
          vitals['pulseRate'] = parsedPulse;
          confidences['pulse'] = 0.92;
        } else {
          vitals['pulseRate'] = 76;
          confidences['pulse'] = 0.60;
        }
      } else {
        vitals['pulseRate'] = 76;
        confidences['pulse'] = 0.60;
      }

      // SpO2
      final spo2Match = RegExp(r'(?:spo2|sp02|saturation|o2)[:\s]*(\d{2,3})%?', caseSensitive: false).firstMatch(text);
      if (spo2Match != null) {
        final parsedSpo2 = int.tryParse(spo2Match.group(1)!);
        if (parsedSpo2 != null && parsedSpo2 >= 50 && parsedSpo2 <= 100) {
          vitals['spo2'] = parsedSpo2;
          confidences['spo2'] = 0.95;
        } else {
          vitals['spo2'] = 98;
          confidences['spo2'] = 0.60;
        }
      } else {
        vitals['spo2'] = 98;
        confidences['spo2'] = 0.60;
      }

      // Blood Glucose
      final glucoseMatch = RegExp(r'(?:glucose|sugar|rbs)[:\s]*(\d{2,3})', caseSensitive: false).firstMatch(text);
      if (glucoseMatch != null) {
        final parsedGlucose = int.tryParse(glucoseMatch.group(1)!);
        if (parsedGlucose != null && parsedGlucose >= 30 && parsedGlucose <= 600) {
          vitals['bloodGlucose'] = parsedGlucose;
          confidences['glucose'] = 0.90;
        } else {
          vitals['bloodGlucose'] = 110;
          confidences['glucose'] = 0.60;
        }
      } else {
        vitals['bloodGlucose'] = 110;
        confidences['glucose'] = 0.60;
      }

      // Rapid Tests
      vitals['urineTest'] = (lowerText.contains('urine: pos') || lowerText.contains('urine pos')) ? 'pos' : 'normal';
      vitals['pregnancyTest'] = (lowerText.contains('hcg: pos') || lowerText.contains('pregnancy: pos')) ? 'pos' : 'neg';
      confidences['labs'] = 0.85;

      // POP Examination & Staging (Station 3)
      final antMatch = RegExp(r'(?:anterior|cystocele)[:\s]*([_0-3LlI|]+)', caseSensitive: false).firstMatch(text);
      final midMatch = RegExp(r'(?:middle|uterine|cervical)[:\s]*([_0-4LlI|]+)', caseSensitive: false).firstMatch(text);
      final postMatch = RegExp(r'(?:posterior|rectocele)[:\s]*([_0-3LlI|]+)', caseSensitive: false).firstMatch(text);
      final highestMatch = RegExp(r'(?:highest(?:\s*pop)?\s*stage|highest)[:\s]*([_0-4LlI|]+)', caseSensitive: false).firstMatch(text);

      final ant = parseStageInt(antMatch?.group(1)) ?? (lowerText.contains('pop') ? 2 : 1);
      final mid = parseStageInt(midMatch?.group(1)) ?? (lowerText.contains('pop') ? 3 : 1);
      final post = parseStageInt(postMatch?.group(1)) ?? 1;
      final explicitHighest = parseStageInt(highestMatch?.group(1));
      final highest = explicitHighest ?? max(ant, max(mid, post));

      popStaging['uterusInside'] = highest == 0;
      popStaging['pelvicFloorTone'] = (lowerText.contains('tone: weak') || lowerText.contains('tone weak') || lowerText.contains('weak')) ? 'weak' : 'normal';
      popStaging['anteriorStage'] = ant;
      popStaging['middleStage'] = mid;
      popStaging['posteriorStage'] = post;
      popStaging['highestPopStage'] = highest;
      confidences['popStaging'] = (antMatch != null || midMatch != null || highestMatch != null) ? 0.94 : 0.70;

      // Diagnoses
      if (lowerText.contains('pop') || highest >= 2) {
        diagnoses.add('POP');
      }
      if (lowerText.contains('candid') || lowerText.contains('fungal')) {
        diagnoses.add('candid infection');
      }
      if (lowerText.contains('vaginosis') || lowerText.contains('bv')) {
        diagnoses.add('bacterial vaginosis');
      }
      if (lowerText.contains('cervicitis')) {
        diagnoses.add('cervicitis');
      }
      if (lowerText.contains('cystitis') || lowerText.contains('uti')) {
        diagnoses.add('cystitis');
      }
      if (lowerText.contains('hypertension') || (vitals['systolicBp'] as int? ?? 0) >= 140) {
        diagnoses.add('hypertension');
      }
      if (lowerText.contains('diabetes') || (vitals['bloodGlucose'] as int? ?? 0) >= 180) {
        diagnoses.add('diabetes mellitus');
      }
      confidences['diagnoses'] = diagnoses.isNotEmpty ? 0.88 : 0.40;

      // Prescriptions & Medications (handles OCR typos like "me+ronidazo" or "luconazole")
      if (RegExp(r'met?ronida|me\+ronida', caseSensitive: false).hasMatch(text)) {
        medications.add('Metronidazole');
      }
      if (RegExp(r'f?luconazole', caseSensitive: false).hasMatch(text)) {
        medications.add('Fluconazole');
      }
      if (RegExp(r'ciproflox', caseSensitive: false).hasMatch(text)) {
        medications.add('Ciprofloxacin');
      }
      if (RegExp(r'clotrimaz', caseSensitive: false).hasMatch(text)) {
        medications.add('Clotrimazole');
      }
      confidences['medications'] = medications.isNotEmpty ? 0.85 : 0.40;

      // Referrals
      if (highest >= 3 || lowerText.contains('scheer')) {
        surgicalReferral = 'Scheer Memorial Hospital';
      }
      followUp = highest >= 2 ? 'GynaeSupport Nurse' : 'Health Post';
    }

    // Calculate overall confidence based on active fields
    final totalConf = confidences.values.fold<double>(0.0, (sum, val) => sum + val);
    final avgConf = confidences.isNotEmpty ? totalConf / confidences.length : 0.80;

    return OcrScanResultModel(
      pageNumber: pageNumber,
      imagePath: imagePath,
      demographics: demographics,
      obstetrics: obstetrics,
      vitals: vitals,
      popStaging: popStaging,
      diagnoses: diagnoses,
      medications: medications,
      surgicalReferral: surgicalReferral,
      followUpDestination: followUp,
      fieldConfidences: confidences,
      overallConfidence: double.parse(avgConf.toStringAsFixed(2)),
      rawText: text,
      scannedAt: DateTime.now(),
    );
  }

  /// Merges Page 1 (Front: Demographics & Anamnesis) and Page 2 (Back: POP Staging & Prescriptions)
  OcrScanResultModel mergeScans(OcrScanResultModel page1, OcrScanResultModel page2) {
    return OcrScanResultModel.merge(page1, page2);
  }

  // ==========================================
  // High-Fidelity Pre-Configured Samples
  // ==========================================

  /// Sample 1: Front Page (Intake & Obstetric History)
  static const String samplePage1Text = '''
GYNOCAMP RURAL HEALTH CLINICAL INTAKE FORM (YELLOW FORM - PAGE 1)
Camp Code: KTM01    Date: 2026-09-06
Patient Name: Maya Tamang
Age: 44 Years
Relative: Som Bahadur Tamang (Husband)
Mobile: 9841987654
District: Kathmandu
Municipality: Ward 04 Community Center
Ward: 04
Marital Status: [x] Married
Reasons for Visit:
[x] Something hanging out / Prolapse (पाठेघर खस्ने समस्या)
[x] Discharge and/or itching (चिलाउने समस्या)
[x] Abdominal / Back pain (ढाड दुख्ने)

OBSTETRIC HISTORY:
Deliveries: 3
Living Children: 3
Abortions: 0
Complaints Duration: >1 Year
Consent: [x] Treatment Informed Consent Granted
''';

  /// Sample 2: Back Page (Vitals, POP Examination, Diagnoses & Treatment)
  static const String samplePage2Text = '''
GYNOCAMP CLINICAL ASSESSMENT & EXAMINATION (YELLOW FORM - PAGE 2)
Station 3: Pelvic Organ Prolapse (POP) Examination
Uterus Inside: No (Prolapsed outside introitus)
Pelvic Floor Tone: Weak
Anterior Compartment Stage: 2
Middle Compartment Stage: 3
Posterior Compartment Stage: 1
Highest POP Stage: 3

Station 4: Point-of-Care Lab Tests & Vitals
Blood Pressure: 130/85 mmHg
Pulse Rate: 78 bpm
SpO2: 98%
Blood Glucose: 115 mg/dL
Urine Test: Normal
Pregnancy Test: Neg

Station 5: Diagnoses & Prescription
Diagnoses:
[x] POP (Pelvic Organ Prolapse Stage 3)
[x] candid infection (Candidiasis)
[x] hypertension (Pre-hypertension monitor)

Treatments & Prescriptions:
[x] Ring Pessary (Size 65mm fitted)
[x] Metronidazole 400mg PO BD x 7d
[x] Fluconazole 150mg stat
Surgical Referral: Scheer Memorial Hospital (Vaginal Hysterectomy evaluation)
Follow-up: GynaeSupport Nurse in 2 weeks
''';

  /// Sample 3: Full 2-Page Combined Intake
  static const String sampleFullFormText = '''
$samplePage1Text
----------------------------------------
$samplePage2Text
''';
}
