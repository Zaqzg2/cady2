import 'dart:typed_data';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:printing/printing.dart';

import 'printer_device.dart';

/// خدمة الطباعة الحرارية 80مم عبر البلوتوث مباشرة (بدون تطبيقات وسيطة) —
/// النسخة الحقيقية لأندرويد/iOS/سطح المكتب. لا تُستخدم هذه النسخة إطلاقًا
/// على الويب (راجع print_service_web.dart وprint_service.dart).
///
/// السبب في طباعة "صورة" بدل نص ESC/POS مباشر: الطابعات الحرارية
/// تعتمد على صفحات ترميز (codepages) لا تدعم تشكيل الحروف العربية بشكل
/// صحيح. لذلك نحوّل نفس PDF المُنتَج فعليًا (نفس تصميم 80مم) إلى صورة
/// نقطية (raster) ثم نرسلها بأوامر ESC/POS كصورة — فتخرج مطابقة تمامًا
/// لما يظهر في PDF، بما في ذلك النصوص العربية والشعار والتوقيع.
///
/// ثلاث طبقات حماية ضد فشل الاتصال/الطباعة "الصامت" (راجع lastAttemptLog
/// لتشخيص أي حالة فعلية على أي جهاز):
/// 1) صلاحيات بلوتوث أندرويد 12+ تُطلَب صراحة قبل أي عملية (_ensurePermissions)
///    — كانت حزمة permission_handler مضافة بـ pubspec.yaml لكن غير
///    مُستخدَمة إطلاقًا في الكود، فإن رفض النظام الصلاحية بصمت (شائع بعد
///    إعادة تثبيت التطبيق أو تحديث أندرويد) كان كل شيء آخر سيفشل بلا تفسير.
/// 2) الكتابة الفعلية مجزّأة على دفعات صغيرة (_writeChunked) بدل دفعة واحدة
///    ضخمة، لأن صورة فاتورة كاملة قد تتجاوز عشرات الكيلوبايتات، وإرسالها
///    دفعة واحدة عبر Bluetooth Classic SPP يُفيض مخزن الطابعة المؤقت
///    المحدود على كثير من الطابعات الرخيصة فتفشل الكتابة أو تتوقف منتصف
///    الإرسال — مشكلة موثّقة شائعة تحديدًا مع طباعة الصور الكبيرة.
/// 3) تحقّق حقيقي من الاتصال (_writeVerified) بدل الاكتفاء بـ
///    connectionStatus وحدها: مقبس بلوتوث أندرويد/iOS لا يوفر طريقة تسأل
///    بها "هل ما زلت حيًا الآن فعلًا؟" — connectionStatus يعكس فقط "هل نجح
///    connect() سابقًا ولم يُستدعَ disconnect() بعده"، حتى لو انقطع الاتصال
///    فعليًا بصمت (قفل الشاشة، خمول لبضع دقائق، تذبذب الراديو...). لذلك لا
///    نثق بها وحدها؛ نكتب فعليًا، وإن فشلت الكتابة رغم "الاتصال"، نفرض
///    إعادة اتصال كاملة (فصل ثم اتصال) بنفس العنوان المحفوظ ونعيد الكتابة
///    مرة أخيرة قبل اعتبارها فشلت فعلًا.
class PrintService {
  PrintService._();
  static final PrintService instance = PrintService._();

  /// سجل خطوة-بخطوة (مع التوقيت بالمللي ثانية) لآخر محاولة طباعة أو تحقق
  /// اتصال. يُعرض للمستخدم عبر زر "التفاصيل" في رسالة الفشل (راجع
  /// showPrintDiagnosticsDialog في print_service.dart) بدل رسالة عامة واحدة
  /// لا تكفي لتحديد أين تحديدًا يفشل الاتصال على جهاز بعينه.
  final List<String> lastAttemptLog = [];
  String? lastError;
  DateTime? _attemptStart;

  void _resetLog() {
    lastAttemptLog.clear();
    lastError = null;
    _attemptStart = DateTime.now();
  }

  void _log(String msg) {
    final ms = _attemptStart == null
        ? 0
        : DateTime.now().difference(_attemptStart!).inMilliseconds;
    lastAttemptLog.add('+${ms}ms  $msg');
  }

