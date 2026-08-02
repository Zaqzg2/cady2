import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:typed_data';

import '../models/customer.dart';
import '../models/ledger_entry.dart';
import '../models/invoice.dart';
import '../providers/app_provider.dart';
import '../services/pdf_service.dart';
import '../services/print_service.dart';
import '../services/document_output_service.dart';
import '../utils/formatters.dart';
import '../widgets/document_actions_row.dart';
import 'invoice_screen.dart';
import 'receipt_screen.dart';
import 'pdf_preview_screen.dart';

/// كشف حساب العميل:
/// - عين سريعة على كل حركة: معاينة PDF فورية بورقة سفلية بدون مغادرة الشاشة.
/// - تاب على البطاقة: تُعيّن كـ"نشطة" ويظهر رف إجراءات لاصق أسفل الشاشة.
/// - ضغط مطوّل: تفعيل وضع تحديد متعدد لطباعة/مشاركة عدة مستندات دفعة واحدة.
/// - شريط عائم ذكي (سند قبض / مرتجع / فاتورة بيع) يختفي أثناء النزول
///   بالتمرير ويظهر فورًا عند الصعود.
class CustomerStatementScreen extends StatefulWidget {
  final Customer customer;
  const CustomerStatementScreen({super.key, required this.customer});

  @override
  State<CustomerStatementScreen> createState() => _CustomerStatementScreenState();
}

class _CustomerStatementScreenState extends State<CustomerStatementScreen> {
  List<LedgerEntry> _entries = [];
  bool _loading = true;

  /// صيغة إخراج كشف الحساب الكامل (من أيقونات شريط العنوان): A4 أو 80مم.
  bool _format80mm = false;

  // ---------------- وضع التحديد المتعدد ----------------
  bool _selecting = false;
  final Set<String> _selectedIds = {};

  // ---------------- رف الإجراءات اللاصق ----------------
  LedgerEntry? _activeEntry;

  // ---------------- الشريط العائم الذكي ----------------
  final ScrollController _scrollController = ScrollController();
  bool _fabVisible = true;
  double _lastOffset = 0;

