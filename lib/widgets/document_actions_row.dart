import 'package:flutter/material.dart';

/// شريط أيقونات موحّد للإجراءات الأكثر استخدامًا يوميًا على أي مستند
/// (فاتورة/سند/كشف حساب): طباعة، مشاركة، معاينة، تحميل، تعديل.
/// يُستخدم كـ widget واحد قابل لإعادة الاستخدام بدل تكرار نفس الأزرار
/// بكل شاشة على حدة، لضمان تناسق الشكل والسلوك في كل مكان.
class DocumentActionsRow extends StatelessWidget {
  final VoidCallback onPrint;
  final VoidCallback onShare;
  final VoidCallback onPreview;
  final VoidCallback onDownload;
  final VoidCallback? onEdit;

  /// شكل مصغّر (بدون تسميات نصية) يستخدم داخل الرف اللاصق أسفل الشاشة
  final bool compact;

  const DocumentActionsRow({
    super.key,
    required this.onPrint,
    required this.onShare,
    required this.onPreview,
    required this.onDownload,
    this.onEdit,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final items = <_ActionSpec>[
      _ActionSpec(Icons.print_outlined, 'طباعة', onPrint),
      _ActionSpec(Icons.share_outlined, 'مشاركة', onShare),
      _ActionSpec(Icons.visibility_outlined, 'معاينة', onPreview),
      _ActionSpec(Icons.download_outlined, 'تحميل', onDownload),
      if (onEdit != null) _ActionSpec(Icons.edit_outlined, 'تعديل', onEdit!),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: items.map((a) => _ActionButton(spec: a, compact: compact)).toList(),
    );
  }
}

class _ActionSpec {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  _ActionSpec(this.icon, this.label, this.onTap);
}

class _ActionButton extends StatelessWidget {
  final _ActionSpec spec;
  final bool compact;
  const _ActionButton({required this.spec, required this.compact});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: spec.onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
            vertical: compact ? 4 : 8, horizontal: compact ? 8 : 10),
        child: compact
            ? Icon(spec.icon, size: 22)
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(spec.icon, size: 22),
                  const SizedBox(height: 3),
                  Text(spec.label, style: const TextStyle(fontSize: 11)),
                ],
              ),
      ),
    );
  }
}
