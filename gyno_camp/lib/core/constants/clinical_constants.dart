class ClinicalConstants {
  // Blood Pressure Validations (mmHg)
  static const int minSystolicWarning = 90;
  static const int maxSystolicWarning = 160;
  static const int minSystolicError = 60;
  static const int maxSystolicError = 260;

  static const int minDiastolicWarning = 60;
  static const int maxDiastolicWarning = 100;
  static const int minDiastolicError = 40;
  static const int maxDiastolicError = 160;

  // Pulse (bpm)
  static const int minPulseWarning = 55;
  static const int maxPulseWarning = 110;
  static const int minPulseError = 35;
  static const int maxPulseError = 220;

  // Oxygen Saturation SpO2 (%)
  static const int minSpO2Warning = 92;
  static const int maxSpO2Warning = 100;
  static const int minSpO2Error = 50;
  static const int maxSpO2Error = 100;

  // Blood Glucose (mg/dL)
  static const int minGlucoseWarning = 70;
  static const int maxGlucoseWarning = 200;
  static const int minGlucoseError = 30;
  static const int maxGlucoseError = 600;

  // Age Threshold for Duplicate Detection Spouse vs Father
  static const int adultAgeThreshold = 20;

  // Pelvic Floor Muscle Tones
  static const String pelvicFloorNormal = 'normal';
  static const String pelvicFloorWeak = 'weak';
  static const String pelvicFloorHypertonic = 'hypertonic';

  // POP Max Stages
  static const int maxStageAnterior = 3;
  static const int maxStageMiddle = 4;
  static const int maxStagePosterior = 3;
  static const int maxStageHighest = 4;

  // 21 Standard Diagnoses (from Yellow Form)
  static const List<String> defaultDiagnoses = [
    'atrophy vagina',
    'bacterial vaginosis',
    'candid infection',
    'trichomonas',
    'PID',
    'cervicitis',
    'cervical polyp',
    'cervical carcinoma',
    'condylomata',
    'fistula',
    'infertility',
    'myoma',
    'cystitis',
    'lichen sclerosis',
    'stress incontinence',
    'ovarian tumor',
    'urge incontinence',
    'menstrual disorder',
    'weak pelvic floor muscle',
    'pregnancy',
    'hypertonic pelvic floor muscle',
  ];

  // 10 Standard Medications (from Yellow Form)
  static const List<String> defaultMedications = [
    'clotrimazol (canesten)',
    'estradiol crème',
    'metronidazol',
    'doxycycline',
    'azithromycin',
    'nitrofurantoine',
    'medroxyprogesterone',
    'ciproflox',
    'mirasin',
    'clobetasol',
  ];

  // Referral Hospitals (from Yellow Form)
  static const List<String> referralHospitals = [
    'Scheer Memorial Hospital',
    'Model Hospital',
    'Local Government Hospital',
  ];

  // Nepal Administrative Divisions
  static const List<String> nepalProvinces = [
    'Koshi',
    'Madhesh',
    'Bagmati',
    'Gandaki',
    'Lumbini',
    'Karnali',
    'Sudurpashchim',
  ];

  // Surgery Types (Station 6 / Outtake / Follow-up)
  static const List<String> surgeryTypes = [
    'Open surgery',
    'Laparoscopy',
    'Vaginal route',
  ];

  // Diagnosis Categories
  static const Map<String, String> diagnosisCategoryMap = {
    'atrophy vagina': 'Neoplasms & Structural',
    'bacterial vaginosis': 'Infections & STIs',
    'candid infection': 'Infections & STIs',
    'trichomonas': 'Infections & STIs',
    'PID': 'Infections & STIs',
    'cervicitis': 'Infections & STIs',
    'cervical polyp': 'Neoplasms & Structural',
    'cervical carcinoma': 'Neoplasms & Structural',
    'condylomata': 'Infections & STIs',
    'fistula': 'Pelvic Floor & Incontinence',
    'infertility': 'Endocrine & Reproductive',
    'myoma': 'Neoplasms & Structural',
    'cystitis': 'Infections & STIs',
    'lichen sclerosis': 'Neoplasms & Structural',
    'stress incontinence': 'Pelvic Floor & Incontinence',
    'ovarian tumor': 'Neoplasms & Structural',
    'urge incontinence': 'Pelvic Floor & Incontinence',
    'menstrual disorder': 'Endocrine & Reproductive',
    'weak pelvic floor muscle': 'Pelvic Floor & Incontinence',
    'pregnancy': 'Endocrine & Reproductive',
    'hypertonic pelvic floor muscle': 'Pelvic Floor & Incontinence',
  };

  static const List<String> diagnosisCategories = [
    'Pelvic Floor & Incontinence',
    'Infections & STIs',
    'Neoplasms & Structural',
    'Endocrine & Reproductive',
    'General / Other',
  ];

  // Medication Categories
  static const Map<String, String> medicationCategoryMap = {
    'clotrimazol (canesten)': 'Antibiotics & Antifungals',
    'estradiol crème': 'Hormonal & Steroids',
    'metronidazol': 'Antibiotics & Antifungals',
    'doxycycline': 'Antibiotics & Antifungals',
    'azithromycin': 'Antibiotics & Antifungals',
    'nitrofurantoine': 'Antibiotics & Antifungals',
    'medroxyprogesterone': 'Hormonal & Steroids',
    'ciproflox': 'Antibiotics & Antifungals',
    'mirasin': 'Urinary & General',
    'clobetasol': 'Hormonal & Steroids',
  };

  static const List<String> medicationCategories = [
    'Antibiotics & Antifungals',
    'Hormonal & Steroids',
    'Urinary & General',
    'Other / Custom',
  ];

  // ── Visit Reason Options (Yellow Form Page 1 Checkboxes) ──────────────────
  // KEY   = stored value in PatientModel.reasonsForVisit (exact match)
  // VALUE = bilingual display label shown in UI, PDF, and OCR output
  // This is the single source of truth shared by:
  //   • PatientRegistrationView (UI checkboxes)
  //   • PdfReportService.generatePatientRegistrationFormPdf (Section B)
  //   • OcrFormService (reason key resolution)
  static const Map<String, String> visitReasonOptions = {
    'something hanging out':    'Something Hanging Out / Prolapse (पाठेघर खस्ने)',
    'discharge and or itching': 'Vaginal Discharge / Itching (स्राव / खटिरो)',
    'problems passing urine':   'Problems Passing Urine (पेसाब सम्बन्धी समस्या)',
    'problems passing stool':   'Problems Passing Stool (दिसा सम्बन्धी समस्या)',
    'menstrual problem':        'Menstrual Problem (महिनावारी सम्बन्धी समस्या)',
    'infertility':              'Infertility (बाँझोपन)',
    'pain':                     'Pelvic / Abdominal Pain (दुखाई)',
    'checkup':                  'General Gynaecological Checkup (सामान्य जाँच)',
  };
}

