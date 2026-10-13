import 'package:flutter_test/flutter_test.dart';
import 'package:gyno_camp/core/services/ocr_form_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ocrService = OcrFormService();

  group('OCR Detection Across All Blank Form Sample Variants', () {
    // ─────────────────────────────────────────────────────────────────────────
    // 1. Two-Column Field Grid vs Classic Single Column Page 1
    // ─────────────────────────────────────────────────────────────────────────
    test('1. Detects Page 1 Demographics from Two-Column Grid layout', () {
      const gridText = '''
WOMEN FOR SOCIETY (SODESI NEPAL)
YELLOW REGISTRATION FORM / बिरामी दर्ता फाराम
TOKEN ID: GC-ILM-2026-00001
FIRST NAME / पहिलो नाम: SITA
SURNAME / थर: SHRESTHA
AGE / उमेर: 34
MARITAL STATUS / वैवाहिक स्थिति: Married
RELATIVE NAME: RAM SHRESTHA
MOBILE / फोन नं.: 9841234567
WARD: 05
DISTRICT / जिल्ला: ILAM
MUNICIPALITY: MAI
REASONS FOR VISIT / मुख्य कारण:
[x] Lower Abdominal Pain
[x] White Discharge / Vaginal Itching
''';
      final res = ocrService.parseFormText(gridText, pageNumber: 1);
      expect(res.demographics['patientTokenId'], 'GC-ILM-2026-00001');
      expect(res.demographics['firstName'], 'Sita');
      expect(res.demographics['surname'], 'Shrestha');
      expect(res.demographics['age'], 34);
      expect(res.demographics['maritalStatus'], 'married');
      expect(res.demographics['ward'], '05');
      expect(res.demographics['district'], 'ILAM');
      expect(res.demographics['reasonsForVisit'], contains('pain'));
    });

    test('2. Detects Page 1 Demographics from Classic Single Column layout', () {
      const classicText = '''
WOMEN FOR SOCIETY (SODESI NEPAL)
YELLOW REGISTRATION FORM
PATIENT TOKEN ID: GC-ILM-2026-00002
First Name: GITA
Surname: MAGAR
Age: 42
Marital Status: Married
Spouse/Father: HARI MAGAR
Phone: 9812345678
Ward No: 02
District: ILAM
Palika: MAI
Chief Complaints:
[x] Prolapse / Sensation of lump falling
''';
      final res = ocrService.parseFormText(classicText, pageNumber: 1);
      expect(res.demographics['patientTokenId'], 'GC-ILM-2026-00002');
      expect(res.demographics['firstName'], 'Gita');
      expect(res.demographics['surname'], 'Magar');
      expect(res.demographics['age'], 42);
      expect(res.demographics['maritalStatus'], 'married');
      expect(res.demographics['ward'], '02');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 2. Doctor Checklist vs Pre-Printed Specific Doctor vs Blank Lines
    // ─────────────────────────────────────────────────────────────────────────
    test('3. Detects checked doctor from Multi-Doctor Checklist sample', () {
      const checklistText = '''
STATION 6: CLINICAL SUMMARY
Follow-up: Health Post in 2 weeks
Examining Doctor (जाँच गर्ने चिकित्सक):
[x] Dr. Anish Tiwari (NMC: 222/222)
[ ] Dr. Sagar Sharma (NMC: 333/333)
[ ] Other: _____
Doctor Signature & NMC: Dr. Anish Tiwari 222/222
''';
      final res = ocrService.parseFormText(checklistText, pageNumber: 2);
      expect(res.examiningDoctor, contains('Anish Tiwari'));
      expect(res.attendingDoctors, anyElement(contains('Anish Tiwari')));
    });

    test('4. Detects second checked doctor from Multi-Doctor Checklist sample', () {
      const checklistText = '''
STATION 6: CLINICAL SUMMARY
Follow-up: In 1 month
Examining Doctor:
[ ] Dr. Anish Tiwari
[x] Dr. Sagar Sharma (NMC: 333/333)
Doctor Signature: Dr. Sagar Sharma
''';
      final res = ocrService.parseFormText(checklistText, pageNumber: 2);
      expect(res.examiningDoctor, contains('Sagar Sharma'));
      expect(res.attendingDoctors, anyElement(contains('Sagar Sharma')));
    });

    test('5. Detects pre-printed specific doctor with NMC stamp', () {
      const preprintedText = '''
STATION 6: CLINICAL SUMMARY
Follow-up Destination: District Hospital
Examining Doctor: Dr. Sita Karki
Medical Officer / Gynecologist
NMC No: 14256 — Date: 2026-10-14
''';
      final res = ocrService.parseFormText(preprintedText, pageNumber: 2);
      expect(res.examiningDoctor, 'Dr. Sita Karki');
      expect(res.attendingDoctors, ['Dr. Sita Karki']);
    });

    test('6. Detects handwritten doctor name from Blank Lines sample', () {
      const blankLinesText = '''
STATION 6: CLINICAL SUMMARY
Examining Doctor / Gynecologist
Doctor Signature & NMC: Dr. Ramesh Adhikari (NMC: 98765)
''';
      final res = ocrService.parseFormText(blankLinesText, pageNumber: 2);
      expect(res.examiningDoctor, contains('Ramesh Adhikari'));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 3. Nurse Checklist vs Pre-Printed Specific Nurse vs Blank Lines
    // ─────────────────────────────────────────────────────────────────────────
    test('7. Detects checked nurse from Multi-Nurse Checklist sample', () {
      const nurseChecklistText = '''
STATION 6: CLINICAL SUMMARY
Attending Nurse (सेवा दिने नर्स):
[x] Ayusha Pathak
[ ] Smiriti Gautam
[ ] Other: _____
Nurse Signature & NNC: Ayusha Pathak
Examining Doctor: Dr. Anish Tiwari
''';
      final res = ocrService.parseFormText(nurseChecklistText, pageNumber: 2);
      expect(res.examiningNurse, 'Ayusha Pathak');
      expect(res.attendingNurses, contains('Ayusha Pathak'));
    });

    test('8. Detects pre-printed specific nurse with NNC number', () {
      const preprintedNurseText = '''
STATION 6: CLINICAL SUMMARY
Attending Nurse: Pooja Thapa
NNC No: 8901
Examining Doctor: Dr. Sita Karki
''';
      final res = ocrService.parseFormText(preprintedNurseText, pageNumber: 2);
      expect(res.examiningNurse, 'Pooja Thapa');
      expect(res.attendingNurses, contains('Pooja Thapa'));
    });

    test('9. Detects handwritten nurse from Blank Nurse Lines sample', () {
      const blankNurseText = '''
STATION 6: CLINICAL SUMMARY
Attending Nurse: Staff Nurse Manisha Giri
Nurse Signature & NNC: M. Giri 4455
Examining Doctor: Dr. Anish Tiwari
''';
      final res = ocrService.parseFormText(blankNurseText, pageNumber: 2);
      expect(res.examiningNurse, 'Manisha Giri');
      expect(res.attendingNurses, contains('Manisha Giri'));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 4. Follow-Up Clinical Encounter Sheet
    // ─────────────────────────────────────────────────────────────────────────
    test('10. Detects Follow-Up Encounter Sheet with Token ID & Clinicians', () {
      const followUpText = '''
FOLLOW-UP CLINICAL ENCOUNTER SHEET
पुनः जाँच तथा फलो-अप क्लिनिकल स्लिप
ENCOUNTER TOKEN ID: GC-ILM-2026-00005
Camp: first testing (11)
Patient Name: Kamala Devi
BP: 120/80 mmHg, Pulse: 72 bpm
Ring Pessary Review: Intact, Cleaned & Reinserted
Examining Doctor: Dr. Anish Tiwari
Attending Nurse: Ayusha Pathak
''';
      final res = ocrService.parseFormText(followUpText, pageNumber: 2);
      expect(res.demographics['patientTokenId'], 'GC-ILM-2026-00005');
      expect(res.examiningDoctor, contains('Anish Tiwari'));
      expect(res.examiningNurse, 'Ayusha Pathak');
      expect(res.vitals['systolicBp'], 120);
      expect(res.vitals['diastolicBp'], 80);
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 5. Completely Blank (Unfilled) Form Behavior
    // ─────────────────────────────────────────────────────────────────────────
    test('11. Completely Blank Form does NOT hallucinate diagnoses or vitals', () {
      const rawBlankFormText = '''
WOMEN FOR SOCIETY (SODESI NEPAL)
YELLOW REGISTRATION FORM / बिरामी दर्ता फाराम
CAMP: first testing (11) | Health Post
PATIENT TOKEN ID: [ ][ ][ ][ ][ ][ ][ ][ ][ ][ ]
FIRST NAME: _______________  SURNAME: _______________
AGE: [ ][ ]  MARITAL STATUS: [ ] Married [ ] Widow
STATION 1: OBSTETRIC HISTORY & CLINICAL COMPLAINTS
Deliveries: [ ][ ]  Living: [ ][ ]
STATION 2: CLINICAL ASSESSMENT (POP-Q STAGING)
Anterior: [ ] 0 [ ] 1 [ ] 2 [ ] 3 [ ] 4
Middle:   [ ] 0 [ ] 1 [ ] 2 [ ] 3 [ ] 4
Posterior:[ ] 0 [ ] 1 [ ] 2 [ ] 3 [ ] 4
STATION 3: VITALS
BP: [ ][ ] / [ ][ ] mmHg
STATION 4: CONFIRMED DIAGNOSES
[ ] atrophy vagina  [ ] candid infection  [ ] PID
STATION 5: TREATMENT & PRESCRIPTIONS
[ ] clotrimazol  [ ] metronidazol
''';
      final p1 = ocrService.parseFormText(rawBlankFormText, pageNumber: 1);
      final p2 = ocrService.parseFormText(rawBlankFormText, pageNumber: 2);

      // Check that un-ticked fields are safely empty
      expect(p1.demographics['firstName'], isNull);
      expect(p1.demographics['surname'], isNull);
      expect(p2.diagnoses, isEmpty);
      expect(p2.medications, isEmpty);
      expect(p2.vitals['systolicBp'], isNull);
      expect(p2.vitals['diastolicBp'], isNull);
    });
  });
}
