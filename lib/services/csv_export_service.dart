import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/invoice.dart';
import 'db_service.dart';

/// تصدير بيانات التطبيق كملفات CSV (تُفتح مباشرة في Excel/Sheets) لغرض
/// المراجعة اليدوية — بخلاف النسخة الاحتياطية JSON المخصّصة للاستيراد
/// الآلي فقط
class CsvExportService {
  static final _df = DateFormat('yyyy-MM-dd');

  static String _esc(Object? v) {
    final s = (v ?? '').toString();
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static String _row(List<Object?> cells) => cells.map(_esc).join(',') + '\r\n';

  static Future<File> _writeCsv(String filename, String content) async {
    final dir = await getApplicationDocumentsDirectory();
    // BOM حتى تفتح Excel الملف بترميز UTF-8 صحيح مع النصوص العربية —
    // مهم: نستخدم utf8.encode() لا content.codeUnits، لأن الأخيرة تُعيد
    // وحدات UTF-16 الخام التي تُفسد أي حرف عربي (خارج نطاق ASCII) عند
    // كتابتها مباشرة كبايتات.
    final file = File('${dir.path}/$filename');
    final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(content)];
    await file.writeAsBytes(bytes);
    return file;
  }

  static Future<List<File>> exportAll() async {
    final customers = await DbService.instance.getCustomers();
    final invoices = await DbService.instance.getInvoices();
    final receipts = await DbService.instance.getReceipts();

    final customersBuf = StringBuffer();
    customersBuf.write(_row(
        ['الاسم', 'الهاتف', 'العنوان', 'الرصيد الافتتاحي', 'الحد الائتماني', 'نشط', 'ملاحظات']));
    for (final c in customers) {
      customersBuf.write(_row([
        c.name,
        c.phone,
        c.address,
        c.openingBalance,
        c.creditLimit,
        c.isActive ? 'نعم' : 'لا',
        c.notes,
      ]));
    }

    final invoicesBuf = StringBuffer();
    invoicesBuf.write(_row([
      'رقم الفاتورة',
      'التاريخ',
      'النوع',
      'العميل',
      'طريقة الدفع',
      'عدد الأصناف',
      'الإجمالي الفرعي',
      'الخصم',
      'الإجمالي النهائي',
      'الرصيد بعد الفاتورة',
    ]));
    for (final i in invoices) {
      invoicesBuf.write(_row([
        i.docNumber,
        _df.format(i.date),
        i.kind == InvoiceKind.sale ? 'بيع' : 'مرتجع',
        i.customerName,
        i.paymentMode == PaymentMode.cash ? 'نقدًا' : 'آجل',
        i.items.length,
        i.subTotal,
        i.discountValue,
        i.grandTotal,
        i.balanceAfter,
      ]));
    }

    final receiptsBuf = StringBuffer();
    receiptsBuf.write(_row(
        ['رقم السند', 'التاريخ', 'العميل', 'طريقة الدفع', 'المبلغ', 'الرصيد بعد السند']));
    for (final r in receipts) {
      receiptsBuf.write(_row([
        r.docNumber,
        _df.format(r.date),
        r.customerName,
        r.method.name,
        r.amount,
        r.balanceAfter,
      ]));
    }

    final stamp = DateTime.now().toIso8601String().split('T').first;
    return [
      await _writeCsv('عملاء_$stamp.csv', customersBuf.toString()),
      await _writeCsv('فواتير_$stamp.csv', invoicesBuf.toString()),
      await _writeCsv('سندات_$stamp.csv', receiptsBuf.toString()),
    ];
  }

  static Future<void> exportAndShare() async {
    final files = await exportAll();
    await SharePlus.instance.share(ShareParams(
      files: files.map((f) => XFile(f.path)).toList(),
      text: 'تصدير بيانات كادي للمنظفات (CSV)',
    ));
  }
}
