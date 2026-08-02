import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../widgets/signature_pad_widget.dart';

const _identityColorChoices = <Color>[
  Color(0xFF00838F), // فيروزي (الافتراضي)
  Color(0xFFB71C1C), // أحمر داكن
  Color(0xFF1B5E20), // أخضر داكن
  Color(0xFF0D47A1), // أزرق داكن
  Color(0xFFE65100), // برتقالي
  Color(0xFF4A148C), // بنفسجي
  Color(0xFF212121), // أسود
];

/// قسم "هويتي التجارية": الشعار، بيانات الشركة والمندوب، توقيع المندوب
/// الافتراضي، لون الهوية على المستندات، ونص التذييل الثابت بالفواتير.
class SettingsCompanyScreen extends StatefulWidget {
  const SettingsCompanyScreen({super.key});

  @override
  State<SettingsCompanyScreen> createState() => _SettingsCompanyScreenState();
}

class _SettingsCompanyScreenState extends State<SettingsCompanyScreen> {
  late TextEditingController _companyName;
  late TextEditingController _companyPhone;
  late TextEditingController _companyAddress;
  late TextEditingController _repName;
  late TextEditingController _repPhone;
  late TextEditingController _footerText;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppProvider>().settings;
    _companyName = TextEditingController(text: s.companyName);
    _companyPhone = TextEditingController(text: s.companyPhone);
    _companyAddress = TextEditingController(text: s.companyAddress);
    _repName = TextEditingController(text: s.repName);
    _repPhone = TextEditingController(text: s.repPhone);
    _footerText = TextEditingController(text: s.footerText);
  }

  @override
  void dispose() {
    _companyName.dispose();
    _companyPhone.dispose();
    _companyAddress.dispose();
    _repName.dispose();
    _repPhone.dispose();
    _footerText.dispose();
    super.dispose();
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final app = context.read<AppProvider>();
    final s = app.settings;
    s.logoPath = file.path;
    await app.saveSettings(s);
    setState(() {});
  }

  Future<void> _removeLogo() async {
    final app = context.read<AppProvider>();
    final s = app.settings;
    s.logoPath = null;
    await app.saveSettings(s);
    setState(() {});
  }

  Future<void> _saveAll() async {
    final app = context.read<AppProvider>();
    final s = app.settings;
    s.companyName = _companyName.text.trim();
    s.companyPhone = _companyPhone.text.trim();
    s.companyAddress = _companyAddress.text.trim();
    s.repName = _repName.text.trim();
    s.repPhone = _repPhone.text.trim();
    s.footerText = _footerText.text.trim();
    await app.saveSettings(s);
    if (mounted) _snack('تم حفظ بيانات الشركة');
  }

  Future<void> _pickIdentityColor() async {
    final app = context.read<AppProvider>();
    final s = app.settings;
    final chosen = await showDialog<Color>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('لون الهوية بالمستندات'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _identityColorChoices.map((c) {
            final selected = c.value == s.identityColorValue;
            return GestureDetector(
              onTap: () => Navigator.pop(ctx, c),
              child: CircleAvatar(
                radius: 22,
                backgroundColor: c,
                child: selected ? const Icon(Icons.check, color: Colors.white) : null,
              ),
            );
          }).toList(),
        ),
      ),
    );
    if (chosen == null) return;
    s.identityColorValue = chosen.value;
    await app.saveSettings(s);
    setState(() {});
  }

  Future<void> _editSignature(String? path) async {
    final app = context.read<AppProvider>();
    final s = app.settings;
    s.repSignaturePath = path;
    await app.saveSettings(s);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final s = app.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('هويتي التجارية')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('شعار الشركة', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: s.logoPath != null ? FileImage(File(s.logoPath!)) : null,
                child: s.logoPath == null ? const Icon(Icons.image, size: 30) : null,
              ),
              const SizedBox(width: 14),
              OutlinedButton.icon(
                icon: const Icon(Icons.upload),
                label: const Text('رفع/تغيير'),
                onPressed: _pickLogo,
              ),
              if (s.logoPath != null) ...[
                const SizedBox(width: 8),
                IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: _removeLogo),
              ],
            ],
          ),
          const Divider(height: 32),

          const Text('بيانات الشركة', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
              controller: _companyName,
              decoration: const InputDecoration(labelText: 'اسم الشركة')),
          const SizedBox(height: 8),
          TextField(
              controller: _companyPhone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'هاتف الشركة')),
          const SizedBox(height: 8),
          TextField(
              controller: _companyAddress,
              decoration: const InputDecoration(labelText: 'عنوان الشركة')),
          const Divider(height: 32),

          const Text('بيانات المندوب', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
              controller: _repName, decoration: const InputDecoration(labelText: 'اسم المندوب')),
          const SizedBox(height: 8),
          TextField(
              controller: _repPhone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'هاتف المندوب')),
          const SizedBox(height: 14),
          const Text('توقيع المندوب الافتراضي',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 4),
          const Text('يُستخدم تلقائيًا بالسندات الجديدة بدل التوقيع يدويًا كل مرة',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 8),
          SignaturePadWidget(
            label: 'توقيع المندوب',
            existingPath: s.repSignaturePath,
            onSaved: _editSignature,
          ),
          const Divider(height: 32),

          const Text('لون الهوية بالمستندات',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('يظهر بعناوين وفواصل الفواتير والسندات وكشوفات الحساب المطبوعة',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 10),
          Row(
            children: [
              CircleAvatar(radius: 18, backgroundColor: s.identityColor),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: _pickIdentityColor, child: const Text('تغيير اللون')),
            ],
          ),
          const Divider(height: 32),

          const Text('نص أسفل الفاتورة والسند', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _footerText,
            decoration: const InputDecoration(
                labelText: 'مثال: شكرًا لتعاملكم معنا', hintText: 'اتركه فارغًا لإخفائه'),
          ),
          const SizedBox(height: 24),

          ElevatedButton.icon(
            icon: const Icon(Icons.save),
            label: const Text('حفظ'),
            onPressed: _saveAll,
          ),
        ],
      ),
    );
  }
}
