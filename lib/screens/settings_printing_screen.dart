import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../providers/app_provider.dart';
import '../services/print_service.dart';
import '../services/pdf_service.dart';

/// قسم "الطباعة والفاتورة": الطابعة الحرارية + اختبار طباعة، خط جدول
/// الأصناف وتباعده (بمعاينة حية)، خط عام للمستند كامل وتباعده (بمعاينة
/// حية منفصلة)، والصيغة الافتراضية لطباعة كشف الحساب.
class SettingsPrintingScreen extends StatefulWidget {
  const SettingsPrintingScreen({super.key});

  @override
  State<SettingsPrintingScreen> createState() => _SettingsPrintingScreenState();
}

class _SettingsPrintingScreenState extends State<SettingsPrintingScreen> {
  double _tableFontSize = 9;
  double _rowSpacing = 4;
  double _docFontSize = 9;
  double _docLineSpacing = 4;
  bool _defaultStatement80mm = false;
  List<BluetoothInfo> _pairedDevices = [];
  String? _selectedPrinterMac;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppProvider>().settings;
    _tableFontSize = s.tableFontSize;
    _rowSpacing = s.rowSpacing;
    _docFontSize = s.docFontSize;
    _docLineSpacing = s.docLineSpacing;
    _defaultStatement80mm = s.defaultStatement80mm;
    _selectedPrinterMac = s.printerAddress;
    _loadPairedDevices();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _loadPairedDevices() async {
    try {
      final list = await PrintService.instance.getPairedDevices();
      if (mounted) setState(() => _pairedDevices = list);
    } catch (_) {
      // البلوتوث قد لا يكون مفعّلاً أو الصلاحيات غير ممنوحة بعد
    }
  }

  Future<void> _connectPrinter(BluetoothInfo device) async {
    setState(() => _selectedPrinterMac = device.macAdress);
    final ok = await PrintService.instance.connect(device.macAdress);
    if (!mounted) return;
    if (ok) {
      final app = context.read<AppProvider>();
      final s = app.settings;
      s.printerAddress = device.macAdress;
      s.printerName = device.name;
      await app.saveSettings(s);
      _snack('تم الاتصال بالطابعة ${device.name}');
    } else {
      setState(() => _selectedPrinterMac = context.read<AppProvider>().settings.printerAddress);
      _snack('تعذّر الاتصال بالطابعة');
    }
  }

