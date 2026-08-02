import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/company_settings.dart';
import '../providers/app_provider.dart';

const _appColorChoices = <Color>[
  Color(0xFF00838F),
  Color(0xFFB71C1C),
  Color(0xFF1B5E20),
  Color(0xFF0D47A1),
  Color(0xFFE65100),
  Color(0xFF4A148C),
  Color(0xFF212121),
];

/// قسم "المظهر": وضع الثيم (تلقائي/فاتح/داكن)، لون واجهة التطبيق نفسه،
/// حجم خط الواجهة، والاهتزاز/الصوت عند الحفظ.
class SettingsAppearanceScreen extends StatelessWidget {
  const SettingsAppearanceScreen({super.key});

  Future<void> _update(BuildContext context, void Function(CompanySettings s) apply) async {
    final app = context.read<AppProvider>();
    final s = app.settings;
    apply(s);
    await app.saveSettings(s);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final s = app.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('المظهر')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('الوضع الليلي', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'system', label: Text('تلقائي'), icon: Icon(Icons.brightness_auto)),
              ButtonSegment(value: 'light', label: Text('فاتح'), icon: Icon(Icons.light_mode)),
              ButtonSegment(value: 'dark', label: Text('داكن'), icon: Icon(Icons.dark_mode)),
            ],
            selected: {s.themeModePref},
            onSelectionChanged: (v) => _update(context, (x) => x.themeModePref = v.first),
          ),
          const Divider(height: 36),

          const Text('لون واجهة التطبيق', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('يخص شاشات التطبيق فقط — منفصل عن لون هوية المستندات المطبوعة',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _appColorChoices.map((c) {
              final selected = c.value == s.appThemeColorValue;
              return GestureDetector(
                onTap: () => _update(context, (x) => x.appThemeColorValue = c.value),
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: c,
                  child: selected ? const Icon(Icons.check, color: Colors.white) : null,
                ),
              );
            }).toList(),
          ),
          const Divider(height: 36),

          const Text('حجم خط الواجهة', style: TextStyle(fontWeight: FontWeight.bold)),
          const Text('يخص نصوص شاشات التطبيق — غير خط الفاتورة المطبوعة',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('أ', style: TextStyle(fontSize: 14)),
              Expanded(
                child: Slider(
                  value: s.appFontScale,
                  min: 0.85,
                  max: 1.3,
                  divisions: 9,
                  label: '${(s.appFontScale * 100).round()}%',
                  onChanged: (v) => _update(context, (x) => x.appFontScale = v),
                ),
              ),
              const Text('أ', style: TextStyle(fontSize: 22)),
            ],
          ),
          const Divider(height: 36),

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('اهتزاز عند الحفظ الناجح'),
            value: s.vibrateOnSave,
            onChanged: (v) {
              _update(context, (x) => x.vibrateOnSave = v);
              if (v) HapticFeedback.mediumImpact();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('صوت تنبيه عند حفظ فاتورة/سند'),
            value: s.soundOnSave,
            onChanged: (v) {
              _update(context, (x) => x.soundOnSave = v);
              if (v) SystemSound.play(SystemSoundType.click);
            },
          ),
        ],
      ),
    );
  }
}