  /// يطلب صلاحيات البلوتوث اللازمة على أندرويد 12+ (BLUETOOTH_CONNECT/SCAN)
  /// ويُسجّل النتيجة تشخيصيًا. لا يمنع المحاولة التالية حتى لو بدت الصلاحية
  /// مرفوضة (بعض قراءات الصلاحية غير دقيقة على أجهزة/إصدارات أقدم) — لكنه
  /// يجعل السبب الحقيقي ظاهرًا في السجل إن كانت هذه هي المشكلة فعلًا.
  ///
  /// ملاحظة لازمة خارج هذا الملف: التصريح بالصلاحية داخل
  /// android/app/src/main/AndroidManifest.xml شرط إضافي لازم — طلبها من
  /// الكود وحده لا يكفي إطلاقًا إن لم تكن مُعلنة هناك:
  ///   <uses-permission android:name="android.permission.BLUETOOTH_SCAN"
  ///       android:usesPermissionFlags="neverForLocation" />
  ///   <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
  ///   <uses-permission android:name="android.permission.BLUETOOTH"
  ///       android:maxSdkVersion="30" />
  ///   <uses-permission android:name="android.permission.BLUETOOTH_ADMIN"
  ///       android:maxSdkVersion="30" />
  Future<void> _ensurePermissions() async {
    try {
      final granted = await PrintBluetoothThermal.isPermissionBluetoothGranted;
      if (granted) {
        _log('صلاحية البلوتوث: ممنوحة ✓');
        return;
      }
      _log('صلاحية البلوتوث: غير ممنوحة — يُطلب الآن من النظام...');
      final statuses = await [
        Permission.bluetoothConnect,
        Permission.bluetoothScan,
      ].request();
      final granted2 = (statuses[Permission.bluetoothConnect]?.isGranted ?? true) &&
          (statuses[Permission.bluetoothScan]?.isGranted ?? true);
      _log('نتيجة طلب الصلاحية: '
          '${statuses.entries.map((e) => '${e.key}=${e.value}').join('، ')}'
          ' ⇒ ${granted2 ? "ممنوحة الآن" : "لا تزال مرفوضة — تحقق من إعدادات النظام > التطبيقات > كادي > الصلاحيات"}');
    } catch (e) {
      _log('⚠️ تعذّر التحقق من صلاحية البلوتوث (قد يكون الجهاز أقدم من أندرويد 12): $e');
    }
  }

  Future<List<PrinterDevice>> getPairedDevices() async {
    await _ensurePermissions();
    final list = await PrintBluetoothThermal.pairedBluetooths;
    return list
        .map((d) => PrinterDevice(name: d.name, macAddress: d.macAdress))
        .toList();
  }

  Future<bool> connect(String macAddress) async {
    return PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
  }

  Future<bool> get isConnected => PrintBluetoothThermal.connectionStatus;

  Future<void> disconnect() => PrintBluetoothThermal.disconnect;

  /// يكتب [bytes] على دفعات صغيرة بدل دفعة واحدة ضخمة (راجع الشرح أعلى
  /// الملف، البند 2). مهلة قصيرة بين كل دفعة والتالية تعطي الطابعة وقتًا
  /// لتفريغ مخزنها المؤقت قبل استقبال المزيد.
  Future<bool> _writeChunked(Uint8List bytes) async {
    const chunkSize = 1024;
    if (bytes.length <= chunkSize) {
      final ok = await PrintBluetoothThermal.writeBytes(bytes);
      _log('كتابة ${bytes.length} بايت (دفعة واحدة): ${ok ? "نجحت" : "فشلت"}');
      return ok;
    }
    var offset = 0;
    var chunkIndex = 0;
    final totalChunks = (bytes.length / chunkSize).ceil();
    while (offset < bytes.length) {
      final end =
          (offset + chunkSize < bytes.length) ? offset + chunkSize : bytes.length;
      final chunk = bytes.sublist(offset, end);
      chunkIndex++;
      bool ok;
      try {
        ok = await PrintBluetoothThermal.writeBytes(chunk);
      } catch (e) {
        _log('❌ استثناء أثناء كتابة الدفعة $chunkIndex/$totalChunks: $e');
        return false;
      }
      if (!ok) {
        _log('❌ فشلت كتابة الدفعة $chunkIndex/$totalChunks عند البايت $offset');
        return false;
      }
      offset = end;
      await Future.delayed(const Duration(milliseconds: 12));
    }
    _log('كتابة ${bytes.length} بايت على $totalChunks دفعة: نجحت جميعها ✓');
    return true;
  }

