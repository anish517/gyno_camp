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

  test('Evaluate Page 2 Station 1-3 clinical complaints, duration, cervix/vagina, and lab detection under real scan noise', () {
    const service = OcrFormService();

    const page2Station1to3Ocr = '''
GYNOCAMP CLINICAL ASSESSMENT FORM - PAGE 2 (BACK)
STATION 1: ANAMNESIS & CLINICAL COMPLAINTS
Deliveries: 3  Living: 2  Abortions: 1
Complaint Duration:
[x] < 3 months  [ ] 3-12 months  [ ] > 1 year
Chief Clinical Complaints:
[x] Lower Abdominal Pain (तल्लो पेट दुख्ने)
[x] White / Foul Discharge (सेतो / गन्हाउने पानी)
[ ] Pelvic Heaviness
[x] Burning Micturition (पिसाब पोल्ने)
[ ] Urinary Incontinence
[x] Dyspareunia (सम्बन्ध राख्दा दुख्ने)
[ ] Coital Bleeding
[x] Mass Per Vagina (केही बाहिर निस्कने)
[ ] Severe Backache

STATION 2: PELVIC EXAMINATION & POP STAGING
Uterus Inside: [ ] Yes  [x] No / Prolapsed
Pelvic Floor Tone: [ ] Normal  [ ] Weak  [x] Hypertonic
Cervix Appearance: Erosion present, contact bleeding noted
Vagina / Vulva: Mild atrophic vaginitis, yellowish discharge
Anterior Compartment (Cystocele): Stage 2
Middle Compartment (Uterine): Stage 3
Posterior Compartment (Rectocele): Stage 1
Highest POP Stage: Stage 3

STATION 3: POINT-OF-CARE LAB TESTS & VITALS
Blood Pressure: 135/88 mmHg
Pulse Rate: 78 bpm
SpO2: 99%
Blood Glucose (RBS): 142 mg/dL
Urine Dipstick: [x] Protein+  [x] Glucose+  [ ] Blood+
Pregnancy Test (UPT): [x] Negative  [ ] Positive  [ ] Not Done
''';

    final result = service.parseFormText(page2Station1to3Ocr, pageNumber: 2);

    // Station 1: Obstetric History & Anamnesis
    expect(result.obstetrics['deliveries'], 3);
    expect(result.obstetrics['livingChildren'], 2);
    expect(result.obstetrics['abortions'], 1);
    expect(result.obstetrics['complaintsDuration'], '< 3 months');

    final complaints = (result.obstetrics['clinicalComplaints'] as List).cast<String>();
    expect(complaints, contains('Lower Abdominal Pain'));
    expect(complaints, contains('White / Foul Discharge'));
    expect(complaints, contains('Burning Micturition'));
    expect(complaints, contains('Dyspareunia'));
    expect(complaints, contains('Mass Per Vagina'));
    expect(complaints, isNot(contains('Pelvic Heaviness')));
    expect(complaints, isNot(contains('Coital Bleeding')));
    expect(complaints, isNot(contains('Severe Backache')));

    // Station 2: Pelvic Exam & POP Staging
    expect(result.popStaging['uterusInside'], false);
    expect(result.popStaging['pelvicFloorTone'], 'hypertonic');
    expect(result.popStaging['cervixRemarks'], contains('Erosion'));
    expect(result.popStaging['vaginaRemarks'], contains('atrophic'));
    expect(result.popStaging['anteriorStage'], 2);
    expect(result.popStaging['middleStage'], 3);
    expect(result.popStaging['posteriorStage'], 1);
    expect(result.popStaging['highestPopStage'], 3);

    // Station 3: Vitals & Point-of-care Labs
    expect(result.vitals['systolicBp'], 135);
    expect(result.vitals['diastolicBp'], 88);
    expect(result.vitals['pulseRate'], 78);
    expect(result.vitals['spo2'], 99);
    expect(result.vitals['bloodGlucose'], 142);
    expect(result.vitals['urineTest'], contains('protein'));
    expect(result.vitals['urineTest'], contains('glucose'));
    expect(result.vitals['urineTest'], isNot(contains('blood')));
    expect(result.vitals['pregnancyTest'], 'neg');
  });
}
