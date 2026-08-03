import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/customer.dart';
import '../models/doc_row.dart';
import '../providers/app_provider.dart';
import '../screens/customer_profile_screen.dart';
import '../screens/invoice_screen.dart';
import '../screens/pdf_preview_screen.dart';
import '../screens/receipt_screen.dart';
import '../services/document_output_service.dart';
import '../services/print_service.dart';
import '../widgets/document_actions_row.dart';

/// إجراءات مشتركة على صف مستند واحد (فاتورة/سند): طباعة، مشاركة، تحميل،
/// معاينة، فتح للتعديل، تكرار، حذف، تثبيت، وفتح كشف الحساب بعد العملية.
/// تُستخدم في سجل الفواتير والسندات وفي قسم "آخر العمليات" بالصفحة
/// الرئيسية لتفادي تكرار نفس المنطق في أكثر من شاشة.
mixin DocumentRowActions<T extends StatefulWidget> on State<T> {
  void snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<Uint8List> bytesFor(DocRow row) async {
    final settings = context.read<AppProvider>().settings;
    if (row.invoice != null) {
      return DocumentOutputService.instance.bytesForInvoice(row.invoice!, settings);
    }
    return DocumentOutputService.instance.bytesForReceipt(row.receipt!, settings);
  }

  Future<void> markPrinted(DocRow row) async {
    final app = context.read<AppProvider>();
    if (row.invoice != null && !row.invoice!.printed) {
      row.invoice!.printed = true;
      await app.updateInvoiceFlags(row.invoice!);
    } else if (row.receipt != null && !row.receipt!.printed) {
      row.receipt!.printed = true;
      await app.updateReceiptFlags(row.receipt!);
    }
  }

  Future<void> markShared(DocRow row) async {
    final app = context.read<AppProvider>();
    if (row.invoice != null && !row.invoice!.shared) {
      row.invoice!.shared = true;
      await app.updateInvoiceFlags(row.invoice!);
    } else if (row.receipt != null && !row.receipt!.shared) {
      row.receipt!.shared = true;
      await app.updateReceiptFlags(row.receipt!);
    }
  }

  Future<void> togglePinRow(DocRow row) async {
    final app = context.read<AppProvider>();
    if (row.invoice != null) {
      row.invoice!.pinned = !row.invoice!.pinned;
      await app.updateInvoiceFlags(row.invoice!);
    } else if (row.receipt != null) {
      row.receipt!.pinned = !row.receipt!.pinned;
      await app.updateReceiptFlags(row.receipt!);
    }
  }

  Future<void> printRow(DocRow row, {VoidCallback? onDone}) async {
    final bytes = await bytesFor(row);
    final ok = await PrintService.instance.printPdfBytes(bytes);
    if (ok) await markPrinted(row);
    if (!mounted) return;
    snack(ok ? 'تمت الطباعة' : 'تعذّر الاتصال بالطابعة — تحقق من الإعدادات');
    if (ok) onDone?.call();
  }

  Future<void> shareRow(DocRow row, {VoidCallback? onDone}) async {
    final bytes = await bytesFor(row);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/${row.title}_${row.docNumber}.pdf');
    await file.writeAsBytes(bytes);
    await SharePlus.instance
        .share(ShareParams(files: [XFile(file.path)], text: '${row.title} #${row.docNumber}'));
    await markShared(row);
    onDone?.call();
  }

  Future<void> downloadRow(DocRow row) async {
    final bytes = await bytesFor(row);
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'اختر مكان الحفظ',
      fileName: '${row.title}_${row.docNumber}.pdf',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (outputPath == null || !mounted) return;
    snack('تم حفظ PDF بنجاح');
  }

  Future<void> previewRowFull(DocRow row) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPreviewScreen(
          title: '${row.title} #${row.docNumber}',
          shareFileName: '${row.title}_${row.docNumber}.pdf',
          buildPdf: () => bytesFor(row),
        ),
      ),
    );
  }

  Future<void> quickPreviewRow(DocRow row, {VoidCallback? onDone}) async {
    final bytes = await bytesFor(row);
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.8,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration:
                  BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text('معاينة سريعة: ${row.title} #${row.docNumber}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
            ),
            Expanded(
              child: PdfPreview(build: (format) async => bytes, canDebug: false, useActions: false),
            ),
            const Divider(height: 1),
            SafeArea(
              top: false,
              child: DocumentActionsRow(
                onPrint: () {
                  Navigator.pop(ctx);
                  printRow(row, onDone: onDone);
                },
                onShare: () {
                  Navigator.pop(ctx);
                  shareRow(row, onDone: onDone);
                },
                onPreview: () {
                  Navigator.pop(ctx);
                  previewRowFull(row);
                },
                onDownload: () {
                  Navigator.pop(ctx);
                  downloadRow(row);
                },
                onEdit: () {
                  Navigator.pop(ctx);
                  editRow(row, onDone: onDone);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> editRow(DocRow row, {VoidCallback? onDone}) async {
    if (row.invoice != null) {
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => InvoiceScreen(kind: row.invoice!.kind, existing: row.invoice)));
    } else if (row.receipt != null) {
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => ReceiptScreen(existing: row.receipt)));
    }
    DocumentOutputService.instance.invalidate(row.docId);
    onDone?.call();
  }

  Future<void> duplicateRow(DocRow row, {VoidCallback? onDone}) async {
    if (row.invoice != null) {
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => InvoiceScreen(kind: row.invoice!.kind, duplicateFrom: row.invoice)));
    } else if (row.receipt != null) {
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => ReceiptScreen(duplicateFrom: row.receipt)));
    }
    onDone?.call();
  }

  Future<void> openStatementAfter(DocRow row) async {
    final app = context.read<AppProvider>();
    final customer = app.customers.firstWhere((c) => c.id == row.customerId,
        orElse: () => Customer(id: row.customerId, name: row.customerName));
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => CustomerProfileScreen(customer: customer)));
  }

  Future<void> confirmDeleteRow(DocRow row, {VoidCallback? onDone}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف ${row.title} رقم #${row.docNumber}؟\n'
            'لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final app = context.read<AppProvider>();
    DocumentOutputService.instance.invalidate(row.docId);
    if (row.invoice != null) {
      await app.deleteInvoice(row.invoice!.id);
    } else if (row.receipt != null) {
      await app.deleteReceipt(row.receipt!.id);
    }
    onDone?.call();
  }

  void longPressMenuRow(DocRow row, {VoidCallback? onDone}) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('معاينة مصغرة'),
              onTap: () {
                Navigator.pop(ctx);
                quickPreviewRow(row, onDone: onDone);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('تعديل'),
              onTap: () {
                Navigator.pop(ctx);
                editRow(row, onDone: onDone);
              },
            ),
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('طباعة'),
              onTap: () {
                Navigator.pop(ctx);
                printRow(row, onDone: onDone);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('PDF'),
              onTap: () {
                Navigator.pop(ctx);
                previewRowFull(row);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('مشاركة'),
              onTap: () {
                Navigator.pop(ctx);
                shareRow(row, onDone: onDone);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('نسخ الرقم'),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: row.docNumber));
                snack('تم نسخ رقم المستند');
              },
            ),
            ListTile(
              leading: Icon(row.pinned ? Icons.star : Icons.star_border,
                  color: row.pinned ? Colors.amber : null),
              title: Text(row.pinned ? 'إلغاء التثبيت' : 'تثبيت بالأعلى'),
              onTap: () {
                Navigator.pop(ctx);
                togglePinRow(row).then((_) => onDone?.call());
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('حذف'),
              onTap: () {
                Navigator.pop(ctx);
                confirmDeleteRow(row, onDone: onDone);
              },
            ),
          ],
        ),
      ),
    );
  }
}
