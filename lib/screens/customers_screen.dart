import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../models/customer.dart';
import '../providers/app_provider.dart';
import '../utils/formatters.dart';
import '../widgets/radial_quick_menu.dart';
import 'customer_statement_screen.dart';

/// إدارة العملاء:
/// - سحب يمين (في RTL): اتصال + واتساب مباشرة (أخضر) بدون فتح كشف الحساب.
/// - سحب يسار: تعديل + حذف (أحمر) مع تأكيد قبل الحذف.
/// - ضغط مطوّل: قائمة دائرية سريعة حول الإصبع (كشف حساب/اتصال/واتساب/حذف).
class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});

  Future<void> _editCustomer(BuildContext context, Customer? existing) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final addressCtrl = TextEditingController(text: existing?.address ?? '');
    final openingCtrl =
        TextEditingController(text: existing?.openingBalance.toString() ?? '0');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
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
                decoration:
                    const InputDecoration(labelText: 'الرصيد الافتتاحي'),
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
    );

    if (result == true && nameCtrl.text.trim().isNotEmpty) {
      final c = Customer(
        id: existing?.id ?? const Uuid().v4(),
        name: nameCtrl.text.trim(),
        phone: phoneCtrl.text.trim(),
        address: addressCtrl.text.trim(),
        openingBalance: double.tryParse(openingCtrl.text) ?? 0,
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

  void _openStatement(BuildContext context, Customer c) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => CustomerStatementScreen(customer: c)));
  }

  void _showRadialMenu(BuildContext context, Offset position, Customer c) {
    RadialQuickMenu.show(context, position, [
      RadialMenuAction(
        icon: Icons.receipt_long,
        label: 'كشف حساب',
        color: Colors.indigo,
        onTap: () => _openStatement(context, c),
      ),
      RadialMenuAction(
        icon: Icons.call,
        label: 'اتصال',
        color: Colors.green.shade600,
        onTap: () => _call(context, c),
      ),
      RadialMenuAction(
        icon: Icons.chat,
        label: 'واتساب',
        color: Colors.teal.shade600,
        onTap: () => _whatsapp(context, c),
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
              itemCount: app.customers.length,
              itemBuilder: (ctx, i) {
                final c = app.customers[i];
                return Slidable(
                  key: ValueKey(c.id),
                  // سحب من الحافة اليمنى (في RTL): اتصال + واتساب
                  startActionPane: ActionPane(
                    motion: const DrawerMotion(),
                    extentRatio: 0.42,
                    children: [
                      SlidableAction(
                        onPressed: (_) => _call(context, c),
                        backgroundColor: Colors.green.shade600,
                        foregroundColor: Colors.white,
                        icon: Icons.call,
                        label: 'اتصال',
                      ),
                      SlidableAction(
                        onPressed: (_) => _whatsapp(context, c),
                        backgroundColor: Colors.teal.shade600,
                        foregroundColor: Colors.white,
                        icon: Icons.chat,
                        label: 'واتساب',
                      ),
                    ],
                  ),
                  // سحب من الحافة اليسرى: تعديل + حذف
                  endActionPane: ActionPane(
                    motion: const DrawerMotion(),
                    extentRatio: 0.42,
                    children: [
                      SlidableAction(
                        onPressed: (_) => _editCustomer(context, c),
                        backgroundColor: Colors.blueGrey.shade400,
                        foregroundColor: Colors.white,
                        icon: Icons.edit_outlined,
                        label: 'تعديل',
                      ),
                      SlidableAction(
                        onPressed: (_) => _confirmDelete(context, c),
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        icon: Icons.delete_outline,
                        label: 'حذف',
                      ),
                    ],
                  ),
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: GestureDetector(
                      onLongPressStart: (details) =>
                          _showRadialMenu(context, details.globalPosition, c),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              Colors.primaries[c.name.hashCode % Colors.primaries.length]
                                  .shade100,
                          foregroundColor:
                              Colors.primaries[c.name.hashCode % Colors.primaries.length]
                                  .shade800,
                          child: Text(
                            c.name.trim().isNotEmpty ? c.name.trim()[0] : '؟',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(c.phone.isEmpty ? 'بدون رقم هاتف' : c.phone),
                        trailing: FutureBuilder<double>(
                          future: app.getCustomerBalance(c.id),
                          builder: (ctx, snap) => Text(
                            snap.hasData ? Formatters.money(snap.data!) : '...',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: (snap.data ?? 0) > 0
                                  ? Colors.red
                                  : (snap.data ?? 0) < 0
                                      ? Colors.green
                                      : Colors.grey,
                            ),
                          ),
                        ),
                        onTap: () => _openStatement(context, c),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
