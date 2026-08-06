import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:signature/signature.dart';

import '../services/image_store.dart';

/// منطقة توقيع بارزة باللمس (تُستخدم لتوقيع العميل في الفاتورة، وتوقيع
/// المندوب في سند القبض). تحفظ الناتج داخل ImageStore (يعمل على الجوال
/// والويب معًا) وتُرجع مفتاحه.
class SignaturePadWidget extends StatefulWidget {
  final String label;
  final String? existingPath;
  final ValueChanged<String?> onSaved;

  const SignaturePadWidget({
    super.key,
    required this.label,
    required this.onSaved,
    this.existingPath,
  });

  @override
  State<SignaturePadWidget> createState() => _SignaturePadWidgetState();
}

class _SignaturePadWidgetState extends State<SignaturePadWidget> {
  late final SignatureController _controller;
  // إذا كان هناك توقيع محفوظ مسبقًا (تعديل فاتورة قديمة)، نعرضه كصورة
  // ثابتة بدل لوحة رسم فاضية، حتى لا يُعتبر "فاضياً" ويُمسح بالخطأ عند
  // الحفظ دون رسم توقيع جديد. المستخدم يقدر يضغط "إعادة التوقيع" إذا
  // يريد تغييره فعليًا.
  bool _showingExistingImage = false;
  bool _loadingExisting = false;
  String? _existingKey;
  Uint8List? _existingBytes;

  @override
  void initState() {
    super.initState();
    _controller = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.white,
    );
    _existingKey = widget.existingPath;
    if (_existingKey != null) {
      _showingExistingImage = true;
      _loadExisting();
    }
  }

  Future<void> _loadExisting() async {
    setState(() => _loadingExisting = true);
    final bytes = await ImageStore.instance.load(_existingKey);
    if (!mounted) return;
    setState(() {
      _existingBytes = bytes;
      _showingExistingImage = bytes != null;
      _loadingExisting = false;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_controller.isEmpty) {
      // لا نمسح توقيعًا محفوظًا مسبقًا لمجرد أن لوحة الرسم فاضية —
      // هذا يحصل فقط إذا لم يرسم المستخدم شيئًا جديدًا أصلاً.
      widget.onSaved(_existingKey);
      return;
    }
    final data = await _controller.toPngBytes();
    if (data == null) return;
    final key = await ImageStore.instance.save(data, key: _existingKey);
    _existingKey = key;
    _existingBytes = data;
    widget.onSaved(key);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(widget.label,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            TextButton.icon(
              onPressed: () {
                _controller.clear();
                setState(() => _showingExistingImage = false);
                _existingKey = null;
                _existingBytes = null;
                widget.onSaved(null);
              },
              icon: const Icon(Icons.refresh),
              label: const Text('مسح'),
            ),
          ],
        ),
        // منطقة التوقيع بارزة بإطار سميك وخلفية مميزة
        Container(
          height: 180,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.orange, width: 2.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: _loadingExisting
              ? const Center(child: CircularProgressIndicator())
              : (_showingExistingImage && _existingBytes != null)
                  ? Stack(
                      children: [
                        Positioned.fill(
                          child: Image.memory(_existingBytes!, fit: BoxFit.contain),
                        ),
                        Positioned(
                          bottom: 6,
                          left: 6,
                          child: TextButton(
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.orange.shade50,
                            ),
                            onPressed: () =>
                                setState(() => _showingExistingImage = false),
                            child: const Text('إعادة التوقيع'),
                          ),
                        ),
                      ],
                    )
                  : Signature(
                      controller: _controller,
                      backgroundColor: Colors.white,
                    ),
        ),
        const SizedBox(height: 6),
        if (!_showingExistingImage && !_loadingExisting)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _save,
              child: const Text('اعتماد التوقيع'),
            ),
          ),
      ],
    );
  }
}
