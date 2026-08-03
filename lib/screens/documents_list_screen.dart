import 'package:flutter/material.dart';

import '../models/doc_row.dart';
import '../models/invoice.dart';
import '../models/receipt.dart';
import '../services/db_service.dart';
import '../utils/document_row_actions.dart';
import '../widgets/doc_card.dart';

/// سجل موحّد لكل الفواتير والسندات.
/// - بطاقة مضغوطة: أيقونة دائرية 48×48، اسم/رقم المستند، اسم العميل،
///   التاريخ والوقت، الرصيد بعد العملية، وزرا "تفاصيل/طباعة" سريعين.
/// - ضغطة واحدة: تفتح تفاصيل المستند (شاشة التعديل).
/// - ضغط على الأيقونة: معاينة سريعة للمستند.
/// - ضغط مطوّل: قائمة إجراءات كاملة.
/// - سحب يمين (جزئي): معاينة/طباعة/مشاركة. سحب يسار: تعديل/تكرار/حذف.
/// - سحب لأسفل: تحديث السجل (Pull to Refresh).
class DocumentsListScreen extends StatefulWidget {
  const DocumentsListScreen({super.key});

  @override
  State<DocumentsListScreen> createState() => _DocumentsListScreenState();
}

class _DocumentsListScreenState extends State<DocumentsListScreen>
    with DocumentRowActions<DocumentsListScreen> {
  String _filter = 'all'; // all / sale / return / receipt
  List<Invoice> _invoices = [];
  List<Receipt> _receipts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _invoices = await DbService.instance.getInvoices();
    _receipts = await DbService.instance.getReceipts();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final items = <DocRow>[
      if (_filter == 'all' || _filter == 'sale' || _filter == 'return')
        ..._invoices
            .where((i) => _filter == 'all' ||
                (_filter == 'sale' && i.kind == InvoiceKind.sale) ||
                (_filter == 'return' && i.kind == InvoiceKind.saleReturn))
            .map((i) => DocRow.invoice(i)),
      if (_filter == 'all' || _filter == 'receipt')
        ..._receipts.map((r) => DocRow.receipt(r)),
    ]..sort((a, b) {
        if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
        return b.date.compareTo(a.date);
      });

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
          : RefreshIndicator(
              onRefresh: _load,
              child: items.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('لا توجد مستندات بعد')),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: items.length,
                      itemBuilder: (ctx, i) {
                        final row = items[i];
                        return DocCard(
                          row: row,
                          onTap: () => editRow(row, onDone: _load),
                          onIconTap: () => quickPreviewRow(row, onDone: _load),
                          onLongPress: () => longPressMenuRow(row, onDone: _load),
                          onDetails: () => openStatementAfter(row),
                          onPrint: () => printRow(row, onDone: () => setState(() {})),
                          onQuickPreview: () => quickPreviewRow(row, onDone: _load),
                          onShare: () => shareRow(row, onDone: () => setState(() {})),
                          onEdit: () => editRow(row, onDone: _load),
                          onDuplicate: () => duplicateRow(row, onDone: _load),
                          onDelete: () => confirmDeleteRow(row, onDone: _load),
                        );
                      },
                    ),
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
