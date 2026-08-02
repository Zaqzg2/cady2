import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/company_settings.dart';
import '../models/customer.dart';
import '../models/invoice.dart';
import '../models/ledger_entry.dart';
import '../models/receipt.dart';

/// توليد ملفات PDF حقيقية بعرض 80مم مطابقة تمامًا لما تطبعه
/// الطابعة الحرارية (نفس التخطيط يُستخدم أيضًا لأوامر ESC/POS في print_service).
///
/// ملاحظة مهمة: لدعم الحروف العربية داخل PDF يجب توفير خط TTF عربي
/// ضمن assets/fonts/NotoNaskhArabic-Regular.ttf وتسجيله في pubspec.yaml
/// تحت fonts: — بدون ذلك ستظهر الحروف العربية كمربعات فارغة.
class PdfService {
  PdfService._();
  static final PdfService instance = PdfService._();

  pw.Font? _arabicFont;
  pw.Font? _arabicFontBold;

  Future<void> _ensureFonts() async {
    if (_arabicFont != null) return;
    try {
      final regular =
          await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
      _arabicFont = pw.Font.ttf(regular);
      try {
        final bold =
            await rootBundle.load('assets/fonts/NotoNaskhArabic-Bold.ttf');
        _arabicFontBold = pw.Font.ttf(bold);
      } catch (_) {
        _arabicFontBold = _arabicFont;
      }
    } catch (_) {
      // في حال عدم توفر الخط بعد سيستخدم الخط الافتراضي (لن يدعم العربية بشكل مثالي)
      _arabicFont = null;
      _arabicFontBold = null;
    }
  }

  final _currency = NumberFormat.currency(
    locale: 'ar',
    symbol: 'ر.ي',
    decimalDigits: 0,
  );

