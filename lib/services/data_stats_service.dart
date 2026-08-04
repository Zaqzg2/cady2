import 'dart:io';
import 'package:path_provider/path_provider.dart';

import 'db_service.dart';

class DataStats {
  final int customers;
  final int products;
  final int invoices;
  final int receipts;
  final int totalBytes;

  const DataStats({
    required this.customers,
    required this.products,
    required this.invoices,
    required this.receipts,
    required this.totalBytes,
  });

  String get formattedSize {
    if (totalBytes < 1024) return '$totalBytes بايت';
    final kb = totalBytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} كيلوبايت';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} ميجابايت';
  }
}

class DataStatsService {
  static Future<DataStats> collect() async {
    final customers = await DbService.instance.getCustomers();
    final products = await DbService.instance.getProducts();
    final invoices = await DbService.instance.getInvoices();
    final receipts = await DbService.instance.getReceipts();

    int totalBytes = 0;
    try {
      final dir = await getApplicationDocumentsDirectory();
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            try {
              totalBytes += await entity.length();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    return DataStats(
      customers: customers.length,
      products: products.length,
      invoices: invoices.length,
      receipts: receipts.length,
      totalBytes: totalBytes,
    );
  }
}
