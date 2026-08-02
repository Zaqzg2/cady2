import 'dart:math';
import 'package:flutter/material.dart';

class RadialMenuAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  RadialMenuAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

/// قائمة دائرية سريعة تظهر حول نقطة الضغط المطوّل مباشرة (بدل فتح شاشة
/// كاملة أو قائمة منسدلة بعيدة عن الإصبع) — أسرع وصول للإجراءات
/// الشائعة على عنصر بقائمة (مثل بطاقة عميل).
class RadialQuickMenu {
  static void show(
    BuildContext context,
    Offset center,
    List<RadialMenuAction> actions,
  ) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _RadialMenuOverlay(
        center: center,
        actions: actions,
        onDismiss: () => entry.remove(),
      ),
    );
    Overlay.of(context).insert(entry);
  }
}

class _RadialMenuOverlay extends StatefulWidget {
  final Offset center;
  final List<RadialMenuAction> actions;
  final VoidCallback onDismiss;
  const _RadialMenuOverlay({
    required this.center,
    required this.actions,
    required this.onDismiss,
  });

  @override
  State<_RadialMenuOverlay> createState() => _RadialMenuOverlayState();
}

class _RadialMenuOverlayState extends State<_RadialMenuOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _close([VoidCallback? then]) async {
    if (_closing) return;
    _closing = true;
    await _controller.reverse();
    widget.onDismiss();
    then?.call();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const radius = 82.0;
    const itemSize = 52.0;
    final n = widget.actions.length;
    // نصف دائرة تفتح للأعلى غالبًا، وللأسفل لو نقطة الضغط قريبة من أعلى
    // الشاشة حتى لا تخرج الأيقونات خارج حدود العرض.
    final openUp = widget.center.dy > size.height * 0.32;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: () => _close(),
            behavior: HitTestBehavior.opaque,
            child: FadeTransition(
              opacity: _controller,
              child: Container(color: Colors.black.withOpacity(0.38)),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _controller,
          builder: (ctx, _) {
            return Stack(
              children: List.generate(n, (i) {
                final t = n == 1 ? 0.5 : i / (n - 1);
                // زاوية موزّعة على نصف دائرة (180°) بين أقصى اليمين وأقصى اليسار
                final angle = pi - (t * pi);
                final dx = radius * _controller.value * cos(angle);
                final dyRaw = radius * _controller.value * sin(angle);
                final dy = (openUp ? -1 : 1) * dyRaw.abs();
                final action = widget.actions[i];
                return Positioned(
                  left: widget.center.dx + dx - itemSize / 2,
                  top: widget.center.dy + dy - itemSize / 2,
                  child: Opacity(
                    opacity: _controller.value.clamp(0, 1),
                    child: GestureDetector(
                      onTap: () => _close(action.onTap),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: itemSize,
                            height: itemSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: action.color,
                              boxShadow: const [
                                BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 6,
                                    offset: Offset(0, 2)),
                              ],
                            ),
                            child: Icon(action.icon, color: Colors.white, size: 24),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(action.label,
                                style: const TextStyle(color: Colors.white, fontSize: 10)),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ],
    );
  }
}