  pw.Widget _header(CompanySettings s, {required String docTitle}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        if (s.logoPath != null && File(s.logoPath!).existsSync())
          pw.Container(
            height: 55,
            margin: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Image(pw.MemoryImage(File(s.logoPath!).readAsBytesSync())),
          ),
        pw.Text(
          s.companyName,
          style: pw.TextStyle(font: _arabicFontBold, fontSize: 13),
          textDirection: pw.TextDirection.rtl,
        ),
        if (s.companyPhone.isNotEmpty)
          pw.Text(s.companyPhone,
              style: pw.TextStyle(font: _arabicFont, fontSize: 8),
              textDirection: pw.TextDirection.rtl),
        if (s.companyAddress.isNotEmpty)
          pw.Text(s.companyAddress,
              style: pw.TextStyle(font: _arabicFont, fontSize: 8),
              textDirection: pw.TextDirection.rtl),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 5),
          child: pw.Divider(thickness: 0.7, color: PdfColor.fromInt(s.identityColorValue)),
        ),
        pw.Text(
          docTitle,
          style: pw.TextStyle(
              font: _arabicFontBold,
              fontSize: 11,
              color: PdfColor.fromInt(s.identityColorValue)),
          textDirection: pw.TextDirection.rtl,
        ),
      ],
    );
  }

  pw.Widget _kv(String k, String v, {double fontSize = 9, double lineSpacing = 3}) {
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: lineSpacing / 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(v,
              style: pw.TextStyle(font: _arabicFont, fontSize: fontSize),
              textDirection: pw.TextDirection.rtl),
          pw.Text(k,
              style: pw.TextStyle(font: _arabicFont, fontSize: fontSize),
              textDirection: pw.TextDirection.rtl),
        ],
      ),
    );
  }

  Future<Uint8List> generateInvoicePdf(
      Invoice inv, CompanySettings settings) async {
    await _ensureFonts();
    final df = DateFormat('yyyy/MM/dd');
    final title = inv.kind == InvoiceKind.sale ? 'فاتورة بيع' : 'فاتورة مرتجع';
    final visibleCols = settings.tableColumns.where((c) => c.visible).toList();

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(8),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _header(settings, docTitle: title),
              pw.SizedBox(height: 4),
              _kv('رقم الفاتورة', inv.docNumber,
                  fontSize: settings.docFontSize, lineSpacing: settings.docLineSpacing),
              _kv('التاريخ', df.format(inv.date),
                  fontSize: settings.docFontSize, lineSpacing: settings.docLineSpacing),
              _kv('العميل', inv.customerName,
                  fontSize: settings.docFontSize, lineSpacing: settings.docLineSpacing),
              _kv('نوع الدفع',
                  inv.paymentMode == PaymentMode.cash ? 'نقدًا' : 'آجل',
                  fontSize: settings.docFontSize, lineSpacing: settings.docLineSpacing),
              pw.Divider(thickness: 0.5),
              pw.Table(
                border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey700),
                columnWidths: {
                  for (int i = 0; i < visibleCols.length; i++)
                    i: pw.FlexColumnWidth(visibleCols[i].widthFlex),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                    children: visibleCols
                        .map((c) => pw.Padding(
                              padding: const pw.EdgeInsets.all(3),
                              child: pw.Text(
                                c.label,
                                style: pw.TextStyle(
                                    font: _arabicFontBold,
                                    fontSize: settings.tableFontSize),
                                textDirection: pw.TextDirection.rtl,
                                textAlign: pw.TextAlign.center,
                              ),
                            ))
                        .toList(),
                  ),
                  for (final item in inv.items)
                    pw.TableRow(
                      children: visibleCols.map((c) {
                        String val;
                        switch (c.key) {
                          case 'productName':
                            val = item.productName;
                            break;
                          case 'quantity':
                            val = item.quantity.toString();
                            break;
                          case 'price':
                            val = item.price.toStringAsFixed(0);
                            break;
                          case 'total':
                            val = item.total.toStringAsFixed(0);
                            break;
                          default:
                            val = '';
                        }
                        return pw.Padding(
                          padding: const pw.EdgeInsets.all(3),
                          child: pw.Text(
                            val,
                            style: pw.TextStyle(
                                font: _arabicFont,
                                fontSize: settings.tableFontSize),
                            textDirection: pw.TextDirection.rtl,
                            textAlign: pw.TextAlign.center,
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Divider(thickness: 0.5),
              _kv('الإجمالي الفرعي', _currency.format(inv.subTotal),
                  fontSize: settings.docFontSize, lineSpacing: settings.docLineSpacing),
              if (inv.discountValue > 0)
                _kv('الخصم', _currency.format(inv.discountValue),
                    fontSize: settings.docFontSize, lineSpacing: settings.docLineSpacing),
              _kv('الإجمالي النهائي', _currency.format(inv.grandTotal),
                  fontSize: settings.docFontSize + 2, lineSpacing: settings.docLineSpacing),
              pw.Divider(thickness: 0.5),
              _kv('رصيد العميل بعد الفاتورة',
                  _currency.format(inv.balanceAfter),
                  fontSize: settings.docFontSize, lineSpacing: settings.docLineSpacing),
              if (inv.notes.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Text('ملاحظات:',
                    style: pw.TextStyle(font: _arabicFontBold, fontSize: 9),
                    textDirection: pw.TextDirection.rtl),
                pw.Text(inv.notes,
                    style: pw.TextStyle(font: _arabicFont, fontSize: 8),
                    textDirection: pw.TextDirection.rtl),
              ],
              if (inv.signaturePath != null &&
                  File(inv.signaturePath!).existsSync()) ...[
                pw.SizedBox(height: 8),
                pw.Text('توقيع العميل:',
                    style: pw.TextStyle(font: _arabicFont, fontSize: 8),
                    textDirection: pw.TextDirection.rtl),
                pw.Container(
                  height: 60,
                  alignment: pw.Alignment.center,
                  child: pw.Image(
                      pw.MemoryImage(File(inv.signaturePath!).readAsBytesSync())),
                ),
              ],
              pw.SizedBox(height: 6),
              if (settings.footerText.isNotEmpty)
                pw.Center(
                  child: pw.Text(settings.footerText,
                      style: pw.TextStyle(font: _arabicFont, fontSize: 8),
                      textDirection: pw.TextDirection.rtl),
                ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  Future<Uint8List> generateReceiptPdf(
      Receipt r, CompanySettings settings) async {
    await _ensureFonts();
    final df = DateFormat('yyyy/MM/dd');
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(8),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _header(settings, docTitle: 'سند قبض'),
              pw.SizedBox(height: 4),
              _kv('رقم السند', r.docNumber,
                  fontSize: settings.docFontSize, lineSpacing: settings.docLineSpacing),
              _kv('التاريخ', df.format(r.date),
                  fontSize: settings.docFontSize, lineSpacing: settings.docLineSpacing),
              _kv('العميل', r.customerName,
                  fontSize: settings.docFontSize, lineSpacing: settings.docLineSpacing),
              _kv('طريقة الدفع',
                  r.method == ReceiptMethod.cash ? 'نقدًا' : 'تحويل'),
              pw.Divider(thickness: 0.5),
              _kv('المبلغ المستلم', _currency.format(r.amount),
                  fontSize: settings.docFontSize + 3, lineSpacing: settings.docLineSpacing),
              pw.Divider(thickness: 0.5),
              _kv('رصيد العميل بعد السند', _currency.format(r.balanceAfter),
                  fontSize: settings.docFontSize, lineSpacing: settings.docLineSpacing),
              if (r.notes.isNotEmpty) ...[
                pw.SizedBox(height: 4),
                pw.Text(r.notes,
                    style: pw.TextStyle(font: _arabicFont, fontSize: 8),
                    textDirection: pw.TextDirection.rtl),
              ],
              if (r.repSignaturePath != null &&
                  File(r.repSignaturePath!).existsSync()) ...[
                pw.SizedBox(height: 8),
                pw.Text('توقيع المندوب:',
                    style: pw.TextStyle(font: _arabicFont, fontSize: 8),
                    textDirection: pw.TextDirection.rtl),
                pw.Container(
                  height: 60,
                  alignment: pw.Alignment.center,
                  child: pw.Image(pw.MemoryImage(
                      File(r.repSignaturePath!).readAsBytesSync())),
                ),
              ],
              pw.SizedBox(height: 6),
              if (settings.footerText.isNotEmpty)
                pw.Center(
                  child: pw.Text(settings.footerText,
                      style: pw.TextStyle(font: _arabicFont, fontSize: 8),
                      textDirection: pw.TextDirection.rtl),
                ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  /// كشف حساب العميل — بعكس الفاتورة/السند (80مم حراري)، يُستخدم مقاس A4
  /// عادي هنا لأن كشف الحساب قد يحتوي عشرات الصفوف ولا يُطبع على طابعة حرارية.
  Future<Uint8List> generateStatementPdf(
    String customerName,
    List<LedgerEntry> entries,
    CompanySettings settings,
  ) async {
    await _ensureFonts();
    final df = DateFormat('yyyy/MM/dd');
    final doc = pw.Document();

    String docTypeLabel(LedgerDocType t) {
      switch (t) {
        case LedgerDocType.invoiceSale:
          return 'فاتورة بيع';
        case LedgerDocType.invoiceReturn:
          return 'فاتورة مرتجع';
        case LedgerDocType.receipt:
          return 'سند قبض';
        case LedgerDocType.opening:
          return 'رصيد افتتاحي';
      }
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            _header(settings, docTitle: 'كشف حساب: $customerName'),
            pw.SizedBox(height: 8),
          ],
        ),
        build: (context) => [
          pw.Table(
            border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey700),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.3), // التاريخ
              1: pw.FlexColumnWidth(2), // البيان
              2: pw.FlexColumnWidth(1.3), // رقم المستند
              3: pw.FlexColumnWidth(1.2), // مدين
              4: pw.FlexColumnWidth(1.2), // دائن
              5: pw.FlexColumnWidth(1.4), // الرصيد
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                children: [
                  'التاريخ',
                  'البيان',
                  'رقم المستند',
                  'مدين',
                  'دائن',
                  'الرصيد',
                ]
                    .map((h) => pw.Padding(
                          padding: const pw.EdgeInsets.all(4),
                          child: pw.Text(
                            h,
                            style: pw.TextStyle(
                                font: _arabicFontBold,
                                fontSize: settings.tableFontSize),
                            textDirection: pw.TextDirection.rtl,
                            textAlign: pw.TextAlign.center,
                          ),
                        ))
                    .toList(),
              ),
              for (final e in entries)
                pw.TableRow(
                  children: [
                    df.format(e.date),
                    docTypeLabel(e.docType),
                    e.docNumber,
                    e.debit > 0 ? _currency.format(e.debit) : '-',
                    e.credit > 0 ? _currency.format(e.credit) : '-',
                    _currency.format(e.runningBalance),
                  ]
                      .map((v) => pw.Padding(
                            padding: pw.EdgeInsets.symmetric(
                                vertical: settings.rowSpacing, horizontal: 3),
                            child: pw.Text(
                              v,
                              style: pw.TextStyle(
                                  font: _arabicFont,
                                  fontSize: settings.tableFontSize),
                              textDirection: pw.TextDirection.rtl,
                              textAlign: pw.TextAlign.center,
                            ),
                          ))
                      .toList(),
                ),
            ],
          ),
          pw.SizedBox(height: 12),
          if (entries.isNotEmpty)
            _kv('الرصيد الحالي', _currency.format(entries.last.runningBalance),
                fontSize: 12),
          if (settings.footerText.isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(settings.footerText,
                  style: pw.TextStyle(font: _arabicFont, fontSize: 9),
                  textDirection: pw.TextDirection.rtl),
            ),
          ],
        ],
      ),
    );
    return doc.save();
  }

  String _docTypeLabel(LedgerDocType t) {
    switch (t) {
      case LedgerDocType.invoiceSale:
        return 'فاتورة بيع';
      case LedgerDocType.invoiceReturn:
        return 'فاتورة مرتجع';
      case LedgerDocType.receipt:
        return 'سند قبض';
      case LedgerDocType.opening:
        return 'رصيد افتتاحي';
    }
  }

  /// نسخة كشف الحساب المخصّصة للطباعة الحرارية بعرض 80مم — بنفس تصميم
  /// نسخة A4 (جدول كامل: التاريخ/البيان/رقم المستند/مدين/دائن/الرصيد)
  /// لكن بأعمدة وخط مضغوطين يتّسعان على عرض الرول الحراري، بدل نسخة
  /// مختصرة بشكل مختلف — حتى تكون الصيغتان متطابقتان بصريًا للعميل.
  Future<Uint8List> generateStatementPdf80mm(
    Customer customer,
    List<LedgerEntry> entries,
    CompanySettings settings,
  ) async {
    await _ensureFonts();
    final dfShort = DateFormat('dd/MM/yy');
    final dfFull = DateFormat('dd/MM/yyyy HH:mm');
    final doc = pw.Document();
    const cellFontSize = 6.5;

    final currentBalance = entries.isNotEmpty ? entries.last.runningBalance : 0.0;
    final balanceLabel =
        currentBalance > 0 ? 'مديون' : (currentBalance < 0 ? 'له رصيد' : 'مسوّى');

    pw.Widget cell(String text, {bool bold = false, PdfColor? color}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 1),
          child: pw.Text(
            text,
            style: pw.TextStyle(
                font: bold ? _arabicFontBold : _arabicFont,
                fontSize: cellFontSize,
                color: color),
            textDirection: pw.TextDirection.rtl,
            textAlign: pw.TextAlign.center,
          ),
        );

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(8),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _header(settings, docTitle: 'كشف حساب عميل'),
              pw.SizedBox(height: 6),
              _kv('اسم العميل', customer.name, fontSize: 9),
              if (customer.address.isNotEmpty)
                _kv('المنطقة', customer.address, fontSize: 9),
              _kv('تاريخ الكشف', dfFull.format(DateTime.now()), fontSize: 9),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 0.5),
              if (entries.isEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 10),
                  child: pw.Text('لا توجد حركات لهذا العميل',
                      style: pw.TextStyle(font: _arabicFont, fontSize: 9),
                      textDirection: pw.TextDirection.rtl,
                      textAlign: pw.TextAlign.center),
                )
              else
                pw.Table(
                  border: pw.TableBorder.all(width: 0.4, color: PdfColors.grey700),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(1.3), // التاريخ
                    1: pw.FlexColumnWidth(1.7), // البيان
                    2: pw.FlexColumnWidth(1), // رقم المستند
                    3: pw.FlexColumnWidth(1.2), // مدين
                    4: pw.FlexColumnWidth(1.2), // دائن
                    5: pw.FlexColumnWidth(1.3), // الرصيد
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                      children: [
                        cell('التاريخ', bold: true),
                        cell('البيان', bold: true),
                        cell('رقم المستند', bold: true),
                        cell('مدين', bold: true),
                        cell('دائن', bold: true),
                        cell('الرصيد', bold: true),
                      ],
                    ),
                    for (final e in entries)
                      pw.TableRow(children: [
                        cell(dfShort.format(e.date)),
                        cell(_docTypeLabel(e.docType)),
                        cell(e.docNumber),
                        cell(e.debit > 0 ? _currency.format(e.debit) : '-',
                            bold: true, color: PdfColors.red700),
                        cell(e.credit > 0 ? _currency.format(e.credit) : '-',
                            bold: true, color: PdfColors.green700),
                        cell(_currency.format(e.runningBalance)),
                      ]),
                  ],
                ),
              pw.SizedBox(height: 8),
              pw.Divider(thickness: 0.7),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(_currency.format(currentBalance.abs()),
                      style: pw.TextStyle(font: _arabicFontBold, fontSize: 11),
                      textDirection: pw.TextDirection.rtl),
                  pw.Text('الرصيد الحالي ($balanceLabel)',
                      style: pw.TextStyle(font: _arabicFontBold, fontSize: 10),
                      textDirection: pw.TextDirection.rtl),
                ],
              ),
              if (settings.footerText.isNotEmpty) ...[
                pw.SizedBox(height: 8),
                pw.Divider(thickness: 0.4),
                pw.Center(
                  child: pw.Text(settings.footerText,
                      style: pw.TextStyle(font: _arabicFont, fontSize: 8),
                      textDirection: pw.TextDirection.rtl),
                ),
              ],
            ],
          );
        },
      ),
    );
    return doc.save();
  }


  /// صفحة اختبار طباعة قصيرة للتأكد من عمل الطابعة الحرارية فعليًا قبل
  /// الاعتماد عليها بفاتورة حقيقية.
  Future<Uint8List> generateTestPrint(CompanySettings settings) async {
    await _ensureFonts();
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(10),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text('اختبار طباعة',
                style: pw.TextStyle(font: _arabicFontBold, fontSize: 14),
                textDirection: pw.TextDirection.rtl),
            pw.SizedBox(height: 8),
            pw.Text(settings.companyName,
                style: pw.TextStyle(font: _arabicFont, fontSize: 10),
                textDirection: pw.TextDirection.rtl),
            pw.SizedBox(height: 4),
            pw.Text('لو وصلتك هذه الورقة بوضوح فالطابعة تعمل بنجاح',
                style: pw.TextStyle(font: _arabicFont, fontSize: 9),
                textDirection: pw.TextDirection.rtl,
                textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 0.5),
            pw.Text('أبجد هوز حطي كلمن سعفص قرشت ثخذ ضظغ',
                style: pw.TextStyle(font: _arabicFont, fontSize: 9),
                textDirection: pw.TextDirection.rtl,
                textAlign: pw.TextAlign.center),
          ],
        ),
      ),
    );
    return doc.save();
  }
}
