import 'dart:typed_data';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
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
class PrintService {
  PrintService._();
  static final PrintService instance = PrintService._();

  /// الأجهزة المقترنة مسبقًا مع الهاتف (يجب إقران الطابعة أولًا من إعدادات
  /// بلوتوث النظام قبل ظهورها هنا)
  Future<List<PrinterDevice>> getPairedDevices() async {
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

  /// إرسال [bytes] فعليًا للطابعة مع تحقّق حقيقي من الاتصال، وليس فقط
  /// الاعتماد على connectionStatus.
  ///
  /// السبب الجذري للعطل المُبلَّغ عنه ("متصلة" بالإعدادات لكن الطباعة
  /// تفشل): مقبس بلوتوث أندرويد/iOS لا يوفر طريقة تسأل بها "هل ما زلت حيًا
  /// الآن فعلًا؟" — connectionStatus يعكس فقط "هل نجح connect() سابقًا ولم
  /// يُستدعَ disconnect() بعده"، حتى لو انقطع الاتصال فعليًا بصمت (قفل
  /// الشاشة، خمول لبضع دقائق، تذبذب الراديو...). الإصلاح السابق كان يعيد
  /// الاتصال فقط عندما تُرجع isConnected قيمة false — لكنها هنا بالذات
  /// تُرجع true بشكل خاطئ/قديم، فلا يُنفَّذ أي تعافٍ إطلاقًا، وتفشل الكتابة
  /// الفعلية لاحقًا بلا أي محاولة إنقاذ.
  ///
  /// الحل: لا نثق بـ connectionStatus وحدها. نحاول الاتصال إن لم نكن
  /// "متصلين" حسب آخر حالة معروفة، ثم نكتب فعليًا. إن فشلت الكتابة رغم ذلك
  /// (أي أن المقبس كان ميتًا بصمت)، نفرض إعادة اتصال كاملة (فصل ثم اتصال)
  /// بنفس العنوان المحفوظ ونعيد الكتابة مرة واحدة أخيرة قبل اعتبارها فشلت.
  Future<bool> _writeVerified(Uint8List bytes, String? printerMac) async {
    var connected = await isConnected;
    if (!connected && printerMac != null && printerMac.isNotEmpty) {
      connected = await connect(printerMac);
    }
    if (!connected) return false;

    var ok = await PrintBluetoothThermal.writeBytes(bytes);
    if (!ok && printerMac != null && printerMac.isNotEmpty) {
      await PrintBluetoothThermal.disconnect;
      if (await connect(printerMac)) {
        ok = await PrintBluetoothThermal.writeBytes(bytes);
      }
    }
    return ok;
  }

  /// أمر تهيئة ESC/POS صامت (ESC @) — لا يطبع شيئًا ولا يغذّي ورقًا مرئيًا،
  /// يُستخدم فقط للتحقق أن الكتابة الفعلية على المقبس تنجح.
  static final Uint8List _pingBytes = Uint8List.fromList(const [0x1B, 0x40]);

  /// تحقّق حقيقي من الاتصال بالطابعة عبر كتابة فعلية صغيرة، وليس
  /// connectionStatus وحدها (راجع شرح _writeVerified أعلاه). تستخدمها شاشة
  /// الإعدادات لعرض حالة "متصلة" تعكس فعلًا ما سيحدث عند الطباعة الحقيقية،
  /// بدل شارة متفائلة قد تكون كاذبة.
  Future<bool> verifyConnection(String? printerMac) =>
      _writeVerified(_pingBytes, printerMac);

  /// يحوّل أول صفحة من ملف PDF (المُصمَّم أصلاً بعرض 80مم) إلى صورة، ثم
  /// يطبعها عبر البلوتوث على طابعة 80مم حرارية متصلة مسبقًا، مع تحقّق
  /// واستعادة تلقائية للاتصال عبر _writeVerified (راجع توثيقها أعلاه).
  Future<bool> printPdfBytes(Uint8List pdfBytes, {String? printerMac}) async {
    // عرض 80مم عند 203 نقطة/إنش (الدقة القياسية لأغلب طابعات الإيصالات)
    // 80mm ≈ 3.15in => العرض بالبكسل ≈ 576
    const targetWidthPx = 576;

    img.Image? finalImage;

    await for (final page in Printing.raster(pdfBytes, dpi: 203)) {
      final pngBytes = await page.toPng();
      final decoded = img.decodePng(pngBytes);
      if (decoded == null) continue;
      final resized = img.copyResize(decoded, width: targetWidthPx);
      finalImage = resized; // فاتورة/سند عادة صفحة واحدة (roll80)
      break;
    }

    if (finalImage == null) return false;

    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile);
    List<int> bytes = [];
    bytes += generator.reset();
    bytes += generator.imageRaster(finalImage, align: PosAlign.center);
    bytes += generator.feed(2);
    bytes += generator.cut();

    return _writeVerified(Uint8List.fromList(bytes), printerMac);
  }
}
