import 'package:nepali_utils/nepali_utils.dart';

class NepaliDateHelper {
  static const List<String> nepaliMonthNames = [
    'बैशाख (Baisakh)',
    'जेठ (Jestha)',
    'असार (Ashadh)',
    'श्रावण (Shrawan)',
    'भाद्र (Bhadra)',
    'असोज (Ashwin)',
    'कार्तिक (Kartik)',
    'मंसिर (Mangsir)',
    'पौष (Poush)',
    'माघ (Magh)',
    'फाल्गुन (Falgun)',
    'चैत्र (Chaitra)',
  ];

  static const List<String> nepaliMonthPureNp = [
    'बैशाख', 'जेठ', 'असार', 'श्रावण', 'भाद्र', 'असोज',
    'कार्तिक', 'मंसिर', 'पौष', 'माघ', 'फाल्गुन', 'चैत्र'
  ];

  static const List<String> nepaliMonthPureEn = [
    'Baisakh', 'Jestha', 'Ashadh', 'Shrawan', 'Bhadra', 'Ashwin',
    'Kartik', 'Mangsir', 'Poush', 'Magh', 'Falgun', 'Chaitra'
  ];

  static const List<String> nepaliWeekDayShortNp = [
    'आई', 'सोम', 'मंगल', 'बुध', 'बिही', 'शुक्र', 'शनि'
  ];

  static const List<String> nepaliWeekDayShortEn = [
    'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'
  ];

  static NepaliDateTime toNepali(DateTime dt) {
    return dt.toNepaliDateTime();
  }

  static DateTime toEnglish(NepaliDateTime np) {
    return np.toDateTime();
  }

  static String formatBsDate(DateTime dt, {bool pureNepali = false}) {
    final np = toNepali(dt);
    if (pureNepali) {
      final monthName = nepaliMonthPureNp[np.month - 1];
      return 'वि.सं. ${np.year} $monthName ${np.day}';
    }
    final monthName = nepaliMonthPureEn[np.month - 1];
    return '$monthName ${np.day}, ${np.year} BS';
  }

  static String formatBsRange(DateTime start, DateTime end, {bool pureNepali = false}) {
    final npStart = toNepali(start);
    final npEnd = toNepali(end);
    if (npStart.year == npEnd.year && npStart.month == npEnd.month) {
      final mName = pureNepali ? nepaliMonthPureNp[npStart.month - 1] : nepaliMonthPureEn[npStart.month - 1];
      if (pureNepali) {
        return 'वि.सं. ${npStart.year} $mName ${npStart.day} – ${npEnd.day}';
      }
      return '$mName ${npStart.day} – ${npEnd.day}, ${npStart.year} BS';
    } else {
      return '${formatBsDate(start, pureNepali: pureNepali)} – ${formatBsDate(end, pureNepali: pureNepali)}';
    }
  }

  static int getDaysInBsMonth(int year, int month) {
    try {
      return NepaliDateTime(year, month).totalDays;
    } catch (_) {
      return 30;
    }
  }

  /// Returns 0 for Sunday, 1 for Monday, ..., 6 for Saturday
  static int getFirstDayWeekdayBs(int year, int month) {
    try {
      final firstDay = NepaliDateTime(year, month, 1);
      // In nepali_utils: 1=Sun, 2=Mon, ..., 7=Sat
      return firstDay.weekday - 1;
    } catch (_) {
      return 0;
    }
  }
}
