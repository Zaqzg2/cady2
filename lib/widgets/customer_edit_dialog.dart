import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../models/customer.dart';
import '../providers/app_provider.dart';

/// يفتح نافذة إضافة/تعديل بيانات عميل، ويحفظها مباشرة عند الضغط "حفظ".
/// تُستخدم من قائمة العملاء وصفحة العميل معًا حتى لا يتكرر نفس النموذج.
/// تُرجع true لو تم الحفظ فعليًا.
Future<bool> showEditCustomerDialog(BuildContext context, Customer? existing) async {
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
  final addressCtrl = TextEditingController(text: existing?.address ?? '');
  final openingCtrl = TextEditingController(text: existing?.openingBalance.toString() ?? '0');
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
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
      return true;
    }
  }
  return false;
}
