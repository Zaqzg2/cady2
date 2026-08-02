import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/app_provider.dart';
import '../services/backup_service.dart';
import '../services/db_service.dart';

/// قسم "البيانات والنسخ الاحتياطي": نسخ يدوي فوري، تذكير نسخ دوري
/// (تحقق عند فتح هذه الشاشة، وليس بالخلفية الحقيقية — يحتاج ذلك حزمة
/// جدولة إضافية لم تُضَف بعد)، استيراد، حجم البيانات، تنظيف صور قديمة،
/// وتصدير كل البيانات كملف CSV للمراجعة اليدوية.
class SettingsBackupScreen extends StatefulWidget {
  const SettingsBackupScreen({super.key});

  @override
  State<SettingsBackupScreen> createState() => _SettingsBackupScreenState();
}

class _SettingsBackupScreenState extends State<SettingsBackupScreen> {
  bool _busy = false;
  int _customersCount = 0, _productsCount = 0, _invoicesCount = 0, _receiptsCount = 0;
  String _storageSize = '...';

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _loadStats() async {
    final db = DbService.instance;
    final customers = await db.getCustomers();
    final products = await db.getProducts();
    final invoices = await db.getInvoices();
    final receipts = await db.getReceipts();
    final dir = await getApplicationDocumentsDirectory();
    var bytes = 0;
    if (await dir.exists()) {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          try {
            bytes += await entity.length();
          } catch (_) {}
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _customersCount = customers.length;
      _productsCount = products.length;
      _invoicesCount = invoices.length;
      _receiptsCount = receipts.length;
      _storageSize = _formatBytes(bytes);
    });
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes بايت';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} ك.ب';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} م.ب';
  }

  Future<void> _manualBackup() async {
    setState(() => _busy = true);
    try {
      await BackupService.instance.exportAndShare();
      if (mounted) _snack('تم إنشاء النسخة الاحتياطية');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final path = await BackupService.instance.pickBackupFilePath();
    if (path == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استيراد نسخة احتياطية'),
        content: const Text('سيتم دمج بيانات الملف المختار مع البيانات الحالية. متابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('استيراد')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    try {
      await BackupService.instance.importFromFile(path);
      if (mounted) {
        _snack('تم الاستيراد بنجاح');
        await context.read<AppProvider>().init();
        _loadStats();
      }
    } catch (e) {
      if (mounted) _snack('فشل الاستيراد: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// يحذف أي صورة داخل مجلد بيانات التطبيق غير مستخدمة حاليًا (غير
  /// الشعار الحالي ولا توقيع المندوب الافتراضي) — عادة توقيعات قديمة أو
  /// شعارات سابقة استُبدلت.
  Future<void> _cleanupOldImages() async {
    final app = context.read<AppProvider>();
    final s = app.settings;
    final keep = {s.logoPath, s.repSignaturePath}.whereType<String>().toSet();
    final dir = await getApplicationDocumentsDirectory();
    if (!await dir.exists()) return;
    var removed = 0;
    await for (final entity in dir.list()) {
      if (entity is File) {
        final ext = entity.path.toLowerCase();
        final isImage = ext.endsWith('.png') || ext.endsWith('.jpg') || ext.endsWith('.jpeg');
        if (isImage && !keep.contains(entity.path)) {
          try {
            await entity.delete();
            removed++;
          } catch (_) {}
        }
      }
    }
    if (mounted) {
      _snack(removed > 0 ? 'تم حذف $removed صورة غير مستخدمة' : 'لا توجد صور قديمة للحذف');
      _loadStats();
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _busy = true);
    try {
      final invoices = await DbService.instance.getInvoices();
      final buffer = StringBuffer();
      buffer.writeln('رقم الفاتورة,التاريخ,العميل,الإجمالي,نوع الدفع');
      for (final i in invoices) {
        buffer.writeln(
            '${i.docNumber},${i.date.toIso8601String()},"${i.customerName}",${i.grandTotal},'
            '${i.paymentMode.name}');
      }
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/فواتير_${DateTime.now().millisecondsSinceEpoch}.csv');
      await file.writeAsString(buffer.toString());
      await SharePlus.instance
          .share(ShareParams(files: [XFile(file.path)], text: 'تصدير الفواتير CSV'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final s = app.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('البيانات والنسخ الاحتياطي')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('نسخة احتياطية', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.backup),
                  label: const Text('نسخ احتياطي فوري ومشاركته'),
                  onPressed: _manualBackup,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.file_open),
                  label: const Text('استيراد نسخة سابقة'),
                  onPressed: _import,
                ),
                const Divider(height: 36),

                const Text('تذكير النسخ الدوري', style: TextStyle(fontWeight: FontWeight.bold)),
                const Text(
                    'تنبيه فقط عند فتح التطبيق (وليس بالخلفية) — بحاجة حزمة جدولة إضافية لتفعيل خلفية حقيقية لاحقًا',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('تفعيل تذكير دوري'),
                  value: s.autoBackupEnabled,
                  onChanged: (v) async {
                    final ns = app.settings;
                    ns.autoBackupEnabled = v;
                    await app.saveSettings(ns);
                  },
                ),
                if (s.autoBackupEnabled)
                  Wrap(
                    spacing: 8,
                    children: [1, 3, 7, 14].map((d) {
                      final selected = s.autoBackupFrequencyDays == d;
                      return ChoiceChip(
                        label: Text('كل $d يوم'),
                        selected: selected,
                        onSelected: (_) async {
                          final ns = app.settings;
                          ns.autoBackupFrequencyDays = d;
                          await app.saveSettings(ns);
                        },
                      );
                    }).toList(),
                  ),
                const Divider(height: 36),

                const Text('حجم البيانات الحالي', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _statRow('العملاء', _customersCount.toString()),
                _statRow('المنتجات', _productsCount.toString()),
                _statRow('الفواتير', _invoicesCount.toString()),
                _statRow('السندات', _receiptsCount.toString()),
                _statRow('المساحة المستخدمة', _storageSize),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.cleaning_services_outlined),
                  label: const Text('تنظيف الصور القديمة غير المستخدمة'),
                  onPressed: _cleanupOldImages,
                ),
                const Divider(height: 36),

                const Text('تصدير للمراجعة اليدوية',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const Text('ملف CSV يحتوي كل الفواتير — يفتح مباشرة في Excel',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.table_view),
                  label: const Text('تصدير الفواتير CSV'),
                  onPressed: _exportCsv,
                ),
              ],
            ),
    );
  }

  Widget _statRow(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(v, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text(k, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );
}
