import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class ChartActiveToolChip extends StatelessWidget {
  final String activeTool;
  final bool hasRulerStart;

  const ChartActiveToolChip({
    Key? key,
    required this.activeTool,
    required this.hasRulerStart,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (activeTool == 'none') return const SizedBox.shrink();

    return Positioned(
      top: 10,
      left: 10,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.9),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 4),
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
              color: AppColors.background,
              size: 14,
            ),
            const SizedBox(width: 6),
            Text(
              activeTool == 'horizontal_line'
                  ? 'DIBUJO: LÍNEA HORIZONTAL'
                  : activeTool == 'place_order'
                      ? 'ORDEN: TOCA UN PRECIO EN EL GRÁFICO'
                      : !hasRulerStart
                          ? 'REGLA: MARCA INICIO'
                          : 'REGLA: MARCA FIN',
              style: const TextStyle(
                color: AppColors.background,
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
