import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/ocr_form_service.dart';

const String page1Ocr = '''
Government of Nepal
'GYNOCAMP CLINICAL INTAKE FORM (YELLOW FORM)
Ministry of Health - Nepal Rural Health Camp Program
Date: 2026-oq-oq
Camp Code: K T M-2026-01
SECTION 1: PATIENT DEMOGRAPHICS
Age: 38 Years
Patient Name: Kamala Devi Thapa
Husband/Spouse: Ram Bahadur Thapa (Husband)
Mobile: q841234567
District: Sindhupalchok
Municipality: Melamchi Rural Municipali+y Ward: 05
Marital Status: Married Unmarried Widow
SECTION 2: REASONS FOR VISIT
OMR
Something hanging out / Prolapse •a-a)
Discharge and/or Itching (RFff3å
Problems passing urine / Incontinence
Abdominal / Back Pain (G
Menstrual Problem
Infertility (ai\$l•qöT)
Problems passing Stool
General Checkup
SECTION 3: OBSTETRIC HISTORY
Deliveries: _4_ Living Children: 3 Abortions:
Duration of Complaints: > 2 Years
Consent: Treatment Informed Consent Granted
Consent to Store Medical Information
''';

const String page2Ocr = '''
GYNOCAMP CLINICAL ASSESSMENT FORM - PAGE 2 (BACK)
STATION 3: PELVIC ORGAN PROLAPSE (POP) EXAMINATION
Uterus Inside:
Pelvic Floor Tone:
Ü Yes NO (Prolapsed)
Weak Ü Normal Strong
Anterior Compartment Stage: _2_ Middle Compartment Stage: _3_
Posterior Compartment Stage: _1_ Highest POP Stage: _3_
STATION 4: POINT-OF-CARE LAB TESTS & VITALS
Blood Pressure:
Pulse Rate:
sp02:
Blood Glucose (RBS):
Urine Test:
Pregnancy Test (hCG):
140 / 90 mmHg
82 bpm
97%
185 mg/dL
Normal
Ü Positive
Ü Positive
Negative
STATION 5: DIAGNOSES & PRESCRIPTION
Diagnoses:
Treatments &
Prescriptions:
Surgical Referral:
Follow-up:
Clinician Signature:
POP (Pelvic Organ Prolapse Stage 3)
Hypertension (Pre-hypertension monitor)
Diabetes Mellitus (Type 2, newly detected)
Ü Candidal Infection
Ü Bacterial Vaginosis
Ü Cervicitis
Ring Pessary (Size 65mm fitted)
Metronidazole 400mg PO BD x 7 days
Fluconazole 150mg stat
Scheer Memorial Hospital (Vaginal Hysterectomy evaluation)
GynaeSupport Nurse in 2 weeks
Date: 2026-09-09
''';

void main() {
  test('Evaluate parser against real OCR output from printed Yellow Form', () {
    const service = OcrFormService();
    final p1 = service.parseFormText(page1Ocr, pageNumber: 1);
    expect(p1.demographics['firstName'], 'Kamala');
    expect(p1.demographics['surname'], 'Devi Thapa');
    expect(p1.demographics['age'], 38);
    expect(p1.demographics['relativeName'], 'Ram Bahadur Thapa');
    expect(p1.demographics['relativeType'], 'Husband');
    expect(p1.demographics['mobile'], '9841234567');
    expect(p1.demographics['ward'], '05');
    expect(p1.demographics['district'], 'Sindhupalchok');
    expect(p1.demographics['municipality'], 'Melamchi Rural Municipality');
    expect(p1.demographics['maritalStatus'], 'married');
    expect(p1.obstetrics['deliveries'], 4);
    expect(p1.obstetrics['livingChildren'], 3);
    expect(p1.obstetrics['abortions'], 1);

    final p2 = service.parseFormText(page2Ocr, pageNumber: 2);
    expect(p2.popStaging['anteriorStage'], 2);
    expect(p2.popStaging['middleStage'], 3);
    expect(p2.popStaging['posteriorStage'], 1);
    expect(p2.popStaging['highestPopStage'], 3);
    expect(p2.popStaging['uterusInside'], false);
    expect(p2.popStaging['pelvicFloorTone'], 'weak');
    expect(p2.vitals['systolicBp'], 140);
    expect(p2.vitals['diastolicBp'], 90);
    expect(p2.vitals['pulseRate'], 82);
    expect(p2.vitals['spo2'], 97);
    expect(p2.vitals['bloodGlucose'], 185);
    expect(p2.vitals['urineTest'], 'normal');
    expect(p2.vitals['pregnancyTest'], 'neg');
    expect(p2.diagnoses, contains('POP'));
    expect(p2.diagnoses, contains('hypertension'));
    expect(p2.diagnoses, contains('diabetes mellitus'));
    expect(p2.diagnoses, isNot(contains('candid infection')));
    expect(p2.diagnoses, isNot(contains('bacterial vaginosis')));
    expect(p2.diagnoses, isNot(contains('cervicitis')));
    expect(p2.medications, contains('Ring Pessary'));
    expect(p2.medications, contains('Metronidazole'));
    expect(p2.medications, contains('Fluconazole'));
    expect(p2.surgicalReferral, contains('Scheer Memorial Hospital'));

    final merged = service.mergeScans(p1, p2);
    expect(merged.isDualPage, true);
    expect(merged.demographics['firstName'], 'Kamala');
    expect(merged.vitals['systolicBp'], 140);
  });
}
