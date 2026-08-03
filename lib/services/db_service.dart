import 'dart:convert';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/customer.dart';
import '../models/product.dart';
import '../models/invoice.dart';
import '../models/receipt.dart';
import '../models/customer_note.dart';

/// طبقة الوصول لقاعدة بيانات SQLite المحلية (كل شيء يُخزَّن على الجهاز)
class DbService {
  DbService._();
  static final DbService instance = DbService._();
  Database? _db;

  Future<Database> get db async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'cady_sales.db');
    final database = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE customers (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            phone TEXT,
            address TEXT,
            openingBalance REAL DEFAULT 0,
            isPinned INTEGER DEFAULT 0,
            isStopped INTEGER DEFAULT 0,
            creditLimit REAL DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE products (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            price REAL NOT NULL,
            unit TEXT,
            imagePath TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE invoices (
            id TEXT PRIMARY KEY,
            docNumber TEXT,
            date TEXT,
            data TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE receipts (
            id TEXT PRIMARY KEY,
            docNumber TEXT,
            date TEXT,
            data TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE customer_notes (
            id TEXT PRIMARY KEY,
            customerId TEXT,
            date TEXT,
            text TEXT
          )
        ''');
      },
      // onUpgrade يُترك فارغًا عمدًا: الاعتماد فقط على رقم إصدار قاعدة
      // البيانات لتحديد الأعمدة الناقصة قد يفشل لو تعطّلت ترقية سابقة في
      // منتصف الطريق (مثلاً: تمت إضافة عمود واحد ثم انهار التطبيق قبل
      // إكمال البقية، بينما رقم الإصدار سُجِّل كأن الترقية اكتملت).
      // بدلها نستخدم _ensureSchema أدناه الذي يتحقق من وجود كل عمود/جدول
      // فعليًا قبل إضافته — آمن ويعمل بشكل صحيح حتى لو استُدعي أكثر من مرة.
      onUpgrade: (db, oldVersion, newVersion) async {},
    );
    await _ensureSchema(database);
    return database;
  }

  /// يتحقق من وجود كل عمود/جدول جديد فعليًا (عبر PRAGMA table_info) ويضيفه
  /// فقط إن كان ناقصًا، بدل الاعتماد على onUpgrade وحده. هذا يمنع أي تعطّل
  /// بسبب "duplicate column" لو كانت قاعدة البيانات بحالة غير مكتملة من
  /// محاولة ترقية سابقة، ويجعل فتح التطبيق يُصلح نفسه تلقائيًا في كل مرة.
  Future<void> _ensureSchema(Database db) async {
    await _ensureColumn(db, 'customers', 'isPinned', 'INTEGER DEFAULT 0');
    await _ensureColumn(db, 'customers', 'isStopped', 'INTEGER DEFAULT 0');
    await _ensureColumn(db, 'customers', 'creditLimit', 'REAL DEFAULT 0');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customer_notes (
        id TEXT PRIMARY KEY,
        customerId TEXT,
        date TEXT,
        text TEXT
      )
    ''');
  }

  Future<void> _ensureColumn(Database db, String table, String column, String ddl) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $ddl');
    }
  }

  // ---------------- العملاء ----------------
  Future<void> upsertCustomer(Customer c) async {
    final d = await db;
    await d.insert('customers', c.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteCustomer(String id) async {
    final d = await db;
    await d.delete('customers', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Customer>> getCustomers() async {
    final d = await db;
    final rows = await d.query('customers');
    final list = <Customer>[];
    for (final r in rows) {
      try {
        list.add(Customer.fromMap(r));
      } catch (e) {
        // نتجاهل صفًا تالفًا واحدًا بدل ما نُسقط قائمة العملاء بالكامل —
        // لو صف واحد فيه بيانات غير متوقعة (مثلاً NULL بمكان غير متوقع)
        // فالسلوك القديم كان يرمي استثناء عند .map().toList() فيختفي كل
        // العملاء دفعة واحدة بسبب صف واحد فقط.
        // ignore: avoid_print
        print('DbService.getCustomers: تجاهل صف عميل تالف: $e  |  row=$r');
      }
    }
    // الترتيب في Dart بدل SQL (COLLATE) لتفادي أي اختلاف سلوك بين أجهزة
    list.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  // ---------------- المنتجات ----------------
  Future<void> upsertProduct(Product p) async {
    final d = await db;
    await d.insert('products', p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteProduct(String id) async {
    final d = await db;
    await d.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Product>> getProducts() async {
    final d = await db;
    final rows = await d.query('products', orderBy: 'name COLLATE NOCASE');
    return rows.map((r) => Product.fromMap(r)).toList();
  }

  // ---------------- الفواتير ----------------
  Future<void> upsertInvoice(Invoice inv) async {
    final d = await db;
    await d.insert(
      'invoices',
      {
        'id': inv.id,
        'docNumber': inv.docNumber,
        'date': inv.date.toIso8601String(),
        'data': jsonEncode(inv.toMap()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteInvoice(String id) async {
    final d = await db;
    await d.delete('invoices', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Invoice>> getInvoices({String? customerId}) async {
    final d = await db;
    final rows = await d.query('invoices', orderBy: 'date DESC');
    final list = rows
        .map((r) => Invoice.fromMap(jsonDecode(r['data'] as String)))
        .toList();
    if (customerId != null) {
      return list.where((i) => i.customerId == customerId).toList();
    }
    return list;
  }

  Future<Invoice?> getInvoiceById(String id) async {
    final d = await db;
    final rows = await d.query('invoices', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Invoice.fromMap(jsonDecode(rows.first['data'] as String));
  }

  // ---------------- السندات ----------------
  Future<void> upsertReceipt(Receipt r) async {
    final d = await db;
    await d.insert(
      'receipts',
      {
        'id': r.id,
        'docNumber': r.docNumber,
        'date': r.date.toIso8601String(),
        'data': jsonEncode(r.toMap()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteReceipt(String id) async {
    final d = await db;
    await d.delete('receipts', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Receipt>> getReceipts({String? customerId}) async {
    final d = await db;
    final rows = await d.query('receipts', orderBy: 'date DESC');
    final list =
        rows.map((r) => Receipt.fromMap(jsonDecode(r['data'] as String))).toList();
    if (customerId != null) {
      return list.where((r) => r.customerId == customerId).toList();
    }
    return list;
  }

  Future<Receipt?> getReceiptById(String id) async {
    final d = await db;
    final rows = await d.query('receipts', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Receipt.fromMap(jsonDecode(rows.first['data'] as String));
  }

  // ---------------- ملاحظات العميل ----------------
  Future<void> insertNote(CustomerNote n) async {
    final d = await db;
    await d.insert('customer_notes', n.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteNote(String id) async {
    final d = await db;
    await d.delete('customer_notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<CustomerNote>> getNotes(String customerId) async {
    final d = await db;
    final rows = await d.query('customer_notes',
        where: 'customerId = ?', whereArgs: [customerId], orderBy: 'date DESC');
    return rows.map((r) => CustomerNote.fromMap(r)).toList();
  }

  // ---------------- حساب رصيد العميل ----------------
  Future<double> getCustomerBalance(String customerId, double openingBalance) async {
    final invoices = await getInvoices(customerId: customerId);
    final receipts = await getReceipts(customerId: customerId);
    double balance = openingBalance;
    for (final inv in invoices) {
      balance += inv.effect;
    }
    for (final r in receipts) {
      balance -= r.amount;
    }
    return balance;
  }
}
