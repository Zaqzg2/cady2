import 'invoice_item.dart';

enum InvoiceKind { sale, saleReturn } // فاتورة بيع / فاتورة مرتجع
enum PaymentMode { cash, credit } // نقد / آجل

class Invoice {
  String id;
  String docNumber; // رقم الفاتورة (قابل للتعديل مع استمرار الترقيم)
  DateTime date;
  InvoiceKind kind;
  PaymentMode paymentMode;
  String customerId;
  String customerName;
  List<InvoiceItem> items;
  double discountPercent;
  double discountAmount;
  String notes;
  String? signaturePath; // مسار صورة توقيع العميل (PNG)
  double balanceAfter; // رصيد مديونية العميل بعد هذه الفاتورة
  DateTime createdAt;
  bool printed; // تمت طباعتها مرة واحدة على الأقل
  bool shared; // تمت مشاركتها/إرسالها مرة واحدة على الأقل
  bool pinned; // مثبّتة أعلى سجل الفواتير والسندات

  Invoice({
    required this.id,
    required this.docNumber,
    required this.date,
    required this.kind,
    required this.paymentMode,
    required this.customerId,
    required this.customerName,
    required this.items,
    this.discountPercent = 0,
    this.discountAmount = 0,
    this.notes = '',
    this.signaturePath,
    this.balanceAfter = 0,
    DateTime? createdAt,
    this.printed = false,
    this.shared = false,
    this.pinned = false,
  }) : createdAt = createdAt ?? DateTime.now();

  double get subTotal => items.fold(0.0, (sum, it) => sum + it.total);

  double get discountValue {
    final byPercent = subTotal * (discountPercent / 100);
    return byPercent + discountAmount;
  }

  double get grandTotal {
    final t = subTotal - discountValue;
    return t < 0 ? 0 : t;
  }

  // فاتورة المرتجع تُخصم من مديونية العميل بدلاً من إضافتها
  double get effect => kind == InvoiceKind.saleReturn ? -grandTotal : grandTotal;

  Map<String, dynamic> toMap() => {
        'id': id,
        'docNumber': docNumber,
        'date': date.toIso8601String(),
        'kind': kind.name,
        'paymentMode': paymentMode.name,
        'customerId': customerId,
        'customerName': customerName,
        'items': items.map((e) => e.toMap()).toList(),
        'discountPercent': discountPercent,
        'discountAmount': discountAmount,
        'notes': notes,
        'signaturePath': signaturePath,
        'balanceAfter': balanceAfter,
        'createdAt': createdAt.toIso8601String(),
        'printed': printed,
        'shared': shared,
        'pinned': pinned,
      };

  factory Invoice.fromMap(Map<String, dynamic> m) => Invoice(
        id: m['id'] as String,
        docNumber: m['docNumber'] as String,
        date: DateTime.parse(m['date'] as String),
        kind: InvoiceKind.values.firstWhere((k) => k.name == m['kind']),
        paymentMode:
            PaymentMode.values.firstWhere((k) => k.name == m['paymentMode']),
        customerId: m['customerId'] as String,
        customerName: m['customerName'] as String,
        items: (m['items'] as List)
            .map((e) => InvoiceItem.fromMap(Map<String, dynamic>.from(e)))
            .toList(),
        discountPercent: (m['discountPercent'] as num?)?.toDouble() ?? 0,
        discountAmount: (m['discountAmount'] as num?)?.toDouble() ?? 0,
        notes: m['notes'] as String? ?? '',
        signaturePath: m['signaturePath'] as String?,
        balanceAfter: (m['balanceAfter'] as num?)?.toDouble() ?? 0,
        createdAt: DateTime.parse(m['createdAt'] as String),
        printed: m['printed'] as bool? ?? false,
        shared: m['shared'] as bool? ?? false,
        pinned: m['pinned'] as bool? ?? false,
      );
}
