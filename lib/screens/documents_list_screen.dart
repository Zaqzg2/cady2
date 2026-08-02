import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/invoice.dart';
import '../models/receipt.dart';
import '../providers/app_provider.dart';
import '../services/db_service.dart';
import '../services/document_output_service.dart';
import '../services/print_service.dart';
import '../utils/formatters.dart';
import '../widgets/document_actions_row.dart';
import 'invoice_screen.dart';
import 'pdf_preview_screen.dart';
import 'receipt_screen.dart';

/// سجل موحّد لكل الفواتير والسندات.
/// - تاب على البطاقة: توسّعها inline وتُظهر شريط الإجراءات الخمسة
///   (طباعة/مشاركة/معاينة/تحميل/تعديل) بدون مغادرة الشاشة.
/// - سحب يمين: طباعة + مشاركة (أخضر) — الإجراءات الآمنة الأكثر استخدامًا.
/// - سحب يسار: تعديل + حذف (أحمر) — مع تأكيد قبل الحذف.
class DocumentsListScreen extends StatefulWidget {
  const DocumentsListScreen({super.key});

  @override
  State<DocumentsListScreen> createState() => _DocumentsListScreenState();
}

class _DocumentsListScreenState extends State<DocumentsListScreen> {
  String _filter = 'all'; // all / sale / return / receipt
  List<Invoice> _invoices = [];
  List<Receipt> _receipts = [];
  bool _loading = true;
  String? _expandedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _invoices = await DbService.instance.getInvoices();
    _receipts = await DbService.instance.getReceipts();
    setState(() => _loading = false);
  }

  Future<void> _confirmDelete(_DocRow row) async {
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
    if (_expandedId == row.docId) _expandedId = null;
    _load();
  }

  Future<void> _editRow(_DocRow row) async {
    if (row.invoice != null) {
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  InvoiceScreen(kind: row.invoice!.kind, existing: row.invoice)));
    } else if (row.receipt != null) {
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => ReceiptScreen(existing: row.receipt)));
    }
    DocumentOutputService.instance.invalidate(row.docId);
    _load();
  }

  Future<Uint8List> _bytesFor(_DocRow row) async {
    final settings = context.read<AppProvider>().settings;
    if (row.invoice != null) {
      return DocumentOutputService.instance.bytesForInvoice(row.invoice!, settings);
    }
    return DocumentOutputService.instance.bytesForReceipt(row.receipt!, settings);
  }

  Future<void> _printRow(_DocRow row) async {
    final bytes = await _bytesFor(row);
    final ok = await PrintService.instance.printPdfBytes(bytes);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'تمت الطباعة' : 'تعذّر الاتصال بالطابعة — تحقق من الإعدادات')));
  }

  Future<void> _shareRow(_DocRow row) async {
    final bytes = await _bytesFor(row);
    final dir = await getApplicationDocumentsDirectory();
    final fileName = '${row.title}_${row.docNumber}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    await SharePlus.instance
        .share(ShareParams(files: [XFile(file.path)], text: '${row.title} #${row.docNumber}'));
  }

  Future<void> _downloadRow(_DocRow row) async {
    final bytes = await _bytesFor(row);
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'اختر مكان الحفظ',
      fileName: '${row.title}_${row.docNumber}.pdf',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (outputPath == null || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('تم حفظ PDF بنجاح')));
  }

  Future<void> _previewRow(_DocRow row) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPreviewScreen(
          title: '${row.title} #${row.docNumber}',
          shareFileName: '${row.title}_${row.docNumber}.pdf',
          buildPdf: () => _bytesFor(row),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = <_DocRow>[
      if (_filter == 'all' || _filter == 'sale' || _filter == 'return')
        ..._invoices
            .where((i) => _filter == 'all' ||
                (_filter == 'sale' && i.kind == InvoiceKind.sale) ||
                (_filter == 'return' && i.kind == InvoiceKind.saleReturn))
            .map((i) => _DocRow.invoice(i)),
      if (_filter == 'all' || _filter == 'receipt')
        ..._receipts.map((r) => _DocRow.receipt(r)),
    ]..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل السندات والفواتير'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('all', 'الكل'),
                  _filterChip('sale', 'فواتير بيع'),
                  _filterChip('return', 'فواتير مرتجع'),
                  _filterChip('receipt', 'سندات قبض'),
                ],
              ),
            ),
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(child: Text('لا توجد مستندات بعد'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final row = items[i];
                    final expanded = _expandedId == row.docId;
                    return Slidable(
                      key: ValueKey(row.docId),
                      // سحب من الحافة اليمنى (في RTL) يكشف: طباعة + مشاركة
                      startActionPane: ActionPane(
                        motion: const DrawerMotion(),
                        extentRatio: 0.42,
                        children: [
                          SlidableAction(
                            onPressed: (_) => _printRow(row),
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            icon: Icons.print_outlined,
                            label: 'طباعة',
                          ),
                          SlidableAction(
                            onPressed: (_) => _shareRow(row),
                            backgroundColor: Colors.green.shade400,
                            foregroundColor: Colors.white,
                            icon: Icons.share_outlined,
                            label: 'مشاركة',
                          ),
                        ],
                      ),
                      // سحب من الحافة اليسرى يكشف: تعديل + حذف
                      endActionPane: ActionPane(
                        motion: const DrawerMotion(),
                        extentRatio: 0.42,
                        children: [
                          SlidableAction(
                            onPressed: (_) => _editRow(row),
                            backgroundColor: Colors.blueGrey.shade400,
                            foregroundColor: Colors.white,
                            icon: Icons.edit_outlined,
                            label: 'تعديل',
                          ),
                          SlidableAction(
                            onPressed: (_) => _confirmDelete(row),
                            backgroundColor: Colors.red.shade600,
                            foregroundColor: Colors.white,
                            icon: Icons.delete_outline,
                            label: 'حذف',
                          ),
                        ],
                      ),
                      child: Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            InkWell(
                              onTap: () => setState(
                                  () => _expandedId = expanded ? null : row.docId),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: row.color.withOpacity(0.15),
                                  child: Icon(row.icon, color: row.color),
                                ),
                                title: Text('${row.title}  #${row.docNumber}'),
                                subtitle:
                                    Text('${row.customerName} • ${Formatters.d(row.date)}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(Formatters.money(row.amount),
                                        style: const TextStyle(fontWeight: FontWeight.bold)),
                                    Icon(expanded
                                        ? Icons.expand_less
                                        : Icons.expand_more),
                                  ],
                                ),
                              ),
                            ),
                            AnimatedCrossFade(
                              duration: const Duration(milliseconds: 200),
                              crossFadeState: expanded
                                  ? CrossFadeState.showFirst
                                  : CrossFadeState.showSecond,
                              firstChild: Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.surfaceVariant
                                      .withOpacity(0.4),
                                  border: Border(
                                      top: BorderSide(color: Colors.grey.shade300)),
                                ),
                                child: DocumentActionsRow(
                                  onPrint: () => _printRow(row),
                                  onShare: () => _shareRow(row),
                                  onPreview: () => _previewRow(row),
                                  onDownload: () => _downloadRow(row),
                                  onEdit: () => _editRow(row),
                                ),
                              ),
                              secondChild: const SizedBox(width: double.infinity),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _filterChip(String value, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: ChoiceChip(
        label: Text(label),
        selected: _filter == value,
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }
}

