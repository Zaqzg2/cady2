import 'package:flutter/material.dart';

import '../models/doc_row.dart';
import '../models/invoice.dart';
import '../services/db_service.dart';
import '../utils/document_row_actions.dart';
import '../widgets/big_card.dart';
import '../widgets/doc_card.dart';
import 'documents_list_screen.dart';
import 'invoice_screen.dart';
import 'receipt_screen.dart';
import 'settings_screen.dart';

/// الشاشة الرئيسية: بطاقات كبيرة بالترتيب المطلوب
/// عميل نقدي / فاتورة مرتجع / فاتورة بيع / سند قبض
/// + أيقونة سجل السندات والفواتير أعلى يمين، وأيقونة الإعدادات أعلى يسار
/// + قسم "آخر العمليات": آخر 5 فواتير/سندات مع رابط لعرض السجل الكامل.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with DocumentRowActions<HomeScreen> {
  List<DocRow> _recent = [];
  bool _loadingRecent = true;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    setState(() => _loadingRecent = true);
    final invoices = await DbService.instance.getInvoices();
    final receipts = await DbService.instance.getReceipts();
    final items = <DocRow>[
      ...invoices.map((i) => DocRow.invoice(i)),
      ...receipts.map((r) => DocRow.receipt(r)),
    ]..sort((a, b) => b.date.compareTo(a.date));
    if (!mounted) return;
    setState(() {
      _recent = items.take(5).toList();
      _loadingRecent = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('كادي للمنظفات'),
        leading: IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'الإعدادات',
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: 'سجل السندات والفواتير',
            onPressed: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const DocumentsListScreen()));
              _loadRecent();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadRecent,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.05,
              children: [
                BigCard(
                  icon: Icons.person,
                  title: 'عميل نقدي',
                  subtitle: 'بيع سريع بدون تسجيل عميل',
                  onTap: () => _openInvoice(
                      context, InvoiceScreen(kind: InvoiceKind.sale, forceCashCustomer: true)),
                ),
                BigCard(
                  icon: Icons.assignment_return,
                  title: 'فاتورة مرتجع',
                  color: Colors.red.shade100,
                  onTap: () =>
                      _openInvoice(context, const InvoiceScreen(kind: InvoiceKind.saleReturn)),
                ),
                BigCard(
                  icon: Icons.point_of_sale,
                  title: 'فاتورة بيع',
                  color: Colors.green.shade100,
                  onTap: () => _openInvoice(context, const InvoiceScreen(kind: InvoiceKind.sale)),
                ),
                BigCard(
                  icon: Icons.payments,
                  title: 'سند قبض',
                  color: Colors.amber.shade100,
                  onTap: () async {
                    await Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const ReceiptScreen()));
                    _loadRecent();
                  },
                ),
              ],
            ),
            const SizedBox(height: 22),
            _recentHeader(),
            const SizedBox(height: 4),
            _recentList(),
          ],
        ),
      ),
    );
  }

  Future<void> _openInvoice(BuildContext context, Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    _loadRecent();
  }

  Widget _recentHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('آخر العمليات',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        TextButton(
          onPressed: () async {
            await Navigator.push(
                context, MaterialPageRoute(builder: (_) => const DocumentsListScreen()));
            _loadRecent();
          },
          child: const Text('عرض الكل'),
        ),
      ],
    );
  }

  Widget _recentList() {
    if (_loadingRecent) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_recent.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
            child: Text('لا توجد عمليات بعد', style: TextStyle(color: Colors.grey.shade600))),
      );
    }
    return Column(
      children: _recent
          .map((row) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 0),
                child: DocCard(
                  row: row,
                  enableSwipe: false,
                  onTap: () => editRow(row, onDone: _loadRecent),
                  onIconTap: () => quickPreviewRow(row, onDone: _loadRecent),
                  onLongPress: () => longPressMenuRow(row, onDone: _loadRecent),
                  onDetails: () => openStatementAfter(row),
                  onPrint: () => printRow(row, onDone: () => setState(() {})),
                ),
              ))
          .toList(),
    );
  }
}