  /// إرسال [bytes] فعليًا مع تحقّق حقيقي من الاتصال ومعالجة كاملة
  /// للاستثناءات (راجع الشرح أعلى الملف، البند 3). يُسجّل كل خطوة في
  /// lastAttemptLog بدل أن ينهار الاستدعاء بصمت أو يُعيد فقط true/false بلا
  /// تفسير.
  Future<bool> _writeVerified(Uint8List bytes, String? printerMac) async {
    try {
      await _ensurePermissions();

      var connected = await isConnected;
      _log('isConnected قبل المحاولة: $connected');
      if (!connected && printerMac != null && printerMac.isNotEmpty) {
        _log('محاولة اتصال بـ $printerMac...');
        connected = await connect(printerMac);
        _log('نتيجة connect(): $connected');
      }
      if (!connected) {
        _log('❌ فشل نهائي: لا يوجد اتصال حي، ولا عنوان طابعة محفوظ لإعادة المحاولة');
        lastError = 'لا يوجد اتصال بالطابعة';
        return false;
      }

      var ok = await _writeChunked(bytes);
      if (!ok && printerMac != null && printerMac.isNotEmpty) {
        _log('الكتابة فشلت رغم أن الحالة كانت "متصلة" — هذا يعني أن المقبس '
            'كان ميتًا بصمت. إعادة اتصال كاملة كمحاولة أخيرة...');
        try {
          await PrintBluetoothThermal.disconnect;
        } catch (e) {
          _log('⚠️ استثناء أثناء disconnect(): $e');
        }
        final reconnected = await connect(printerMac);
        _log('نتيجة إعادة الاتصال: $reconnected');
        if (reconnected) {
          ok = await _writeChunked(bytes);
        }
      }
      if (!ok) lastError = 'فشلت الكتابة على المقبس رغم محاولات إعادة الاتصال';
      _log(ok ? '✅ نجحت الكتابة النهائية' : '❌ فشلت الكتابة نهائيًا');
      return ok;
    } catch (e) {
      _log('❌ استثناء غير متوقع لم تتم معالجته: $e');
      lastError = e.toString();
      return false;
    }
  }

  /// أمر تهيئة ESC/POS صامت (ESC @) — لا يطبع شيئًا ولا يغذّي ورقًا مرئيًا،
  /// يُستخدم فقط للتحقق أن الكتابة الفعلية على المقبس تنجح.
  static final Uint8List _pingBytes = Uint8List.fromList(const [0x1B, 0x40]);

  /// تحقّق حقيقي من الاتصال بالطابعة عبر كتابة فعلية صغيرة، وليس
  /// connectionStatus وحدها. تستخدمها شاشة الإعدادات لعرض حالة "متصلة"
  /// تعكس فعلًا ما سيحدث عند الطباعة الحقيقية، بدل شارة متفائلة قد تكون
  /// كاذبة (هذا بالضبط ما كان يُنتج "متصلة" بالإعدادات مع فشل الطباعة).
  Future<bool> verifyConnection(String? printerMac) async {
    _resetLog();
    _log('— بدء تحقق اتصال حقيقي —');
    return _writeVerified(_pingBytes, printerMac);
  }

  /// يحوّل أول صفحة من ملف PDF (المُصمَّم أصلاً بعرض 80مم) إلى صورة، ثم
  /// يطبعها عبر البلوتوث على طابعة 80مم حرارية متصلة مسبقًا، مع كل طبقات
  /// الحماية الثلاث الموثّقة أعلى الملف.
  Future<bool> printPdfBytes(Uint8List pdfBytes, {String? printerMac}) async {
    _resetLog();
    _log('— بدء طباعة (PDF: ${pdfBytes.length} بايت) —');

    // عرض 80مم عند 203 نقطة/إنش (الدقة القياسية لأغلب طابعات الإيصالات)
    // 80mm ≈ 3.15in => العرض بالبكسل ≈ 576
    const targetWidthPx = 576;

    img.Image? finalImage;
    try {
      await for (final page in Printing.raster(pdfBytes, dpi: 203)) {
        final pngBytes = await page.toPng();
        final decoded = img.decodePng(pngBytes);
        if (decoded == null) continue;
        finalImage = img.copyResize(decoded, width: targetWidthPx);
        break; // فاتورة/سند عادة صفحة واحدة (roll80)
      }
    } catch (e) {
      _log('❌ فشل تحويل PDF إلى صورة: $e');
      lastError = 'فشل تحويل الفاتورة إلى صورة قابلة للطباعة';
      return false;
    }

    if (finalImage == null) {
      _log('❌ فشل تحويل PDF إلى صورة (نتيجة فارغة بلا استثناء)');
      lastError = 'فشل تحويل الفاتورة إلى صورة قابلة للطباعة';
      return false;
    }
    _log('تم تحويل PDF إلى صورة ${finalImage.width}×${finalImage.height}');

    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile);
    List<int> bytes = [];
    bytes += generator.reset();
    bytes += generator.imageRaster(finalImage, align: PosAlign.center);
    bytes += generator.feed(2);
    bytes += generator.cut();
    final payload = Uint8List.fromList(bytes);
    _log('حجم أوامر ESC/POS النهائية: ${payload.length} بايت');

    return _writeVerified(payload, printerMac);
  }
}
