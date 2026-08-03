/// ملاحظة نصية مرتبطة بعميل، تظهر ضمن سجل النشاط في صفحة العميل
/// (لا تؤثر على الرصيد أو كشف الحساب المالي).
class CustomerNote {
  final String id;
  final String customerId;
  final DateTime date;
  final String text;

  CustomerNote({
    required this.id,
    required this.customerId,
    required this.date,
    required this.text,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'customerId': customerId,
        'date': date.toIso8601String(),
        'text': text,
      };

  factory CustomerNote.fromMap(Map<String, dynamic> m) => CustomerNote(
        id: m['id'] as String,
        customerId: m['customerId'] as String,
        date: DateTime.parse(m['date'] as String),
        text: m['text'] as String? ?? '',
      );
}
