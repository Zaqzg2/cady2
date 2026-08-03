/// ملخص مجمّع لبيانات عميل واحد يُستخدم في بطاقة العميل وصفحته:
/// الرصيد، آخر حركة (زيارة)، آخر فاتورة، وإجماليات سريعة للمؤشرات.
class CustomerSummary {
  final double balance;
  final DateTime? lastActivity; // تاريخ آخر حركة (فاتورة أو سند)
  final String? lastInvoiceNumber;
  final int invoiceCount; // عدد فواتير البيع فقط
  final double receivedTotal; // إجمالي المقبوض (سندات القبض)
  final double returnsTotal; // إجمالي المرتجعات

  const CustomerSummary({
    required this.balance,
    this.lastActivity,
    this.lastInvoiceNumber,
    this.invoiceCount = 0,
    this.receivedTotal = 0,
    this.returnsTotal = 0,
  });

  int? get daysSinceLastActivity =>
      lastActivity == null ? null : DateTime.now().difference(lastActivity!).inDays;

  /// نص مختصر لعدد أيام آخر زيارة: اليوم / أمس / منذ N يوم
  String get lastActivityLabel {
    final d = daysSinceLastActivity;
    if (d == null) return 'لا توجد حركات';
    if (d <= 0) return 'اليوم';
    if (d == 1) return 'أمس';
    return 'منذ $d يوم';
  }
}