  @override
  void initState() {
    super.initState();
    _reload();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    if (offset > _lastOffset && offset > 40 && _fabVisible) {
      setState(() => _fabVisible = false);
    } else if (offset < _lastOffset && !_fabVisible) {
      setState(() => _fabVisible = true);
    }
    _lastOffset = offset;
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final entries =
        await context.read<AppProvider>().getCustomerStatement(widget.customer.id);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  // ---------------- إخراج كشف الحساب الكامل ----------------
  Future<Uint8List> _buildStatementBytes() async {
    final app = context.read<AppProvider>();
    return _format80mm
        ? PdfService.instance
            .generateStatementPdf80mm(widget.customer.name, _entries, app.settings)
        : PdfService.instance
            .generateStatementPdf(widget.customer.name, _entries, app.settings);
  }

  Future<void> _previewStatement() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPreviewScreen(
          title: 'كشف حساب ${widget.customer.name}',
          shareFileName: 'كشف_حساب_${widget.customer.name}.pdf',
          buildPdf: _buildStatementBytes,
        ),
      ),
    );
  }

  Future<void> _printStatement() async {
    final bytes = await _buildStatementBytes();
    if (_format80mm) {
      final ok = await PrintService.instance.printPdfBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(ok ? 'تمت الطباعة' : 'تعذّر الاتصال بالطابعة — تحقق من الإعدادات')));
    } else {
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    }
  }

  Future<void> _shareStatement() async {
    final bytes = await _buildStatementBytes();
    final dir = await getApplicationDocumentsDirectory();
    final suffix = _format80mm ? '_80mm' : '_A4';
    final file = File('${dir.path}/كشف_حساب_${widget.customer.name}$suffix.pdf');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)], text: 'كشف حساب ${widget.customer.name}'));
  }

  // ---------------- إخراج مستند مفرد (فاتورة/سند) لحركة واحدة ----------------
  bool _hasDoc(LedgerEntry e) => e.docType != LedgerDocType.opening;

  Future<Uint8List?> _bytesForEntry(LedgerEntry e) async {
    final app = context.read<AppProvider>();
    if (e.docType == LedgerDocType.invoiceSale ||
        e.docType == LedgerDocType.invoiceReturn) {
      final inv = await app.getInvoiceById(e.docId);
      if (inv == null) return null;
      return DocumentOutputService.instance.bytesForInvoice(inv, app.settings);
    } else if (e.docType == LedgerDocType.receipt) {
      final r = await app.getReceiptById(e.docId);
      if (r == null) return null;
      return DocumentOutputService.instance.bytesForReceipt(r, app.settings);
    }
    return null;
  }

  Future<void> _printEntry(LedgerEntry e) async {
    final bytes = await _bytesForEntry(e);
    if (bytes == null || !mounted) return;
    final ok = await PrintService.instance.printPdfBytes(bytes);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? 'تمت الطباعة' : 'تعذّر الاتصال بالطابعة — تحقق من الإعدادات')));
  }

  Future<void> _shareEntry(LedgerEntry e) async {
    final bytes = await _bytesForEntry(e);
    if (bytes == null || !mounted) return;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/${e.description}_${e.docNumber}.pdf');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: '${e.description} #${e.docNumber}'));
  }

  Future<void> _downloadEntry(LedgerEntry e) async {
    final bytes = await _bytesForEntry(e);
    if (bytes == null || !mounted) return;
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'اختر مكان الحفظ',
      fileName: '${e.description}_${e.docNumber}.pdf',
      bytes: bytes,
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (outputPath == null || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('تم حفظ PDF بنجاح')));
  }

  Future<void> _openFullPreview(LedgerEntry e) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPreviewScreen(
          title: '${e.description} #${e.docNumber}',
          shareFileName: '${e.description}_${e.docNumber}.pdf',
          buildPdf: () async {
            final b = await _bytesForEntry(e);
            return b ?? Uint8List(0);
          },
        ),
      ),
    );
  }

  /// معاينة سريعة لحركة واحدة داخل ورقة سفلية بدون مغادرة كشف الحساب.
  Future<void> _quickPreview(LedgerEntry e) async {
    final bytes = await _bytesForEntry(e);
    if (bytes == null || !mounted) return;
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
              decoration: BoxDecoration(
                  color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text('معاينة سريعة: ${e.description} #${e.docNumber}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx)),
                ],
              ),
            ),
            Expanded(
              child: PdfPreview(
                build: (format) async => bytes,
                canDebug: false,
                useActions: false,
              ),
            ),
            const Divider(height: 1),
            SafeArea(
              top: false,
              child: DocumentActionsRow(
                onPrint: () {
                  Navigator.pop(ctx);
                  _printEntry(e);
                },
                onShare: () {
                  Navigator.pop(ctx);
                  _shareEntry(e);
                },
                onPreview: () {
                  Navigator.pop(ctx);
                  _openFullPreview(e);
                },
                onDownload: () {
                  Navigator.pop(ctx);
                  _downloadEntry(e);
                },
                onEdit: () {
                  Navigator.pop(ctx);
                  _openEntry(e);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- تعديل / حذف حركة ----------------
  Future<void> _openEntry(LedgerEntry e) async {
    final app = context.read<AppProvider>();
    if (e.docType == LedgerDocType.invoiceSale ||
        e.docType == LedgerDocType.invoiceReturn) {
      final inv = await app.getInvoiceById(e.docId);
      if (inv == null) return;
      if (!mounted) return;
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => InvoiceScreen(kind: inv.kind, existing: inv)));
    } else if (e.docType == LedgerDocType.receipt) {
      final r = await app.getReceiptById(e.docId);
      if (r == null) return;
      if (!mounted) return;
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => ReceiptScreen(existing: r)));
    }
    DocumentOutputService.instance.invalidate(e.docId);
    if (_activeEntry?.docId == e.docId) _activeEntry = null;
    _reload();
  }

  Future<void> _deleteEntry(LedgerEntry e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف ${e.description} رقم #${e.docNumber}؟'),
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
    DocumentOutputService.instance.invalidate(e.docId);
    if (e.docType == LedgerDocType.invoiceSale || e.docType == LedgerDocType.invoiceReturn) {
      await app.deleteInvoice(e.docId);
    } else if (e.docType == LedgerDocType.receipt) {
      await app.deleteReceipt(e.docId);
    }
    if (_activeEntry?.docId == e.docId) _activeEntry = null;
    _reload();
  }

  // ---------------- التحديد المتعدد ----------------
  void _enterSelection(LedgerEntry e) {
    if (!_hasDoc(e)) return;
    setState(() {
      _selecting = true;
      _selectedIds.add(e.docId);
    });
  }

  void _toggleSelection(LedgerEntry e) {
    if (!_hasDoc(e)) return;
    setState(() {
      if (_selectedIds.contains(e.docId)) {
        _selectedIds.remove(e.docId);
        if (_selectedIds.isEmpty) _selecting = false;
      } else {
        _selectedIds.add(e.docId);
      }
    });
  }

  void _exitSelection() => setState(() {
        _selecting = false;
        _selectedIds.clear();
      });

  Future<void> _printSelected() async {
    final selected = _entries.where((e) => _selectedIds.contains(e.docId)).toList();
    var success = 0;
    for (final e in selected) {
      final bytes = await _bytesForEntry(e);
      if (bytes == null) continue;
      final ok = await PrintService.instance.printPdfBytes(bytes);
      if (ok) success++;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('تمت طباعة $success من ${selected.length}')));
    _exitSelection();
  }

  Future<void> _shareSelected() async {
    final selected = _entries.where((e) => _selectedIds.contains(e.docId)).toList();
    final dir = await getApplicationDocumentsDirectory();
    final files = <XFile>[];
    for (final e in selected) {
      final bytes = await _bytesForEntry(e);
      if (bytes == null) continue;
      final file = File('${dir.path}/${e.description}_${e.docNumber}.pdf');
      await file.writeAsBytes(bytes);
      files.add(XFile(file.path));
    }
    if (files.isEmpty || !mounted) return;
    await SharePlus.instance
        .share(ShareParams(files: files, text: 'مستندات ${widget.customer.name}'));
    _exitSelection();
  }

  // ---------------- فتح فاتورة/سند جديد لنفس العميل مباشرة ----------------
  Future<void> _newDoc({bool receipt = false, InvoiceKind? kind}) async {
    if (receipt) {
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => ReceiptScreen(presetCustomer: widget.customer)));
    } else if (kind != null) {
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => InvoiceScreen(kind: kind, presetCustomer: widget.customer)));
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _selecting ? _selectionAppBar() : _normalAppBar(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? const Center(child: Text('لا توجد حركات لهذا العميل'))
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.only(bottom: 8),
                  itemCount: _entries.length,
                  itemBuilder: (ctx, i) => _entryCard(_entries[i]),
                ),
      bottomNavigationBar: _bottomDock(),
      floatingActionButton: _selecting ? null : _smartFab(),
    );
  }

  AppBar _normalAppBar() {
    return AppBar(
      title: Text('كشف حساب: ${widget.customer.name}'),
      actions: [
        IconButton(
            icon: const Icon(Icons.visibility_outlined),
            tooltip: 'معاينة',
            onPressed: _previewStatement),
        IconButton(icon: const Icon(Icons.print), tooltip: 'طباعة', onPressed: _printStatement),
        IconButton(icon: const Icon(Icons.share), tooltip: 'مشاركة', onPressed: _shareStatement),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(44),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Center(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                    value: false,
                    label: Text('A4'),
                    icon: Icon(Icons.description_outlined, size: 16)),
                ButtonSegment(
                    value: true,
                    label: Text('80مم حراري'),
                    icon: Icon(Icons.receipt_long, size: 16)),
              ],
              selected: {_format80mm},
              onSelectionChanged: (s) => setState(() => _format80mm = s.first),
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ),
      ),
    );
  }

  AppBar _selectionAppBar() {
    return AppBar(
      leading: IconButton(icon: const Icon(Icons.close), onPressed: _exitSelection),
      title: Text('${_selectedIds.length} محدد'),
      actions: [
        IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'طباعة الكل',
            onPressed: _selectedIds.isEmpty ? null : _printSelected),
        IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'مشاركة الكل',
            onPressed: _selectedIds.isEmpty ? null : _shareSelected),
      ],
    );
  }

  Widget _entryCard(LedgerEntry e) {
    final selected = _selectedIds.contains(e.docId);
    final isDebit = e.debit > 0;
    final amount = isDebit ? e.debit : e.credit;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      color: selected ? Colors.indigo.shade50 : null,
      child: InkWell(
        onTap: () {
          if (_selecting) {
            _toggleSelection(e);
          } else {
            setState(() => _activeEntry = e);
          }
        },
        onLongPress: () => _enterSelection(e),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              if (_selecting)
                Checkbox(
                  value: selected,
                  onChanged: _hasDoc(e) ? (_) => _toggleSelection(e) : null,
                )
              else
                CircleAvatar(
                  backgroundColor: (isDebit ? Colors.red : Colors.green).withOpacity(0.12),
                  child: Icon(
                    e.docType == LedgerDocType.opening
                        ? Icons.flag_outlined
                        : (isDebit ? Icons.point_of_sale : Icons.payments),
                    color: isDebit ? Colors.red : Colors.green,
                    size: 20,
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${e.description}${e.docNumber != '-' ? '  #${e.docNumber}' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text('${Formatters.d(e.date)}  •  الرصيد: ${Formatters.money(e.runningBalance)}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isDebit ? '+' : '-'}${Formatters.money(amount)}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isDebit ? Colors.red : Colors.green),
                  ),
                  if (_hasDoc(e) && !_selecting)
                    InkWell(
                      onTap: () => _quickPreview(e),
                      borderRadius: BorderRadius.circular(20),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.visibility_outlined, size: 18, color: Colors.indigo),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _bottomDock() {
    if (_selecting) return null;
    final e = _activeEntry;
    if (e == null || !_hasDoc(e)) return null;
    return Material(
      elevation: 10,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${e.description} #${e.docNumber}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              DocumentActionsRow(
                compact: true,
                onPrint: () => _printEntry(e),
                onShare: () => _shareEntry(e),
                onPreview: () => _quickPreview(e),
                onDownload: () => _downloadEntry(e),
                onEdit: () => _openEntry(e),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _activeEntry = null),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                onPressed: () => _deleteEntry(e),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _smartFab() {
    return AnimatedSlide(
      duration: const Duration(milliseconds: 200),
      offset: _fabVisible ? Offset.zero : const Offset(0, 2),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: _fabVisible ? 1 : 0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton.extended(
              heroTag: 'fab_receipt',
              onPressed: () => _newDoc(receipt: true),
              icon: const Icon(Icons.payments),
              label: const Text('سند قبض'),
              backgroundColor: Colors.amber.shade700,
            ),
            const SizedBox(height: 10),
            FloatingActionButton.extended(
              heroTag: 'fab_return',
              onPressed: () => _newDoc(kind: InvoiceKind.saleReturn),
              icon: const Icon(Icons.assignment_return),
              label: const Text('مرتجع'),
              backgroundColor: Colors.red.shade400,
            ),
            const SizedBox(height: 10),
            FloatingActionButton.extended(
              heroTag: 'fab_sale',
              onPressed: () => _newDoc(kind: InvoiceKind.sale),
              icon: const Icon(Icons.point_of_sale),
              label: const Text('فاتورة بيع'),
              backgroundColor: Colors.green.shade600,
            ),
          ],
        ),
      ),
    );
  }
}
