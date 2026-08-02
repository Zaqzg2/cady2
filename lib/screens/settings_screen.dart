import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/auth_service.dart';
import 'settings_company_screen.dart';
import 'settings_printing_screen.dart';
import 'settings_appearance_screen.dart';
import 'settings_security_screen.dart';
import 'settings_backup_screen.dart';

/// الشاشة الرئيسية للإعدادات — قائمة أقسام (نمط إعدادات النظام): كل سطر
/// أيقونة + عنوان + سطر فرعي يلخّص الحالة الحالية، وسهم يفتح شاشة كاملة
/// مستقلة لذاك القسم فقط.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _passwordEnabled;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final pw = await AuthService.instance.isPasswordSet();
    if (mounted) setState(() => _passwordEnabled = pw);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final s = app.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          _sectionTile(
            icon: Icons.store,
            iconColor: Colors.brown,
            title: 'هويتي التجارية',
            subtitle: s.companyName.isEmpty ? 'لم تُضبط بعد' : s.companyName,
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SettingsCompanyScreen())),
          ),
          _sectionTile(
            icon: Icons.print_outlined,
            iconColor: Colors.indigo,
            title: 'الطباعة والفاتورة',
            subtitle: s.printerName != null
                ? 'الطابعة: ${s.printerName} • متصلة'
                : 'لا توجد طابعة متصلة',
            statusColor: s.printerName != null ? Colors.green : Colors.orange,
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SettingsPrintingScreen())),
          ),
          _sectionTile(
            icon: Icons.palette_outlined,
            iconColor: Colors.purple,
            title: 'المظهر',
            subtitle: switch (s.themeModePref) {
              'dark' => 'داكن دائمًا',
              'system' => 'تلقائي حسب النظام',
              _ => 'فاتح دائمًا',
            },
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SettingsAppearanceScreen())),
          ),
          _sectionTile(
            icon: Icons.shield_outlined,
            iconColor: Colors.red,
            title: 'الخصوصية والأمان',
            subtitle: _passwordEnabled == null
                ? '...'
                : (_passwordEnabled!
                    ? 'الحماية مفعّلة 🔒'
                    : 'بدون كلمة مرور — الجهاز مفتوح لأي شخص'),
            statusColor: _passwordEnabled == true ? Colors.green : Colors.orange,
            onTap: () async {
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const SettingsSecurityScreen()));
              _loadStatus();
            },
          ),
          _sectionTile(
            icon: Icons.cloud_outlined,
            iconColor: Colors.teal,
            title: 'البيانات والنسخ الاحتياطي',
            subtitle: s.autoBackupEnabled
                ? 'نسخ تلقائي كل ${s.autoBackupFrequencyDays} يوم'
                : 'النسخ الاحتياطي يدوي فقط',
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SettingsBackupScreen())),
          ),
        ],
      ),
    );
  }

  Widget _sectionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Color? statusColor,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: iconColor.withOpacity(0.12),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: statusColor ?? Colors.grey.shade600),
        ),
        trailing: const Icon(Icons.chevron_left),
        onTap: onTap,
      ),
    );
  }
}
