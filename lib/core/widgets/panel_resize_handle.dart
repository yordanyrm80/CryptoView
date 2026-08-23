import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PanelResizeHandle extends StatefulWidget {
  final ValueChanged<double> onDeltaDrag;
  final VoidCallback? onDoubleTap;
  final String tooltip;

  const PanelResizeHandle({
    Key? key,
    required this.onDeltaDrag,
    this.onDoubleTap,
    this.tooltip = 'Arrastra para redimensionar el panel (Doble clic para colapsar/restaurar)',
  }) : super(key: key);

  @override
  _PanelResizeHandleState createState() => _PanelResizeHandleState();
}

class _PanelResizeHandleState extends State<PanelResizeHandle> {
  bool _isHovered = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final bool active = _isHovered || _isDragging;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: widget.onDoubleTap,
          onHorizontalDragStart: (_) => setState(() => _isDragging = true),
          onHorizontalDragUpdate: (details) => widget.onDeltaDrag(details.delta.dx),
          onHorizontalDragEnd: (_) => setState(() => _isDragging = false),
          onHorizontalDragCancel: () => setState(() => _isDragging = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 8,
            color: active ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: active ? 3 : 1,
                decoration: BoxDecoration(
                  color: active ? AppColors.primary : AppColors.border,
                  borderRadius: BorderRadius.circular(1.5),
                  boxShadow: [
                    if (active)
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.5),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
