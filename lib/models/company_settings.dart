import 'package:flutter/material.dart';

class ColumnConfig {
  String key; // productName / quantity / price / total
  String label;
  double widthFlex;
  bool visible;

  ColumnConfig({
    required this.key,
    required this.label,
    this.widthFlex = 1,
    this.visible = true,
  });

  Map<String, dynamic> toMap() => {
        'key': key,
        'label': label,
        'widthFlex': widthFlex,
        'visible': visible,
      };

  factory ColumnConfig.fromMap(Map<String, dynamic> m) => ColumnConfig(
        key: m['key'] as String,
        label: m['label'] as String,
        widthFlex: (m['widthFlex'] as num?)?.toDouble() ?? 1,
        visible: m['visible'] as bool? ?? true,
      );
}

class CompanySettings {
  // ---------------- 1) هويتي التجارية ----------------
  String companyName;
  String companyPhone;
  String companyAddress;
  String? logoPath;
  String repName;
  String repPhone;

  /// مسار صورة توقيع المندوب المحفوظ مسبقًا (بدل توقيعه يدويًا بكل سند)
  String? repSignaturePath;

  /// لون الهوية التجارية — يُطبّق على عناصر الفواتير/السندات/كشف الحساب
  /// المطبوعة (لون الخط البارز والفواصل)، بصرف النظر عن لون واجهة التطبيق.
  int identityColorValue;

  /// نص ثابت يظهر أسفل كل فاتورة (قابل للتخصيص)
  String footerText;

  // ---------------- 2) الطباعة والفاتورة ----------------
  double tableFontSize;
  double rowSpacing;
  List<ColumnConfig> tableColumns;

  /// خط عام للمستند كامل (رأس/بيانات العميل/تذييل) — منفصل عن خط جدول
  /// الأصناف فقط.
  double docFontSize;
  double docLineSpacing;

  String? printerAddress; // عنوان MAC لطابعة البلوتوث المحفوظة
  String? printerName;

  /// الصيغة الافتراضية لطباعة كشف الحساب عند فتح شاشة عميل جديدة
  bool defaultStatement80mm;

  // ---------------- 3) المظهر ----------------
  bool darkMode; // محفوظ للتوافق مع نسخ سابقة فقط
  /// 'system' / 'light' / 'dark'
  String themeModePref;

  /// لون واجهة التطبيق نفسه (Seed Color) — مستقل عن لون الهوية بالمستندات
  int appThemeColorValue;

  double appFontScale;
  bool vibrateOnSave;
  bool soundOnSave;

  // ---------------- 4) الخصوصية والأمان ----------------
  /// دقائق الخمول قبل القفل التلقائي: 0=فورًا، -1=أبدًا
  int autoLockMinutes;
  bool biometricEnabled;
  bool hideAmountsInRecents;

  // ---------------- 5) البيانات والنسخ الاحتياطي ----------------
  bool autoBackupEnabled;
  int autoBackupFrequencyDays;

  CompanySettings({
    this.companyName = 'كادي للمنظفات',
    this.companyPhone = '',
    this.companyAddress = '',
    this.logoPath,
    this.repName = '',
    this.repPhone = '',
    this.repSignaturePath,
    this.identityColorValue = 0xFF00838F,
    this.footerText = 'شكرًا لتعاملكم معنا',
    this.tableFontSize = 9,
    this.rowSpacing = 4,
    List<ColumnConfig>? tableColumns,
    this.docFontSize = 9,
    this.docLineSpacing = 4,
    this.printerAddress,
    this.printerName,
    this.defaultStatement80mm = false,
    this.darkMode = false,
    this.themeModePref = 'light',
    this.appThemeColorValue = 0xFF00838F,
    this.appFontScale = 1.0,
    this.vibrateOnSave = true,
    this.soundOnSave = false,
    this.autoLockMinutes = -1,
    this.biometricEnabled = false,
    this.hideAmountsInRecents = false,
    this.autoBackupEnabled = false,
    this.autoBackupFrequencyDays = 7,
  }) : tableColumns = tableColumns ??
            [
              ColumnConfig(key: 'productName', label: 'الصنف', widthFlex: 3),
              ColumnConfig(key: 'quantity', label: 'الكمية', widthFlex: 1),
              ColumnConfig(key: 'price', label: 'السعر', widthFlex: 1.2),
              ColumnConfig(key: 'total', label: 'الإجمالي', widthFlex: 1.4),
            ];

