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
}
