import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/company_settings.dart';
import '../providers/app_provider.dart';
import '../services/auth_service.dart';

/// قسم "الخصوصية والأمان": كلمة المرور، القفل التلقائي بعد مدة خمول
/// (مفعّل فعليًا عبر مراقبة دورة حياة التطبيق)، وإخفاء الأرقام المالية
/// أثناء التبديل بين التطبيقات (Recents).
class SettingsSecurityScreen extends StatefulWidget {
  const SettingsSecurityScreen({super.key});

  @override
  State<SettingsSecurityScreen> createState() => _SettingsSecurityScreenState();
}

class _SettingsSecurityScreenState extends State<SettingsSecurityScreen> {
  bool? _passwordEnabled;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final set = await AuthService.instance.isPasswordSet();
    if (mounted) setState(() => _passwordEnabled = set);
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _setOrChangePassword() async {
    final ctrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_passwordEnabled == true ? 'تغيير كلمة المرور' : 'تفعيل كلمة المرور'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: ctrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'كلمة المرور الجديدة')),
            TextField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'تأكيد كلمة المرور')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (result != true) return;
    if (ctrl.text.trim().isEmpty || ctrl.text != confirmCtrl.text) {
      _snack('كلمتا المرور غير متطابقتين أو فارغتين');
      return;
    }
    await AuthService.instance.setPassword(ctrl.text.trim());
    _snack('تم حفظ كلمة المرور');
    _load();
  }

  Future<void> _disablePassword() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعطيل كلمة المرور'),
        content: const Text('سيصبح التطبيق مفتوحًا لأي شخص يمسك الجهاز. متأكد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton.tonal(
            style: FilledButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تعطيل'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await AuthService.instance.removePassword();
    _snack('تم تعطيل كلمة المرور');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final s = app.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('الخصوصية والأمان')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('كلمة المرور', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (_passwordEnabled == null)
            const LinearProgressIndicator()
          else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                _passwordEnabled! ? Icons.lock : Icons.lock_open,
                color: _passwordEnabled! ? Colors.green : Colors.orange,
              ),
              title: Text(_passwordEnabled! ? 'الحماية مفعّلة' : 'بدون كلمة مرور'),
              subtitle: Text(_passwordEnabled!
                  ? 'يُطلب إدخالها عند فتح التطبيق'
                  : 'أي شخص يمسك الجهاز يقدر يفتح التطبيق'),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _setOrChangePassword,
                    child: Text(_passwordEnabled! ? 'تغيير كلمة المرور' : 'تفعيل كلمة مرور'),
                  ),
                ),
                if (_passwordEnabled!) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.lock_open, color: Colors.red),
                    tooltip: 'تعطيل',
                    onPressed: _disablePassword,
                  ),
                ],
              ],
            ),
          ],
          const Divider(height: 36),

          const Text('القفل التلقائي', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('يعيد طلب كلمة المرور تلقائيًا بعد مدة خمول بالخلفية',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _lockChip(context, s, 0, 'فورًا'),
              _lockChip(context, s, 1, 'دقيقة'),
              _lockChip(context, s, 5, '5 دقائق'),
              _lockChip(context, s, -1, 'أبدًا'),
            ],
          ),
          const Divider(height: 36),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('إخفاء الأرقام المالية بالتطبيقات الأخيرة'),
            subtitle: const Text('يغطي الشاشة بشعار محايد عند التبديل لتطبيق آخر'),
            value: s.hideAmountsInRecents,
            onChanged: (v) async {
              final app2 = context.read<AppProvider>();
              final ns = app2.settings;
              ns.hideAmountsInRecents = v;
              await app2.saveSettings(ns);
            },
          ),
          const Divider(height: 36),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('فتح ببصمة الإصبع / الوجه'),
            subtitle: const Text(
                'يتطلب إعدادًا إضافيًا (حزمة local_auth) لم يُفعَّل بعد بهذه النسخة — الخيار محفوظ فقط حاليًا'),
            value: s.biometricEnabled,
            onChanged: (v) async {
              final app2 = context.read<AppProvider>();
              final ns = app2.settings;
              ns.biometricEnabled = v;
              await app2.saveSettings(ns);
            },
          ),
        ],
      ),
    );
  }

  Widget _lockChip(BuildContext context, CompanySettings s, int minutes, String label) {
    final selected = s.autoLockMinutes == minutes;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) async {
        final app = context.read<AppProvider>();
        final ns = app.settings;
        ns.autoLockMinutes = minutes;
        await app.saveSettings(ns);
      },
    );
  }
}
