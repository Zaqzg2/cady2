import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../models/customer.dart';
import '../models/customer_summary.dart';
import '../models/invoice.dart';
import '../providers/app_provider.dart';
import '../utils/formatters.dart';
import '../widgets/radial_quick_menu.dart';
import 'customer_profile_screen.dart';
import 'invoice_screen.dart';
import 'receipt_screen.dart';

/// إدارة العملاء — بطاقة العميل:
/// - ضغطة واحدة: تفتح صفحة العميل الكاملة (رصيد، مؤشرات، سجل نشاط).
/// - سحب يمين (في RTL): إجراءات سريعة (فاتورة بيع/سند قبض/اتصال).
/// - سحب يسار: إجراءات إدارية (تعديل/تثبيت/حذف).
/// - ضغط مطوّل: قائمة دائرية شاملة حول الإصبع.
class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});

  Future<void> _editCustomer(BuildContext context, Customer? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final addressCtrl = TextEditingController(text: existing?.address ?? '');
    final openingCtrl =
        TextEditingController(text: existing?.openingBalance.toString() ?? '0');
    final creditLimitCtrl =
        TextEditingController(text: existing?.creditLimit.toString() ?? '0');
    bool isStopped = existing?.isStopped ?? false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(existing == null ? 'إضافة عميل' : 'تعديل عميل'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'اسم العميل')),
                TextField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'رقم الهاتف')),
                TextField(
                    controller: addressCtrl,
                    decoration: const InputDecoration(labelText: 'العنوان')),
                TextField(
                  controller: openingCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'الرصيد الافتتاحي'),
                ),
                TextField(
                  controller: creditLimitCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'الحد الائتماني (اختياري)', helperText: '0 = بدون حد'),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('عميل متوقف'),
                  subtitle: const Text('لن يظهر كنشط في بطاقته'),
                  value: isStopped,
                  onChanged: (v) => setState(() => isStopped = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );

    if (result == true && nameCtrl.text.trim().isNotEmpty) {
      final c = Customer(
        id: existing?.id ?? const Uuid().v4(),
        name: nameCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
        address: addressCtrl.text.trim(),
        openingBalance: double.tryParse(openingCtrl.text) ?? 0,
        isPinned: existing?.isPinned ?? false,
        isStopped: isStopped,
        creditLimit: double.tryParse(creditLimitCtrl.text) ?? 0,
      );
      if (context.mounted) {
        await context.read<AppProvider>().saveCustomer(c);
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, Customer c) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد حذف العميل'),
        content: Text('هل أنت متأكد من حذف "${c.name}"؟\n'
            'ملاحظة: فواتيره وسنداته السابقة تبقى محفوظة بالسجل لكن بدون '
            'ربط بعميل حالي.'),
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
    if (confirm == true && context.mounted) {
      await context.read<AppProvider>().deleteCustomer(c.id);
    }
  }

  Future<void> _call(BuildContext context, Customer c) async {
    if (c.phone.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('لا يوجد رقم هاتف مسجل لهذا العميل')));
      return;
    }
    final uri = Uri(scheme: 'tel', path: c.phone.trim());
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _whatsapp(BuildContext context, Customer c) async {
    if (c.phone.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('لا يوجد رقم هاتف مسجل لهذا العميل')));
      return;
    }
    final digits = c.phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse('https://wa.me/$digits');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تعذّر فتح واتساب')));
    }
  }

  Future<void> _newInvoice(BuildContext context, Customer c) async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => InvoiceScreen(kind: InvoiceKind.sale, presetCustomer: c)));
  }

  Future<void> _newReceipt(BuildContext context, Customer c) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => ReceiptScreen(presetCustomer: c)));
  }

  void _openProfile(BuildContext context, Customer c) {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => CustomerProfileScreen(customer: c)));
  }

  void _showRadialMenu(BuildContext context, Offset position, Customer c) {
    final app = context.read<AppProvider>();
    RadialQuickMenu.show(context, position, [
      RadialMenuAction(
        icon: Icons.visibility_outlined,
        label: 'عرض',
        color: Colors.indigo,
        onTap: () => _openProfile(context, c),
      ),
      RadialMenuAction(
        icon: Icons.point_of_sale,
        label: 'فاتورة بيع',
        color: Colors.green.shade600,
        onTap: () => _newInvoice(context, c),
      ),
      RadialMenuAction(
        icon: Icons.payments,
        label: 'سند قبض',
        color: Colors.amber.shade700,
        onTap: () => _newReceipt(context, c),
      ),
      RadialMenuAction(
        icon: Icons.call,
        label: 'اتصال',
        color: Colors.teal.shade600,
        onTap: () => _call(context, c),
      ),
      RadialMenuAction(
        icon: Icons.chat,
        label: 'واتساب',
        color: Colors.green.shade700,
        onTap: () => _whatsapp(context, c),
      ),
      RadialMenuAction(
        icon: Icons.edit_outlined,
        label: 'تعديل',
        color: Colors.blueGrey.shade400,
        onTap: () => _editCustomer(context, c),
      ),
      RadialMenuAction(
        icon: c.isPinned ? Icons.star : Icons.star_border,
        label: c.isPinned ? 'إلغاء التثبيت' : 'تثبيت',
        color: Colors.orange.shade700,
        onTap: () => app.togglePinned(c),
      ),
      RadialMenuAction(
        icon: Icons.delete_outline,
        label: 'حذف',
        color: Colors.red.shade600,
        onTap: () => _confirmDelete(context, c),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('العملاء')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _editCustomer(context, null),
        child: const Icon(Icons.add),
      ),
      body: app.customers.isEmpty
          ? const Center(child: Text('لا يوجد عملاء بعد — اضغط + للإضافة'))
          : ListView.builder(
              padding: const EdgeInsets.only(top: 4, bottom: 90),
              itemCount: app.customers.length,
              itemBuilder: (ctx, i) => _CustomerCard(
                customer: app.customers[i],
                onTap: () => _openProfile(context, app.customers[i]),
                onLongPressStart: (details) =>
                    _showRadialMenu(context, details.globalPosition, app.customers[i]),
                onCall: () => _call(context, app.customers[i]),
                onWhatsapp: () => _whatsapp(context, app.customers[i]),
                onNewInvoice: () => _newInvoice(context, app.customers[i]),
                onNewReceipt: () => _newReceipt(context, app.customers[i]),
                onEdit: () => _editCustomer(context, app.customers[i]),
                onDelete: () => _confirmDelete(context, app.customers[i]),
                onTogglePin: () => app.togglePinned(app.customers[i]),
              ),
            ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  final Customer customer;
  final VoidCallback onTap;
  final GestureLongPressStartCallback onLongPressStart;
  final VoidCallback onCall;
  final VoidCallback onWhatsapp;
  final VoidCallback onNewInvoice;
  final VoidCallback onNewReceipt;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTogglePin;

  const _CustomerCard({
    required this.customer,
    required this.onTap,
    required this.onLongPressStart,
    required this.onCall,
    required this.onWhatsapp,
    required this.onNewInvoice,
    required this.onNewReceipt,
    required this.onEdit,
    required this.onDelete,
    required this.onTogglePin,
  });

  MaterialColor _avatarColor(BuildContext context) =>
      Colors.primaries[customer.name.hashCode % Colors.primaries.length];

  @override
  Widget build(BuildContext context) {
    final c = customer;
    return Slidable(
      key: ValueKey(c.id),
      // سحب من الحافة اليمنى (في RTL): إجراءات سريعة
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.62,
        children: [
          SlidableAction(
            onPressed: (_) => onNewInvoice(),
            backgroundColor: Colors.green.shade600,
            foregroundColor: Colors.white,
            icon: Icons.point_of_sale,
            label: 'فاتورة',
          ),
          SlidableAction(
            onPressed: (_) => onNewReceipt(),
            backgroundColor: Colors.amber.shade700,
            foregroundColor: Colors.white,
            icon: Icons.payments,
            label: 'قبض',
          ),
          SlidableAction(
            onPressed: (_) => onCall(),
            backgroundColor: Colors.teal.shade600,
            foregroundColor: Colors.white,
            icon: Icons.call,
            label: 'اتصال',
          ),
        ],
      ),
      // سحب من الحافة اليسرى: إجراءات إدارية
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.62,
        children: [
          SlidableAction(
            onPressed: (_) => onEdit(),
            backgroundColor: Colors.blueGrey.shade400,
            foregroundColor: Colors.white,
            icon: Icons.edit_outlined,
            label: 'تعديل',
          ),
          SlidableAction(
            onPressed: (_) => onTogglePin(),
            backgroundColor: Colors.orange.shade700,
            foregroundColor: Colors.white,
            icon: c.isPinned ? Icons.star : Icons.star_border,
            label: c.isPinned ? 'مثبّت' : 'تثبيت',
          ),
          SlidableAction(
            onPressed: (_) => onDelete(),
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
        child: FutureBuilder<CustomerSummary>(
          future: context.read<AppProvider>().getCustomerSummary(c.id),
          builder: (ctx, snap) {
            final summary = snap.data;
            final balance = summary?.balance ?? 0;
            final overdue = summary != null &&
                balance > 0 &&
                ((c.creditLimit > 0 && balance > c.creditLimit) ||
                    ((summary.daysSinceLastActivity ?? 0) >= 30));
            final avatarColor = _avatarColor(context);

            return GestureDetector(
              onTap: onTap,
              onLongPressStart: onLongPressStart,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // شريط جانبي أحمر للعملاء المتأخرين في السداد
                  Container(width: 4, color: overdue ? Colors.red.shade400 : Colors.transparent),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 10, 12, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // السطر الأول: الاسم + التثبيت + حالة النشاط
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: avatarColor.shade100,
                                foregroundColor: avatarColor.shade800,
                                child: Text(
                                  c.name.trim().isNotEmpty ? c.name.trim()[0] : '؟',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(c.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold, fontSize: 15),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              if (c.isPinned)
                                const Padding(
                                  padding: EdgeInsets.only(left: 4),
                                  child: Icon(Icons.star, size: 16, color: Colors.amber),
                                ),
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: c.isStopped ? Colors.grey.shade400 : Colors.green,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // السطر الثاني: الرصيد
                          Text(
                            'الرصيد: ${summary == null ? '...' : Formatters.money(balance)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: balance > 0
                                  ? Colors.red.shade600
                                  : balance < 0
                                      ? Colors.green.shade700
                                      : Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          // السطر الثالث: آخر زيارة + آخر فاتورة
                          Row(
                            children: [
                              Icon(Icons.schedule, size: 12, color: Colors.grey.shade600),
                              const SizedBox(width: 3),
                              Text(summary?.lastActivityLabel ?? '...',
                                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                              if (summary?.lastInvoiceNumber != null) ...[
                                const SizedBox(width: 10),
                                Icon(Icons.receipt_long, size: 12, color: Colors.grey.shade600),
                                const SizedBox(width: 3),
                                Text('#${summary!.lastInvoiceNumber}',
                                    style:
                                        TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                              ],
                            ],
                          ),
                          if (c.creditLimit > 0) ...[
                            const SizedBox(height: 6),
                            _CreditLimitBar(balance: balance, limit: c.creditLimit),
                          ],
                          const SizedBox(height: 6),
                          // السطر الرابع: إجراءات سريعة
                          Row(
                            children: [
                              _QuickIcon(
                                  icon: Icons.call, color: Colors.teal, onTap: onCall),
                              _QuickIcon(
                                  icon: Icons.chat, color: Colors.green, onTap: onWhatsapp),
                              _QuickIcon(
                                  icon: Icons.point_of_sale,
                                  color: Colors.indigo,
                                  onTap: onNewInvoice),
                              _QuickIcon(
                                  icon: Icons.payments,
                                  color: Colors.amber.shade800,
                                  onTap: onNewReceipt),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _QuickIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _QuickIcon({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}

/// شريط بسيط يوضح نسبة استخدام الحد الائتماني
class _CreditLimitBar extends StatelessWidget {
  final double balance;
  final double limit;
  const _CreditLimitBar({required this.balance, required this.limit});

  @override
  Widget build(BuildContext context) {
    final ratio = (balance / limit).clamp(0.0, 1.0);
    final over = balance > limit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 5,
            backgroundColor: Colors.grey.shade200,
            color: over ? Colors.red : Colors.orange,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'الحد الائتماني: ${Formatters.money(limit)}  (${(ratio * 100).clamp(0, 100).toStringAsFixed(0)}٪)',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
