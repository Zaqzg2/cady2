import 'package:flutter/material.dart';

import '../models/invoice.dart';
import '../models/receipt.dart';

/// تمثيل موحّد لصف واحد في أي قائمة تعرض فواتير وسندات معًا
/// (سجل المستندات، آخر العمليات بالصفحة الرئيسية...).
class DocRow {
  final DateTime date;
  final String title;
  final String docNumber;
  final String docId;
  final String customerId;
  final String customerName;
  final double amount;
  final double balanceAfter;
  final Color color;
  final IconData icon;
  final bool printed;
  final bool shared;
  final bool pinned;
  final bool hasAttachment;
  final Invoice? invoice;
  final Receipt? receipt;

  DocRow({
    required this.date,
    required this.title,
    required this.docNumber,
    required this.docId,
    required this.customerId,
    required this.customerName,
    required this.amount,
    required this.balanceAfter,
    required this.color,
    required this.icon,
    required this.printed,
    required this.shared,
    required this.pinned,
    required this.hasAttachment,
    this.invoice,
    this.receipt,
  });

  factory DocRow.invoice(Invoice i) => DocRow(
        date: i.date,
        title: i.kind == InvoiceKind.sale ? 'فاتورة بيع' : 'فاتورة مرتجع',
        docNumber: i.docNumber,
        docId: i.id,
        customerId: i.customerId,
        customerName: i.customerName,
        amount: i.grandTotal,
        balanceAfter: i.balanceAfter,
        color: i.kind == InvoiceKind.sale ? Colors.blue : Colors.orange,
        icon: i.kind == InvoiceKind.sale ? Icons.point_of_sale : Icons.assignment_return,
        printed: i.printed,
        shared: i.shared,
        pinned: i.pinned,
        hasAttachment: (i.signaturePath ?? '').isNotEmpty,
        invoice: i,
      );

  factory DocRow.receipt(Receipt r) => DocRow(
        date: r.date,
        title: 'سند قبض',
        docNumber: r.docNumber,
        docId: r.id,
        customerId: r.customerId,
        customerName: r.customerName,
        amount: r.amount,
        balanceAfter: r.balanceAfter,
        color: Colors.green,
        icon: Icons.payments,
        printed: r.printed,
        shared: r.shared,
        pinned: r.pinned,
        hasAttachment: (r.repSignaturePath ?? '').isNotEmpty,
        receipt: r,
      );
}