  Color get identityColor => Color(identityColorValue);
  Color get appThemeColor => Color(appThemeColorValue);

  Map<String, dynamic> toJson() => {
        'companyName': companyName,
        'companyPhone': companyPhone,
        'companyAddress': companyAddress,
        'logoPath': logoPath,
        'repName': repName,
        'repPhone': repPhone,
        'repSignaturePath': repSignaturePath,
        'identityColorValue': identityColorValue,
        'footerText': footerText,
        'tableFontSize': tableFontSize,
        'rowSpacing': rowSpacing,
        'tableColumns': tableColumns.map((c) => c.toMap()).toList(),
        'docFontSize': docFontSize,
        'docLineSpacing': docLineSpacing,
        'printerAddress': printerAddress,
        'printerName': printerName,
        'defaultStatement80mm': defaultStatement80mm,
        'darkMode': darkMode,
        'themeModePref': themeModePref,
        'appThemeColorValue': appThemeColorValue,
        'appFontScale': appFontScale,
        'vibrateOnSave': vibrateOnSave,
        'soundOnSave': soundOnSave,
        'autoLockMinutes': autoLockMinutes,
        'biometricEnabled': biometricEnabled,
        'hideAmountsInRecents': hideAmountsInRecents,
        'autoBackupEnabled': autoBackupEnabled,
        'autoBackupFrequencyDays': autoBackupFrequencyDays,
      };

  factory CompanySettings.fromJson(Map<String, dynamic> m) => CompanySettings(
        companyName: m['companyName'] as String? ?? 'كادي للمنظفات',
        companyPhone: m['companyPhone'] as String? ?? '',
        companyAddress: m['companyAddress'] as String? ?? '',
        logoPath: m['logoPath'] as String?,
        repName: m['repName'] as String? ?? '',
        repPhone: m['repPhone'] as String? ?? '',
        repSignaturePath: m['repSignaturePath'] as String?,
        identityColorValue: (m['identityColorValue'] as num?)?.toInt() ?? 0xFF00838F,
        footerText: m['footerText'] as String? ?? 'شكرًا لتعاملكم معنا',
        tableFontSize: (m['tableFontSize'] as num?)?.toDouble() ?? 9,
        rowSpacing: (m['rowSpacing'] as num?)?.toDouble() ?? 4,
        tableColumns: (m['tableColumns'] as List?)
                ?.map((e) => ColumnConfig.fromMap(Map<String, dynamic>.from(e)))
                .toList() ??
            [],
        docFontSize: (m['docFontSize'] as num?)?.toDouble() ?? 9,
        docLineSpacing: (m['docLineSpacing'] as num?)?.toDouble() ?? 4,
        printerAddress: m['printerAddress'] as String?,
        printerName: m['printerName'] as String?,
        defaultStatement80mm: m['defaultStatement80mm'] as bool? ?? false,
        darkMode: m['darkMode'] as bool? ?? false,
        themeModePref: m['themeModePref'] as String? ??
            ((m['darkMode'] as bool? ?? false) ? 'dark' : 'light'),
        appThemeColorValue:
            (m['appThemeColorValue'] as num?)?.toInt() ?? 0xFF00838F,
        appFontScale: (m['appFontScale'] as num?)?.toDouble() ?? 1.0,
        vibrateOnSave: m['vibrateOnSave'] as bool? ?? true,
        soundOnSave: m['soundOnSave'] as bool? ?? false,
        autoLockMinutes: (m['autoLockMinutes'] as num?)?.toInt() ?? -1,
        biometricEnabled: m['biometricEnabled'] as bool? ?? false,
        hideAmountsInRecents: m['hideAmountsInRecents'] as bool? ?? false,
        autoBackupEnabled: m['autoBackupEnabled'] as bool? ?? false,
        autoBackupFrequencyDays:
            (m['autoBackupFrequencyDays'] as num?)?.toInt() ?? 7,
      );
}
