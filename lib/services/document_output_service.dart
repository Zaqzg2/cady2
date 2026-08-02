import 'dart:typed_data';

import '../models/company_settings.dart';
import '../models/invoice.dart';
import '../models/receipt.dart';
import 'pdf_service.dart';

/// يولّد ملفات PDF للفواتير والسندات مرة واحدة فقط لكل نسخة من المستند،
/// ويعيد استخدام نفس النسخة لأي إجراء تالٍ (طباعة/مشاركة/تحميل/معاينة)
/// بدل توليد الملف من جديد في كل ضغطة زر — أسرع وأخف على المعالج
/// والبطارية، خصوصًا على الأجهزة الضعيفة.
class DocumentOutputService {
  DocumentOutputService._();
  static final DocumentOutputService instance = DocumentOutputService._();

  final Map<String, Uint8List> _cache = {};

  /// المفتاح يتضمن آخر تعديل مؤثر (رقم المستند + الإجمالي) حتى لو عُدّل
  /// المستند بنفس الـ id، يتولّد PDF جديد بدل استخدام نسخة قديمة مخزّنة.
  Future<Uint8List> bytesForInvoice(Invoice inv, CompanySettings settings) async {
    final key = 'inv_${inv.id}_${inv.docNumber}_${inv.grandTotal}_${inv.items.length}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final bytes = await PdfService.instance.generateInvoicePdf(inv, settings);
    _cache[key] = bytes;
    return bytes;
  }

  Future<Uint8List> bytesForReceipt(Receipt r, CompanySettings settings) async {
    final key = 'rcpt_${r.id}_${r.docNumber}_${r.amount}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final bytes = await PdfService.instance.generateReceiptPdf(r, settings);
    _cache[key] = bytes;
    return bytes;
  }

  /// تفريغ كل نسخ مستند معيّن من الذاكرة المؤقتة (يُستخدم بعد حذفه أو
  /// تعديله من مكان آخر لضمان عدم عرض نسخة قديمة).
  void invalidate(String docId) {
    _cache.removeWhere((k, _) => k.contains(docId));
  }

  void clear() => _cache.clear();
}
