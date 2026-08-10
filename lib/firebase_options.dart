// ignore_for_file: type=lint

// ⚠️ هذا ملف مؤقت (placeholder) بقيم وهمية — التطبيق يبني ويشتغل بيه
// عادي، لكن مزامنة السحابة (CloudSyncService) راح تفشل بصمت وتتجاهل
// نفسها لأن القيم هنا مو حقيقية.
//
// لتفعيل المزامنة فعليًا: بعد إنشاء مشروعك على console.firebase.google.com
// وتفعيل Firestore، شغّل من جذر المشروع:
//
//     flutterfire configure
//
// بيسألك تختار المشروع والمنصّات (اختر Android و Web)، وبيعيد كتابة
// هذا الملف بالكامل تلقائيًا بمفاتيح مشروعك الحقيقية — ما تحتاج تعدّله
// يدويًا أبدًا.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions لم تُضبط لهذه المنصة بعد. '
          'شغّل flutterfire configure لإضافتها.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'REPLACE_ME',
    appId: 'REPLACE_ME',
    messagingSenderId: 'REPLACE_ME',
    projectId: 'REPLACE_ME',
    storageBucket: 'REPLACE_ME',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'REPLACE_ME',
    appId: 'REPLACE_ME',
    messagingSenderId: 'REPLACE_ME',
    projectId: 'REPLACE_ME',
    authDomain: 'REPLACE_ME',
    storageBucket: 'REPLACE_ME',
  );
}
