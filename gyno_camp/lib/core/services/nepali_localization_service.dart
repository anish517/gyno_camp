class NepaliLocalizationService {
  static const Map<String, String> _termsEnToNe = {
    // Primary complaints
    'something hanging out': 'पाठेघर खस्ने समस्या (प्रोल्याप्स)',
    'discharge and or itching': 'योनीबाट पानी बग्ने वा चिलाउने',
    'problems passing urine': 'पिसाब फेर्न समस्या / चुहिने',
    'problems passing stool': 'दिसा गर्न समस्या',
    'menstrual problem': 'महिनावारी सम्बन्धी समस्या',
    'infertility': 'बाँझोपन',
    'pain': 'तल्लो पेट वा ढाड दुख्ने',
    'checkup': 'नियमित स्वास्थ्य जाँच',

    // Marital Status
    'married': 'विवाहित',
    'widow': 'एकल महिला (विधवा)',
    'unmarried': 'अविवाहित',
    'divorced': 'सम्बन्धविच्छेद',

    // Discharge Colors
    'white': 'सेतो',
    'yellow': 'पहेँलो',
    'green': 'हरियो',
    'grey': 'खैरो',
    'smelly': 'गन्हाउने',

    // Incontinence Types
    'stress': 'खोक्दा वा हाँस्दा चुहिने (Stress)',
    'urge': 'पिसाब थाम्न नसक्ने (Urge)',
    'continuous flow': 'निरन्तर पिसाब बगिरहने (Continuous)',

    // Pelvic Floor
    'normal': 'सामान्य (Normal)',
    'weak': 'कमजोर (Weak)',
    'hypertonic': 'कडा / तनावग्रस्त (Hypertonic)',

    // Pessary
    'ring': 'साधारण रिङ (Ring)',
    'ring with support': 'सपोर्टसहितको रिङ (Ring with Support)',
    'ring with knob': 'नबसहितको रिङ (Ring with Knob)',

    // Follow-up
    'Health Post': 'स्थानीय स्वास्थ्य चौकी (Health Post)',
    'GynaeSupport Nurse': 'गाइनोसपोर्ट नर्स (GynaeSupport Nurse)',

    // Common Diagnoses & Conditions
    'pop': 'आङ खस्ने समस्या (POP)',
    'uti': 'पिसाब संक्रमण (UTI)',
    'hypertension': 'उच्च रक्तचाप (High BP)',
    'ring pessary': 'रिङ पेसरी',
  };

  /// Translates clinical terminology from English to Nepali
  static String translate(String englishTerm) {
    final lower = englishTerm.trim().toLowerCase();
    for (final entry in _termsEnToNe.entries) {
      if (entry.key.toLowerCase() == lower) {
        return entry.value;
      }
    }
    return englishTerm;
  }

  /// Formats date showing both Gregorian (AD) and Bikram Sambat (BS approximation)
  /// Nepal calendar is approx +56.7 years ahead
  static String formatDualCalendarDate(DateTime date) {
    final adStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} AD';
    final bsYear = date.year + 57;
    // Approximating Nepali month based on mid-month shifts
    final bsMonth = ((date.month + 8) % 12) + 1;
    final bsDay = date.day;
    final bsStr = '$bsYear-${bsMonth.toString().padLeft(2, '0')}-${bsDay.toString().padLeft(2, '0')} BS';
    return '$adStr ($bsStr)';
  }

  static String formatNepaliDate(DateTime date) => formatDualCalendarDate(date);
}
