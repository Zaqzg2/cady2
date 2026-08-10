import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/customer.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/receipt.dart';
import 'db_service.dart';

/// طبقة مزامنة سحابية اختيارية تعمل فوق Hive — لا تُستخدم كمصدر قراءة
/// مباشر لأي شاشة، وكل الشاشات تستمر تتعامل مع DbService/Hive كما هي
/// تمامًا (يعني التطبيق يشتغل 100% بدون إنترنت زي ما هو الحال الآن).
///
/// وظيفتها فقط: كل ما DbService يخزّن سجل محليًا، تدفعه بالخلفية إلى
/// Firestore (fire-and-forget، ما توقف أي عملية محلية إذا فشلت أو ما
/// كان في نت)، وبالمقابل تستمع realtime لأي تغيير يجي من جهاز ثاني
/// وتدمجه تلقائيًا داخل Hive عبر نفس دوال DbService.upsert*/delete*.
///
/// إذا Firebase غير مُهيّأ بعد (قبل تشغيل flutterfire configure، أو فشلت
/// التهيئة) كل الدوال هنا تتجاهل نفسها بصمت — بدون ما تكسر شي.
class CloudSyncService {
  CloudSyncService._();
  static final CloudSyncService instance = CloudSyncService._();

  final List<StreamSubscription> _subs = [];
  bool _listening = false;

  /// null إذا Firebase غير مُهيّأ بعد (بدل ما نستدعي FirebaseFirestore.instance
  /// مباشرة ونطيح بخطأ فوري وقت التشغيل)
  FirebaseFirestore? get _dbOrNull =>
      Firebase.apps.isEmpty ? null : FirebaseFirestore.instance;

  // ---------------- دفع تغيير محلي إلى السحابة ----------------
  Future<void> pushCustomer(Customer c) => _push('customers', c.id, c.toMap());
  Future<void> pushProduct(Product p) => _push('products', p.id, p.toMap());
  Future<void> pushInvoice(Invoice i) => _push('invoices', i.id, i.toMap());
  Future<void> pushReceipt(Receipt r) => _push('receipts', r.id, r.toMap());

  Future<void> pushDeleteCustomer(String id) => _pushDelete('customers', id);
  Future<void> pushDeleteProduct(String id) => _pushDelete('products', id);
  Future<void> pushDeleteInvoice(String id) => _pushDelete('invoices', id);
  Future<void> pushDeleteReceipt(String id) => _pushDelete('receipts', id);

  Future<void> _push(String collection, String id, Map<String, dynamic> data) async {
    final db = _dbOrNull;
    if (db == null) return;
    try {
      await db.collection(collection).doc(id).set(data);
    } catch (e) {
      // فشل الدفع (بدون نت / صلاحيات) لا يوقف أي شيء محليًا — Firestore
      // SDK أصلاً يخزّن العملية محليًا ويعيد إرسالها تلقائيًا عند عودة النت
      debugPrint('CloudSync push($collection/$id) failed: $e');
    }
  }

  Future<void> _pushDelete(String collection, String id) async {
    final db = _dbOrNull;
    if (db == null) return;
    try {
      await db.collection(collection).doc(id).delete();
    } catch (e) {
      debugPrint('CloudSync delete($collection/$id) failed: $e');
    }
  }

  // ---------------- الاستماع للتغييرات الواردة من أجهزة ثانية ----------------
  /// تُستدعى مرة وحدة بعد Firebase.initializeApp() الناجحة (من main.dart)
  void startListening() {
    if (_listening) return;
    final db = _dbOrNull;
    if (db == null) return;
    _listening = true;

    _subs.add(_watch(db, 'customers', (data) => DbService.instance.upsertCustomer(Customer.fromMap(data)),
        (id) => DbService.instance.deleteCustomer(id)));
    _subs.add(_watch(db, 'products', (data) => DbService.instance.upsertProduct(Product.fromMap(data)),
        (id) => DbService.instance.deleteProduct(id)));
    _subs.add(_watch(db, 'invoices', (data) => DbService.instance.upsertInvoice(Invoice.fromMap(data)),
        (id) => DbService.instance.deleteInvoice(id)));
    _subs.add(_watch(db, 'receipts', (data) => DbService.instance.upsertReceipt(Receipt.fromMap(data)),
        (id) => DbService.instance.deleteReceipt(id)));
  }

  StreamSubscription _watch(
    FirebaseFirestore db,
    String collection,
    Future<void> Function(Map<String, dynamic> data) onUpsert,
    Future<void> Function(String id) onDelete,
  ) {
    return db.collection(collection).snapshots().listen((snap) async {
      for (final change in snap.docChanges) {
        try {
          if (change.type == DocumentChangeType.removed) {
            await onDelete(change.doc.id);
          } else {
            final data = change.doc.data();
            if (data != null) await onUpsert(data);
          }
        } catch (e) {
          debugPrint('CloudSync merge($collection/${change.doc.id}) failed: $e');
        }
      }
    }, onError: (e) => debugPrint('CloudSync listen($collection) error: $e'));
  }

  void stopListening() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _listening = false;
  }
}
