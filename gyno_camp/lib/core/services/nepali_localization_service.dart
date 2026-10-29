import 'package:nepali_utils/nepali_utils.dart';
import '../utils/nepali_date_helper.dart';

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

    // Consultation Triage
    'consultation': 'परामर्श',
    'counseling': 'काउन्सिलिङ',
    'gynocheckup': 'गाइनो जाँच',
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

  /// Formats date showing both Bikram Sambat (BS) and Gregorian (AD) accurately using nepali_utils
  static String formatDualCalendarDate(DateTime date, {bool bsFirst = true}) {
    try {
      NepaliDateTime np;
      DateTime ad;
      if (date.year >= 2070 && date.year <= 2120) {
        np = NepaliDateTime(date.year, date.month, date.day);
        ad = NepaliDateHelper.toEnglish(np);
      } else {
        ad = date;
        np = NepaliDateHelper.toNepali(date);
      }
      final bsStr = '${np.year}-${np.month.toString().padLeft(2, '0')}-${np.day.toString().padLeft(2, '0')} BS';
      final adStr = '${ad.year}-${ad.month.toString().padLeft(2, '0')}-${ad.day.toString().padLeft(2, '0')} AD';
      return bsFirst ? '$bsStr ($adStr)' : '$adStr ($bsStr)';
    } catch (_) {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }

  /// Formats date showing Bikram Sambat (BS) only
  static String formatBsDateOnly(DateTime date) {
    try {
      NepaliDateTime np;
      if (date.year >= 2070 && date.year <= 2120) {
        np = NepaliDateTime(date.year, date.month, date.day);
      } else {
        np = NepaliDateHelper.toNepali(date);
      }
      return '${np.year}-${np.month.toString().padLeft(2, '0')}-${np.day.toString().padLeft(2, '0')} BS';
    } catch (_) {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} AD';
    }
  }

  /// Formats date with Nepali Month name (e.g., 'Kartik 13, 2083 BS (2026-10-29 AD)')
  static String formatDescriptiveDualDate(DateTime date) {
    try {
      NepaliDateTime np;
      DateTime ad;
      if (date.year >= 2070 && date.year <= 2120) {
        np = NepaliDateTime(date.year, date.month, date.day);
        ad = NepaliDateHelper.toEnglish(np);
      } else {
        ad = date;
        np = NepaliDateHelper.toNepali(date);
      }
      final monthName = (np.month >= 1 && np.month <= 12)
          ? NepaliDateHelper.nepaliMonthPureEn[np.month - 1]
          : '${np.month}';
      final bsStr = '$monthName ${np.day}, ${np.year} BS';
      final adStr = '${ad.year}-${ad.month.toString().padLeft(2, '0')}-${ad.day.toString().padLeft(2, '0')} AD';
      return '$bsStr ($adStr)';
    } catch (_) {
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
  }

  static String formatNepaliDate(DateTime date) => formatDualCalendarDate(date);
}