class _DocRow {
  final DateTime date;
  final String title;
  final String docNumber;
  final String docId;
  final String customerName;
  final double amount;
  final Color color;
  final IconData icon;
  final Invoice? invoice;
  final Receipt? receipt;

  _DocRow({
    required this.date,
    required this.title,
    required this.docNumber,
    required this.docId,
    required this.customerName,
    required this.amount,
    required this.color,
    required this.icon,
    this.invoice,
    this.receipt,
  });

  factory _DocRow.invoice(Invoice i) => _DocRow(
        date: i.date,
        title: i.kind == InvoiceKind.sale ? 'فاتورة بيع' : 'فاتورة مرتجع',
        docNumber: i.docNumber,
        docId: i.id,
        customerName: i.customerName,
        amount: i.grandTotal,
        color: i.kind == InvoiceKind.sale ? Colors.green : Colors.red,
        icon: i.kind == InvoiceKind.sale ? Icons.point_of_sale : Icons.assignment_return,
        invoice: i,
      );

  factory _DocRow.receipt(Receipt r) => _DocRow(
        date: r.date,
        title: 'سند قبض',
        docNumber: r.docNumber,
        docId: r.id,
        customerName: r.customerName,
        amount: r.amount,
        color: Colors.amber.shade800,
        icon: Icons.payments,
        receipt: r,
      );
}
