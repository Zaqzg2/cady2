import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/customer.dart';
import '../models/customer_note.dart';
import '../models/customer_summary.dart';
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
import 'customer_statement_screen.dart';

/// صفحة العميل: بديل عن كشف الحساب المجرّد — رأس بمعلومات العميل، مؤشرات
/// سريعة، إجراءات كشف الحساب، وسجل نشاط زمني موحّد يجمع الفواتير والسندات
/// والملاحظات، مع زر عائم واحد يفتح قائمة إجراءات الإضافة.
class CustomerProfileScreen extends StatefulWidget {
  final Customer customer;
  const CustomerProfileScreen({super.key, required this.customer});

  @override
  State<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends State<CustomerProfileScreen> {
  late Customer _customer;
  List<LedgerEntry> _entries = [];
  List<CustomerNote> _notes = [];
  CustomerSummary? _summary;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final app = context.read<AppProvider>();
    final entries = await app.getCustomerStatement(_customer.id);
    final notes = await app.getCustomerNotes(_customer.id);
    final summary = await app.getCustomerSummary(_customer.id);
    final fresh = app.customers.firstWhere((c) => c.id == _customer.id,
        orElse: () => _customer);
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _notes = notes;
      _summary = summary;
      _customer = fresh;
      _loading = false;
    });
  }

  // ---------------- اتصال / واتساب ----------------
  Future<void> _call() async {
    if (_customer.phone.trim().isEmpty) {
      _snack('لا يوجد رقم هاتف مسجل لهذا العميل');
      return;
    }
    final uri = Uri(scheme: 'tel', path: _customer.phone.trim());
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _whatsapp({String? text}) async {
    if (_customer.phone.trim().isEmpty) {
      _snack('لا يوجد رقم هاتف مسجل لهذا العميل');
      return;
    }
    final digits = _customer.phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse(
        'https://wa.me/$digits${text != null ? '?text=${Uri.encodeComponent(text)}' : ''}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      _snack('تعذّر فتح واتساب');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _togglePin() async {
    await context.read<AppProvider>().togglePinned(_customer);
    _reload();
  }

  // ---------------- كشف الحساب الكامل ----------------
  Future<Uint8List> _buildStatementBytes() async {
    final app = context.read<AppProvider>();
    return PdfService.instance
        .generateStatementPdf(_customer.name, _entries, app.settings);
  }

  Future<void> _previewStatement() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPreviewScreen(
          title: 'كشف حساب ${_customer.name}',
          shareFileName: 'كشف_حساب_${_customer.name}.pdf',
          buildPdf: _buildStatementBytes,
        ),
      ),
    );
  }

  Future<void> _printStatement() async {
    final bytes = await _buildStatementBytes();
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  Future<void> _shareStatement() async {
    final bytes = await _buildStatementBytes();
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/كشف_حساب_${_customer.name}.pdf');
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'كشف حساب ${_customer.name}'));
  }

  void _openFullStatement() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => CustomerStatementScreen(customer: _customer)));
  }

  // ---------------- مستند مفرد (فاتورة/سند) ----------------
  bool _hasDoc(LedgerEntry e) => e.docType != LedgerDocType.opening;

  Future<Uint8List?> _bytesForEntry(LedgerEntry e) async {
    final app = context.read<AppProvider>();
    if (e.docType == LedgerDocType.invoiceSale || e.docType == LedgerDocType.invoiceReturn) {
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
    _snack(ok ? 'تمت الطباعة' : 'تعذّر الاتصال بالطابعة — تحقق من الإعدادات');
    if (ok) await _markFlag(e, printed: true);
  }

  Future<void> _shareEntry(LedgerEntry e) async {
    final bytes = await _bytesForEntry(e);
    if (bytes == null || !mounted) return;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/${e.description}_${e.docNumber}.pdf');
    await file.writeAsBytes(bytes);
    await SharePlus.instance
        .share(ShareParams(files: [XFile(file.path)], text: '${e.description} #${e.docNumber}'));
    await _markFlag(e, shared: true);
  }

  /// يحدّث حالتي "مطبوع/مُرسل" على الفاتورة أو السند نفسه (تظهر كشارات
  /// في سجل الفواتير والسندات وقسم "آخر العمليات" بالصفحة الرئيسية).
  Future<void> _markFlag(LedgerEntry e, {bool? printed, bool? shared}) async {
    final app = context.read<AppProvider>();
    if (e.docType == LedgerDocType.invoiceSale || e.docType == LedgerDocType.invoiceReturn) {
      final inv = await app.getInvoiceById(e.docId);
      if (inv == null) return;
      if (printed != null) inv.printed = printed;
      if (shared != null) inv.shared = shared;
      await app.updateInvoiceFlags(inv);
    } else if (e.docType == LedgerDocType.receipt) {
      final r = await app.getReceiptById(e.docId);
      if (r == null) return;
      if (printed != null) r.printed = printed;
      if (shared != null) r.shared = shared;
      await app.updateReceiptFlags(r);
    }
  }

  Future<void> _whatsappEntry(LedgerEntry e) async {
    await _whatsapp(text: '${e.description} #${e.docNumber}');
  }

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
                  _shareEntry(e);
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

  Future<void> _openFullPreview(LedgerEntry e) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPreviewScreen(
          title: '${e.description} #${e.docNumber}',
          shareFileName: '${e.description}_${e.docNumber}.pdf',
          buildPdf: () async => (await _bytesForEntry(e)) ?? Uint8List(0),
        ),
      ),
    );
  }

  Future<void> _openEntry(LedgerEntry e) async {
    final app = context.read<AppProvider>();
    if (e.docType == LedgerDocType.invoiceSale || e.docType == LedgerDocType.invoiceReturn) {
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
    _reload();
  }

  Future<void> _duplicateEntry(LedgerEntry e) async {
    final app = context.read<AppProvider>();
    if (e.docType == LedgerDocType.invoiceSale || e.docType == LedgerDocType.invoiceReturn) {
      final inv = await app.getInvoiceById(e.docId);
      if (inv == null || !mounted) return;
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => InvoiceScreen(kind: inv.kind, duplicateFrom: inv)));
    } else if (e.docType == LedgerDocType.receipt) {
      final r = await app.getReceiptById(e.docId);
      if (r == null || !mounted) return;
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => ReceiptScreen(duplicateFrom: r)));
    }
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
    _reload();
  }

  // ---------------- ملاحظات ----------------
  Future<void> _addNote() async {
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ملاحظة جديدة'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'اكتب ملاحظة عن هذا العميل...'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('حفظ')),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    await context.read<AppProvider>().addCustomerNote(_customer.id, text);
    _reload();
  }

  Future<void> _deleteNote(CustomerNote n) async {
    await context.read<AppProvider>().deleteCustomerNote(n.id);
    _reload();
  }

  // ---------------- فتح مستند جديد ----------------
  Future<void> _newDoc({bool receipt = false, InvoiceKind? kind}) async {
    if (receipt) {
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => ReceiptScreen(presetCustomer: _customer)));
    } else if (kind != null) {
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => InvoiceScreen(kind: kind, presetCustomer: _customer)));
    }
    _reload();
  }

  void _showAddMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.point_of_sale, color: Colors.green),
              title: const Text('فاتورة بيع'),
              onTap: () {
                Navigator.pop(ctx);
                _newDoc(kind: InvoiceKind.sale);
              },
            ),
            ListTile(
              leading: Icon(Icons.payments, color: Colors.amber.shade800),
              title: const Text('سند قبض'),
              onTap: () {
                Navigator.pop(ctx);
                _newDoc(receipt: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.assignment_return, color: Colors.red),
              title: const Text('مرتجع'),
              onTap: () {
                Navigator.pop(ctx);
                _newDoc(kind: InvoiceKind.saleReturn);
              },
            ),
            ListTile(
              leading: const Icon(Icons.sticky_note_2_outlined, color: Colors.indigo),
              title: const Text('ملاحظة'),
              onTap: () {
                Navigator.pop(ctx);
                _addNote();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_customer.name),
        actions: [
          IconButton(
            icon: Icon(_customer.isPinned ? Icons.star : Icons.star_border,
                color: _customer.isPinned ? Colors.amber : null),
            tooltip: _customer.isPinned ? 'إلغاء التثبيت' : 'تثبيت',
            onPressed: _togglePin,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                children: [
                  _header(),
                  const SizedBox(height: 12),
                  _indicatorCards(),
                  const SizedBox(height: 12),
                  _quickActions(),
                  const SizedBox(height: 18),
                  Text('سجل النشاط',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ..._timelineWidgets(),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddMenu,
        child: const Icon(Icons.add),
      ),
    );
  }

  // ---------------- الرأس ----------------
  Widget _header() {
    final balance = _summary?.balance ?? _customer.openingBalance;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.primaries[_customer.name.hashCode % Colors.primaries.length]
                      .shade100,
                  foregroundColor:
                      Colors.primaries[_customer.name.hashCode % Colors.primaries.length].shade800,
                  child: Text(
                    _customer.name.trim().isNotEmpty ? _customer.name.trim()[0] : '؟',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_customer.name,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _customer.isStopped ? Colors.grey.shade400 : Colors.green,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(_customer.isStopped ? 'متوقف' : 'نشط',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                          const SizedBox(width: 10),
                          Icon(Icons.schedule, size: 13, color: Colors.grey.shade600),
                          const SizedBox(width: 3),
                          Text('آخر زيارة: ${_summary?.lastActivityLabel ?? '...'}',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('الرصيد',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                const SizedBox(width: 8),
                Text(
                  Formatters.money(balance),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: balance > 0
                        ? Colors.red.shade600
                        : balance < 0
                            ? Colors.green.shade700
                            : Colors.grey.shade700,
                  ),
                ),
              ],
            ),
            if (_customer.creditLimit > 0) ...[
              const SizedBox(height: 8),
              _creditLimitBar(balance, _customer.creditLimit),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                _contactIcon(Icons.call, 'اتصال', _call),
                _contactIcon(Icons.chat, 'واتساب', () => _whatsapp()),
                if (_customer.address.trim().isNotEmpty)
                  _contactIcon(Icons.location_on_outlined, 'العنوان',
                      () => _showAddress(_customer.address)),
                _contactIcon(
                  _customer.isPinned ? Icons.star : Icons.star_border,
                  _customer.isPinned ? 'مثبّت' : 'تثبيت',
                  _togglePin,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAddress(String address) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(address)));
  }

  Widget _creditLimitBar(double balance, double limit) {
    final ratio = (balance / limit).clamp(0.0, 1.0);
    final over = balance > limit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: Colors.grey.shade200,
            color: over ? Colors.red : Colors.orange,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'الحد الائتماني: ${Formatters.money(limit)}  •  المستخدم ${(ratio * 100).clamp(0, 100).toStringAsFixed(0)}٪',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _contactIcon(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 3),
              Text(label, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- بطاقات المؤشرات ----------------
  Widget _indicatorCards() {
    final s = _summary;
    return Row(
      children: [
        _indicatorCard('💰', 'الرصيد', s == null ? '...' : Formatters.money(s.balance),
            Colors.teal),
        _indicatorCard('🧾', 'الفواتير', s == null ? '...' : '${s.invoiceCount}', Colors.indigo),
        _indicatorCard(
            '💵', 'المقبوض', s == null ? '...' : Formatters.money(s.receivedTotal), Colors.green),
        _indicatorCard(
            '↩️', 'المرتجع', s == null ? '...' : Formatters.money(s.returnsTotal), Colors.orange),
      ],
    );
  }

  Widget _indicatorCard(String emoji, String label, String value, Color color) {
    return Expanded(
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        color: color.withOpacity(0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          child: Column(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 4),
              Text(value,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: color)),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- الإجراءات السريعة ----------------
  Widget _quickActions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            _actionButton(Icons.picture_as_pdf_outlined, 'كشف حساب PDF', _openFullStatement),
            _actionButton(Icons.print_outlined, 'طباعة', _printStatement),
            _actionButton(Icons.share_outlined, 'مشاركة', _shareStatement),
            _actionButton(Icons.visibility_outlined, 'معاينة', _previewStatement),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Icon(icon, size: 22),
              const SizedBox(height: 4),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10.5)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- سجل النشاط ----------------
  List<Widget> _timelineWidgets() {
    final items = <_TimelineItem>[
      ..._entries.map((e) => _TimelineItem.entry(e)),
      ..._notes.map((n) => _TimelineItem.note(n)),
    ]..sort((a, b) => b.date.compareTo(a.date));

    if (items.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 30),
          child: Center(
              child: Text('لا توجد حركات لهذا العميل بعد',
                  style: TextStyle(color: Colors.grey.shade600))),
        ),
      ];
    }

    return items.map((it) => it.entry != null ? _entryTile(it.entry!) : _noteTile(it.note!)).toList();
  }

  Widget _noteTile(CustomerNote n) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      color: Colors.indigo.withOpacity(0.06),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.transparent,
          child: Text('📝', style: TextStyle(fontSize: 18)),
        ),
        title: Text(n.text),
        subtitle: Text(Formatters.d(n.date), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
          onPressed: () => _deleteNote(n),
        ),
      ),
    );
  }

  Widget _entryTile(LedgerEntry e) {
    final isDebit = e.debit > 0;
    final amount = isDebit ? e.debit : e.credit;
    final dotEmoji = e.docType == LedgerDocType.receipt
        ? '🟢'
        : e.docType == LedgerDocType.invoiceReturn
            ? '🟠'
            : e.docType == LedgerDocType.invoiceSale
                ? '🔵'
                : '🚩';

    final card = Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: InkWell(
        onTap: _hasDoc(e) ? () => _openEntry(e) : null,
        onLongPress: _hasDoc(e) ? () => _entryLongPressMenu(e) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: (isDebit ? Colors.red : Colors.green).withOpacity(0.12),
                child: Text(dotEmoji, style: const TextStyle(fontSize: 14)),
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
              Text(
                '${isDebit ? '+' : '-'}${Formatters.money(amount)}',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: isDebit ? Colors.red : Colors.green),
              ),
            ],
          ),
        ),
      ),
    );

    if (!_hasDoc(e)) return card;

    return Slidable(
      key: ValueKey(e.docId),
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.62,
        children: [
          SlidableAction(
            onPressed: (_) => _printEntry(e),
            backgroundColor: Colors.indigo.shade400,
            foregroundColor: Colors.white,
            icon: Icons.print_outlined,
            label: 'طباعة',
          ),
          SlidableAction(
            onPressed: (_) => _whatsappEntry(e),
            backgroundColor: Colors.green.shade600,
            foregroundColor: Colors.white,
            icon: Icons.chat,
            label: 'واتساب',
          ),
          SlidableAction(
            onPressed: (_) => _shareEntry(e),
            backgroundColor: Colors.teal.shade600,
            foregroundColor: Colors.white,
            icon: Icons.share_outlined,
            label: 'مشاركة',
          ),
        ],
      ),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.62,
        children: [
          SlidableAction(
            onPressed: (_) => _openEntry(e),
            backgroundColor: Colors.blueGrey.shade400,
            foregroundColor: Colors.white,
            icon: Icons.edit_outlined,
            label: 'تعديل',
          ),
          SlidableAction(
            onPressed: (_) => _duplicateEntry(e),
            backgroundColor: Colors.purple.shade400,
            foregroundColor: Colors.white,
            icon: Icons.copy_all_outlined,
            label: 'تكرار',
          ),
          SlidableAction(
            onPressed: (_) => _deleteEntry(e),
            backgroundColor: Colors.red.shade600,
            foregroundColor: Colors.white,
            icon: Icons.delete_outline,
            label: 'حذف',
          ),
        ],
      ),
      child: card,
    );
  }

  void _entryLongPressMenu(LedgerEntry e) {
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
                _quickPreview(e);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('تعديل'),
              onTap: () {
                Navigator.pop(ctx);
                _openEntry(e);
              },
            ),
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('طباعة'),
              onTap: () {
                Navigator.pop(ctx);
                _printEntry(e);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('مشاركة PDF'),
              onTap: () {
                Navigator.pop(ctx);
                _shareEntry(e);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('نسخ رقم المستند'),
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: e.docNumber));
                _snack('تم نسخ رقم المستند');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineItem {
  final DateTime date;
  final LedgerEntry? entry;
  final CustomerNote? note;
  _TimelineItem.entry(LedgerEntry e)
      : entry = e,
        note = null,
        date = e.date;
  _TimelineItem.note(CustomerNote n)
      : note = n,
        entry = null,
        date = n.date;
}
