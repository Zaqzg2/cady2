import 'package:flutter/services.dart';
import '../models/company_settings.dart';

/// تنبيه بسيط (اهتزاز و/أو صوت نظام) عند نجاح حفظ فاتورة أو سند، حسب
/// تفضيلات المستخدم بالإعدادات. يستخدم واجهات Flutter المدمجة فقط
/// (بدون حزم إضافية) لتفادي أي تعقيد صلاحيات إضافي.
class SaveFeedback {
  static Future<void> play(CompanySettings settings) async {
    if (settings.vibrateOnSave) {
      HapticFeedback.mediumImpact();
    }
    if (settings.soundOnSave) {
      SystemSound.play(SystemSoundType.click);
    }
  }
}