  Future<void> _testPrint() async {
    setState(() => _testing = true);
    try {
      final settings = context.read<AppProvider>().settings;
      final bytes = await PdfService.instance.generateTestPrint(settings);
      final ok = await PrintService.instance.printPdfBytes(bytes);
      if (mounted) {
        _snack(ok ? 'أُرسلت صفحة الاختبار للطابعة' : 'تعذّر الاتصال بالطابعة');
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _saveNumbers() async {
    final app = context.read<AppProvider>();
    final s = app.settings;
    s.tableFontSize = _tableFontSize;
    s.rowSpacing = _rowSpacing;
    s.docFontSize = _docFontSize;
    s.docLineSpacing = _docLineSpacing;
    s.defaultStatement80mm = _defaultStatement80mm;
    await app.saveSettings(s);
    if (mounted) _snack('تم حفظ إعدادات الطباعة');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الطباعة والفاتورة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              const Text('الطابعة الحرارية', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_selectedPrinterMac != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: Colors.green.shade50, borderRadius: BorderRadius.circular(20)),
                  child: const Text('متصلة', style: TextStyle(color: Colors.green, fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('تحديث قائمة الأجهزة المقترنة'),
            onPressed: _loadPairedDevices,
          ),
          const SizedBox(height: 8),
          if (_pairedDevices.isEmpty)
            const Text('لا توجد أجهزة مقترنة — اقرن الطابعة أولًا من إعدادات بلوتوث الهاتف',
                style: TextStyle(fontSize: 12, color: Colors.grey))
          else
            ..._pairedDevices.map((d) => RadioListTile<String>(
                  title: Text(d.name),
                  subtitle: Text(d.macAdress),
                  value: d.macAdress,
                  groupValue: _selectedPrinterMac,
                  onChanged: (_) => _connectPrinter(d),
                )),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            icon: _testing
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.receipt_long),
            label: const Text('طباعة ورقة اختبار'),
            onPressed: _selectedPrinterMac == null || _testing ? null : _testPrint,
          ),
          const Divider(height: 36),

          const Text('خط الجدول', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('حجم وتباعد جدول الأصناف داخل الفاتورة فقط',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 10),
          _tableLivePreview(),
          const SizedBox(height: 10),
          Text('حجم الخط: ${_tableFontSize.toStringAsFixed(0)}'),
          Slider(
            value: _tableFontSize,
            min: 6,
            max: 14,
            divisions: 8,
            label: _tableFontSize.toStringAsFixed(0),
            onChanged: (v) => setState(() => _tableFontSize = v),
          ),
          Text('تباعد الصفوف: ${_rowSpacing.toStringAsFixed(0)}'),
          Slider(
            value: _rowSpacing,
            min: 0,
            max: 16,
            divisions: 8,
            label: _rowSpacing.toStringAsFixed(0),
            onChanged: (v) => setState(() => _rowSpacing = v),
          ),
          const Divider(height: 36),

          const Text('خط عام للمستند', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('يشمل الرأس وبيانات العميل والتذييل بالفاتورة والسند كاملة (غير الجدول)',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 10),
          _docLivePreview(),
          const SizedBox(height: 10),
          Text('حجم الخط: ${_docFontSize.toStringAsFixed(0)}'),
          Slider(
            value: _docFontSize,
            min: 7,
            max: 14,
            divisions: 7,
            label: _docFontSize.toStringAsFixed(0),
            onChanged: (v) => setState(() => _docFontSize = v),
          ),
          Text('تباعد الأسطر: ${_docLineSpacing.toStringAsFixed(0)}'),
          Slider(
            value: _docLineSpacing,
            min: 0,
            max: 12,
            divisions: 6,
            label: _docLineSpacing.toStringAsFixed(0),
            onChanged: (v) => setState(() => _docLineSpacing = v),
          ),
          const Divider(height: 36),

          const Text('كشف الحساب', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('80مم حراري كصيغة افتراضية'),
            subtitle: const Text('بدل A4 — يمكن تغييرها يدويًا داخل كل عميل'),
            value: _defaultStatement80mm,
            onChanged: (v) => setState(() => _defaultStatement80mm = v),
          ),
          const SizedBox(height: 20),

          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('حفظ'),
            onPressed: _saveNumbers,
          ),
        ],
      ),
    );
  }

  Widget _tableLivePreview() {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
      child: Table(
        border: TableBorder.all(color: Colors.grey.shade400, width: 0.5),
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.grey.shade200),
            children: ['الصنف', 'الكمية', 'السعر', 'الإجمالي']
                .map((h) => Padding(
                      padding: EdgeInsets.symmetric(vertical: _rowSpacing, horizontal: 4),
                      child: Text(h,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: _tableFontSize, fontWeight: FontWeight.bold)),
                    ))
                .toList(),
          ),
          TableRow(
            children: ['صابون سائل', '3', '1200', '3600']
                .map((v) => Padding(
                      padding: EdgeInsets.symmetric(vertical: _rowSpacing, horizontal: 4),
                      child: Text(v,
                          textAlign: TextAlign.center, style: TextStyle(fontSize: _tableFontSize)),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _docLivePreview() {
    Widget row(String k, String v) => Padding(
          padding: EdgeInsets.symmetric(vertical: _docLineSpacing / 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(v, style: TextStyle(fontSize: _docFontSize)),
              Text(k, style: TextStyle(fontSize: _docFontSize)),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)),
      child: Column(
        children: [
          Text('كادي للمنظفات',
              style: TextStyle(fontSize: _docFontSize + 3, fontWeight: FontWeight.bold)),
          const Divider(),
          row('رقم الفاتورة', '0021'),
          row('العميل', 'اخوة السلام'),
          row('الإجمالي', '15,000 ر.ي'),
        ],
      ),
    );
  }
}
