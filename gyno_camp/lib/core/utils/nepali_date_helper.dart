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

  /// Converts UTC timestamps to Nepal Standard Time (UTC+05:45) calendar wall-clock
  /// components while leaving local calendar DateTimes unchanged.
  static DateTime normalizeNepalCalendarDate(DateTime dt) {
    final wall = dt.isUtc ? dt.add(const Duration(hours: 5, minutes: 45)) : dt;
    return DateTime(
      wall.year,
      wall.month,
      wall.day,
      wall.hour,
      wall.minute,
      wall.second,
      wall.millisecond,
      wall.microsecond,
    );
  }

  /// Parses stored ISO / PostgreSQL TIMESTAMPTZ calendar dates safely without
  /// losing a day to UTC timezone offsets.
  static DateTime? parseStoredCalendarDate(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return normalizeNepalCalendarDate(raw);
    final str = raw.toString().trim();
    if (str.isEmpty) return null;
    final parsed = DateTime.tryParse(str);
    if (parsed == null) return null;
    return normalizeNepalCalendarDate(parsed);
  }

  static NepaliDateTime toNepali(DateTime dt) {
    final wall = normalizeNepalCalendarDate(dt);
    final targetDate = DateTime(wall.year, wall.month, wall.day);
    // Anchor at 12:00 Nepal Time (06:15 UTC) on the calendar date so device timezone
    // offsets never shift the calendar day.
    var np = DateTime.utc(
      wall.year,
      wall.month,
      wall.day,
      6,
      15,
      wall.second,
      wall.millisecond,
      wall.microsecond,
    ).toNepaliDateTime();

    // Guard against nepali_utils-3.0.8's Windows "Nepal Standard Time" (+05:45) +1 day
    // offset bug (Windows lacks the 1986 +05:30->+05:45 LMT rule, yet nepali_utils
    // unconditionally adds +1 day when local timeZoneOffset == +05:45).
    // NepaliDateTime.toDateTime() uses pure lookup-table integer math, so verifying
    // against it guarantees an exact AD <-> BS bijection on every OS and timezone.
    final roundTrip = NepaliDateTime(np.year, np.month, np.day).toDateTime();
    final diffDays = DateTime.utc(targetDate.year, targetDate.month, targetDate.day)
        .difference(DateTime.utc(roundTrip.year, roundTrip.month, roundTrip.day))
        .inDays;
    if (diffDays != 0) {
      final adjusted = DateTime.utc(wall.year, wall.month, wall.day, 6, 15)
          .add(Duration(days: diffDays));
      np = adjusted.toNepaliDateTime();
    }
    return NepaliDateTime(
      np.year,
      np.month,
      np.day,
      wall.hour,
      wall.minute,
      wall.second,
      wall.millisecond,
      wall.microsecond,
    );
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
