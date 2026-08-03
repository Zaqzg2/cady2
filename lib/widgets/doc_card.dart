import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../models/doc_row.dart';
import '../utils/formatters.dart';

/// بطاقة مستند واحدة (فاتورة/سند) — تُستخدم في سجل الفواتير والسندات
/// وفي قسم "آخر العمليات" بالصفحة الرئيسية.
/// أيقونة دائرية 48×48، ثلاثة أسطر معلومات، شارات حالة مختصرة،
/// وزرا "تفاصيل/طباعة" أسفل البطاقة.
class DocCard extends StatelessWidget {
  final DocRow row;
  final VoidCallback onTap;
  final VoidCallback onIconTap;
  final VoidCallback? onLongPress;
  final VoidCallback onDetails;
  final VoidCallback onPrint;
  final VoidCallback? onQuickPreview;
  final VoidCallback? onShare;
  final VoidCallback? onEdit;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;

  /// تعطيل إيماءات السحب (تُستخدم بالقائمة المختصرة "آخر العمليات")
  final bool enableSwipe;

  const DocCard({
    super.key,
    required this.row,
    required this.onTap,
    required this.onIconTap,
    this.onLongPress,
    required this.onDetails,
    required this.onPrint,
    this.onQuickPreview,
    this.onShare,
    this.onEdit,
    this.onDuplicate,
    this.onDelete,
    this.enableSwipe = true,
  });

  @override
  Widget build(BuildContext context) {
    final card = _card(context);
    if (!enableSwipe) return card;

    return Slidable(
      key: ValueKey(row.docId),
      // سحب من الحافة اليمنى (RTL) — جزئي: معاينة/طباعة/مشاركة
      startActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.56,
        children: [
          SlidableAction(
            onPressed: (_) => (onQuickPreview ?? onIconTap)(),
            backgroundColor: Colors.indigo.shade400,
            foregroundColor: Colors.white,
            icon: Icons.visibility_outlined,
            label: 'معاينة',
          ),
          SlidableAction(
            onPressed: (_) => onPrint(),
            backgroundColor: Colors.green.shade600,
            foregroundColor: Colors.white,
            icon: Icons.print_outlined,
            label: 'طباعة',
          ),
          if (onShare != null)
            SlidableAction(
              onPressed: (_) => onShare!(),
              backgroundColor: Colors.teal.shade600,
              foregroundColor: Colors.white,
              icon: Icons.share_outlined,
              label: 'مشاركة',
            ),
        ],
      ),
      // سحب من الحافة اليسرى — كامل: تعديل/تكرار/حذف
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: 0.62,
        children: [
          if (onEdit != null)
            SlidableAction(
              onPressed: (_) => onEdit!(),
              backgroundColor: Colors.blueGrey.shade400,
              foregroundColor: Colors.white,
              icon: Icons.edit_outlined,
              label: 'تعديل',
            ),
          if (onDuplicate != null)
            SlidableAction(
              onPressed: (_) => onDuplicate!(),
              backgroundColor: Colors.purple.shade400,
              foregroundColor: Colors.white,
              icon: Icons.copy_all_outlined,
              label: 'تكرار',
            ),
          if (onDelete != null)
            SlidableAction(
              onPressed: (_) => onDelete!(),
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              icon: Icons.delete_outline,
              label: 'حذف',
            ),
        ],
      ),
      child: card,
    );
  }

  Widget _card(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: onIconTap,
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration:
                          BoxDecoration(color: row.color.withOpacity(0.15), shape: BoxShape.circle),
                      child: Icon(row.icon, color: row.color),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (row.pinned) ...[
                              const Icon(Icons.star, size: 14, color: Colors.amber),
                              const SizedBox(width: 3),
                            ],
                            Expanded(
                              child: Text('${row.title} #${row.docNumber}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 13.5),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(left: 4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: (row.printed && row.shared)
                                    ? Colors.green
                                    : Colors.red.shade400,
                              ),
                            ),
                            Flexible(
                              child: Text(row.customerName,
                                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(Formatters.dt(row.date),
                            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                        const SizedBox(height: 2),
                        Text('الرصيد بعد العملية: ${Formatters.money(row.balanceAfter)}',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 2,
                children: [
                  if (row.receipt != null) _badge('🟢 تم التحصيل', Colors.green),
                  if (!row.printed) _badge('🟡 غير مطبوع', Colors.amber.shade800),
                  if (!row.shared) _badge('🔴 غير مرسل', Colors.red),
                  if (row.hasAttachment) _badge('📎 مرفق', Colors.blueGrey),
                ],
              ),
              const Divider(height: 14),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: onDetails,
                    icon: const Icon(Icons.visibility_outlined, size: 17),
                    label: const Text('تفاصيل', style: TextStyle(fontSize: 12.5)),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  ),
                  const SizedBox(width: 14),
                  TextButton.icon(
                    onPressed: onPrint,
                    icon: const Icon(Icons.print_outlined, size: 17),
                    label: const Text('طباعة', style: TextStyle(fontSize: 12.5)),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration:
          BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 10.5, color: color)),
    );
  }
}
