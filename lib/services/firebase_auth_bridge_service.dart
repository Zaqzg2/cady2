import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// يربط كل حساب محلي (UserAccount) بحساب Firebase Auth مقابل له —
/// الهدف الوحيد إفادة Firestore security rules (تعرف مين يكتب/يقرأ شنو)،
/// وليس بديلاً عن نظام الدخول المحلي (AccountService) اللي يبقى هو
/// المتحكم الفعلي بمن يدخل التطبيق ومحليًا بدون نت دايمًا.
///
/// بما إن Firebase Auth ما فيه بريد إلكتروني حقيقي عندنا (فقط اسم
/// مستخدم)، نبني بريدًا اصطناعيًا ثابتًا من اسم المستخدم — هذا بريد
/// شكلي فقط لإرضاء تنسيق Firebase Auth، ما يُرسل له أي شيء فعليًا ولا
/// يُستخدم لاستعادة كلمة المرور.
class FirebaseAuthBridgeService {
  FirebaseAuthBridgeService._();
  static final FirebaseAuthBridgeService instance = FirebaseAuthBridgeService._();

  static const _emailDomain = 'kady-app.local';

  String syntheticEmail(String username) =>
      '${username.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_.]'), '_')}@$_emailDomain';

  /// ينشئ حساب Firebase Auth مرتبط بمستخدم محلي جديد (مدير أو مندوب)،
  /// بدون ما يقطع جلسة الشخص المسجّل دخوله حاليًا على هذا الجهاز (مثلاً
  /// المدير وهو يضيف مندوب) — نستخدم تطبيق Firebase ثانوي مؤقت خصيصًا
  /// لعملية الإنشاء، ثم نتخلّص منه فورًا.
  ///
  /// يرجع uid الحساب الجديد، أو null إذا Firebase غير مفعّل أو فشلت
  /// العملية (بدون نت مثلاً) — الحساب المحلي يبقى شغّال بكل الأحوال.
  Future<String?> createLinkedAuthAccount({
    required String username,
    required String rawPassword,
    required String role,
  }) async {
    if (Firebase.apps.isEmpty) return null;
    final tempName = 'cady_temp_${DateTime.now().microsecondsSinceEpoch}';
    FirebaseApp? tempApp;
    try {
      tempApp = await Firebase.initializeApp(
        name: tempName,
        options: Firebase.app().options,
      );
      final tempAuth = FirebaseAuth.instanceFor(app: tempApp);
      final cred = await tempAuth.createUserWithEmailAndPassword(
        email: syntheticEmail(username),
        password: rawPassword,
      );
      final uid = cred.user?.uid;
      if (uid != null) {
        // مستند دور المستخدم — تعتمد عليه Firestore rules للتحقق من
        // الصلاحيات (مدير يشوف الكل / مندوب يشوف بياناته فقط)
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'username': username.trim(),
          'role': role,
        });
      }
      await tempAuth.signOut();
      return uid;
    } catch (e) {
      debugPrint('createLinkedAuthAccount failed (الحساب المحلي سليم رغم ذلك): $e');
      return null;
    } finally {
      if (tempApp != null) {
        try {
          await tempApp.delete();
        } catch (_) {}
      }
    }
  }

  /// يُستدعى بعد نجاح تسجيل الدخول المحلي — يفتح جلسة Firebase Auth
  /// الحقيقية (على التطبيق الرئيسي هذي المرة) عشان عمليات المزامنة
  /// السحابية اللاحقة تُنسب لهذا المستخدم. فشلها لا يوقف الدخول المحلي
  /// أبدًا (يُستدعى دون انتظار من account_service.dart).
  Future<void> signInLinkedAccount({
    required String username,
    required String rawPassword,
  }) async {
    if (Firebase.apps.isEmpty) return;
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: syntheticEmail(username),
        password: rawPassword,
      );
    } catch (e) {
      debugPrint('signInLinkedAccount failed (سيعمل التطبيق محليًا فقط): $e');
    }
  }
}
