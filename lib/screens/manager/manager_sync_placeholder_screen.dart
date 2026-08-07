import 'package:flutter/material.dart';

/// عناصر الاستيراد/التصدير/سجل المزامنة — ستُفعَّل في المرحلة القادمة
/// (طبقة بيانات المزامنة: Pending/Synced لكل سجل + Sync Queue)
class ManagerSyncPlaceholderScreen extends StatelessWidget {
  const ManagerSyncPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('المزامنة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _ComingSoonCard(
            icon: Icons.file_download_outlined,
            title: 'استيراد ملف مندوب',
            subtitle: 'استيراد عمليات المندوبين مع معاينة قبل الاعتماد',
          ),
          SizedBox(height: 12),
          _ComingSoonCard(
            icon: Icons.file_upload_outlined,
            title: 'إنشاء تحديث',
            subtitle: 'تصدير المنتجات/الأسعار/العملاء لمندوب أو للجميع',
          ),
          SizedBox(height: 12),
          _ComingSoonCard(
            icon: Icons.history_outlined,
            title: 'سجل المزامنة',
            subtitle: 'كل عمليات الاستيراد السابقة مع إمكانية إعادة الاستيراد',
          ),
        ],
      ),
    );
  }
}

class _ComingSoonCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _ComingSoonCard(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Colors.grey.shade400),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Chip(
          label: const Text('قريبًا', style: TextStyle(fontSize: 11)),
          backgroundColor: Colors.grey.shade200,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}
