import 'dart:io';
import 'package:path_provider/path_provider.dart';

import 'db_service.dart';
import 'settings_service.dart';

/// تنظيف صور التوقيع (sig_*.png) غير المرتبطة بأي فاتورة أو سند حالي ولا
/// بالتوقيع الافتراضي المحفوظ للمندوب — لتحرير المساحة المستخدمة
class CleanupService {
  static Future<int> cleanUnusedSignatures() async {
    final invoices = await DbService.instance.getInvoices();
    final receipts = await DbService.instance.getReceipts();
    final settings = await SettingsService.instance.load();

    final used = <String>{
      ...invoices.map((i) => i.signaturePath).whereType<String>(),
      ...receipts.map((r) => r.repSignaturePath).whereType<String>(),
      if (settings.defaultRepSignaturePath != null)
        settings.defaultRepSignaturePath!,
    };

    int deleted = 0;
    final dir = await getApplicationDocumentsDirectory();
    if (!await dir.exists()) return 0;
    for (final entity in dir.listSync()) {
      if (entity is File &&
          entity.path.contains('/sig_') &&
          entity.path.endsWith('.png') &&
          !used.contains(entity.path)) {
        try {
          await entity.delete();
          deleted++;
        } catch (_) {}
      }
    }
    return deleted;
  }
}
