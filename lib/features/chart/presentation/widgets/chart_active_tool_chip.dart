import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class ChartActiveToolChip extends StatelessWidget {
  final String activeTool;
  final bool hasRulerStart;
  final double? rulerPercent;

  const ChartActiveToolChip({
    Key? key,
    required this.activeTool,
    required this.hasRulerStart,
    this.rulerPercent,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (activeTool == 'none') return const SizedBox.shrink();

    final bool isRulerComplete = activeTool == 'ruler' && rulerPercent != null;
    final Color chipColor = isRulerComplete
        ? (rulerPercent! >= 0 ? AppColors.bull : AppColors.bear)
        : AppColors.primary.withValues(alpha: 0.9);
    final Color contentColor = isRulerComplete ? Colors.white : AppColors.background;

    String chipText;
    if (activeTool == 'horizontal_line') {
      chipText = 'DIBUJO: LÍNEA HORIZONTAL';
    } else if (activeTool == 'place_order') {
      chipText = 'ORDEN: TOCA UN PRECIO EN EL GRÁFICO';
    } else if (isRulerComplete) {
      final String sign = rulerPercent! >= 0 ? '+' : '';
      chipText = 'REGLA: $sign${rulerPercent!.toStringAsFixed(2)}% (Toca para nueva medida)';
    } else if (hasRulerStart) {
      chipText = 'REGLA: MARCA FIN';
    } else {
      chipText = 'REGLA: MARCA INICIO';
    }

    return Positioned(
      top: 10,
      left: 10,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: chipColor,
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              activeTool == 'horizontal_line'
                  ? Icons.border_horizontal
                  : activeTool == 'place_order'
                      ? Icons.add_shopping_cart
                      : Icons.square_foot,
              color: contentColor,
              size: 14,
            ),
            const SizedBox(width: 6),
            Text(
              chipText,
              style: TextStyle(
                color: contentColor,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
