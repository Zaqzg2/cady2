import 'package:intl/intl.dart';

/// تنسيق المبالغ بالريال اليمني، وتنسيق التاريخ المستخدم في كل التطبيق
class Formatters {
  static final currency = NumberFormat.currency(
    locale: 'ar',
    symbol: 'ر.ي',
    decimalDigits: 0,
  );

  static final date = DateFormat('yyyy/MM/dd');
  static final _dmy = DateFormat('dd/MM/yyyy');
  static final _hm = DateFormat('HH:mm');

  // أسماء الأيام بالعربية يدويًا (DateTime.weekday: 1=الإثنين ... 7=الأحد)
  // لتفادي الحاجة لاستدعاء initializeDateFormatting('ar') في كل أنحاء التطبيق.
  static const _arWeekdays = [
    'الإثنين',
    'الثلاثاء',
    'الأربعاء',
    'الخميس',
    'الجمعة',
    'السبت',
    'الأحد',
  ];

  static String money(num value) => currency.format(value);
  static String d(DateTime dt) => date.format(dt);

  /// اسم اليوم بالعربية + التاريخ + الوقت، مثل: "السبت 03/08/2026 • 10:45"
  static String dt(DateTime dt) =>
      '${_arWeekdays[dt.weekday - 1]} ${_dmy.format(dt)} • ${_hm.format(dt)}';
}
