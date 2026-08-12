/// واجهة موحّدة للطباعة تختار تلقائيًا التنفيذ المناسب حسب المنصة وقت
/// الترجمة (compile time) — بدون أي فرع كود يدوي في باقي التطبيق:
/// - على أندرويد/iOS/سطح المكتب (dart:io متاحة): طباعة حرارية بلوتوث حقيقية.
/// - على الويب (dart:io غير متاحة): حوار طباعة المتصفح الأصلي.
///
/// كل الشاشات تستورد هذا الملف فقط، ولا تستورد print_bluetooth_thermal
/// مباشرة أبدًا — هذا يضمن أن كود الويب لا "يرى" تلك الحزمة غير المدعومة
/// على الويب إطلاقًا.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'print_service_web.dart' if (dart.library.io) 'print_service_io.dart';

export 'printer_device.dart';
export 'print_service_web.dart' if (dart.library.io) 'print_service_io.dart';

/// يعرض نتيجة طباعة موحّدة لكل شاشات التطبيق. عند الفشل، يضيف زر "التفاصيل"
/// يفتح سجل PrintService.instance.lastAttemptLog كاملاً (راجع
/// showPrintDiagnosticsDialog أدناه) — بدل رسالة عامة واحدة متكرّرة في 6
/// أماكن مختلفة بالتطبيق لا تكفي لتشخيص أين تحديدًا تفشل كل حالة.
void showPrintResultSnack(BuildContext context, bool ok) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  if (ok) {
    messenger.showSnackBar(const SnackBar(content: Text('تمت الطباعة')));
    return;
  }
  messenger.showSnackBar(SnackBar(
    content: const Text('تعذّر الاتصال بالطابعة'),
    duration: const Duration(seconds: 6),
    action: SnackBarAction(
      label: 'التفاصيل',
      onPressed: () => showPrintDiagnosticsDialog(context),
    ),
  ));
}

/// حوار يعرض سجل آخر محاولة طباعة/اتصال خطوة بخطوة (بالتوقيت وأي استثناء
/// فعلي حدث)، مع زر نسخ لإرسال النص كاملاً عند طلب دعم فني. هذا يستبدل
/// رسالة "تعذّر الاتصال بالطابعة" العامة التي لا تُبيّن أين تحديدًا يفشل
/// الاتصال (صلاحيات؟ مقبس ميت؟ حجم البيانات؟ استثناء غير متوقع؟).
Future<void> showPrintDiagnosticsDialog(BuildContext context) async {
  final log = PrintService.instance.lastAttemptLog;
  final text = log.isEmpty
      ? 'لا يوجد سجل بعد — جرّب الطباعة أو الاتصال مرة أخرى ثم افتح التفاصيل.'
      : log.join('\n');
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('تفاصيل محاولة الاتصال'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: SelectableText(
            text,
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            textDirection: TextDirection.ltr,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(ctx)
                .showSnackBar(const SnackBar(content: Text('تم نسخ التفاصيل')));
          },
          child: const Text('نسخ'),
        ),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
      ],
    ),
  );
}
