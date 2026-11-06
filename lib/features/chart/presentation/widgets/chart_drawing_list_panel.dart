import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/chart_provider.dart';

class ChartDrawingListPanel extends StatelessWidget {
  final ChartProvider chartProvider;
  final String currentExchange;
  final String currentSymbol;
  final bool isExpanded;
  final VoidCallback onToggleExpand;
  final double panelHeight;
  final ValueChanged<double>? onVerticalDragUpdate;

  const ChartDrawingListPanel({
    Key? key,
    required this.chartProvider,
    required this.currentExchange,
    required this.currentSymbol,
    this.isExpanded = false,
    required this.onToggleExpand,
    this.panelHeight = 175.0,
    this.onVerticalDragUpdate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final count = chartProvider.drawings.length;

    return Container(
      color: AppColors.card,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isExpanded && onVerticalDragUpdate != null)
            MouseRegion(
              cursor: SystemMouseCursors.resizeRow,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (details) =>
                    onVerticalDragUpdate!(details.delta.dy),
                child: Container(
                  height: 5,
                  width: double.infinity,
                  color: AppColors.border,
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 2,
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          InkWell(
            onTap: onToggleExpand,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  top: BorderSide(color: AppColors.border, width: 1),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_up,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'NIVELES DE SOPORTE Y RESISTENCIA',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '$count ${count == 1 ? 'línea' : 'líneas'}',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    isExpanded ? 'Ocultar panel' : 'Mostrar panel',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            SizedBox(
              height: panelHeight,
              child: count == 0
                  ? const Center(
                      child: Text(
                        'No hay niveles técnicos trazados en este activo.',
                        style:
                            TextStyle(color: AppColors.textMuted, fontSize: 12),
                      ),
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: count,
                      itemBuilder: (context, index) {
                        final drawing = chartProvider.drawings[index];
                        final int id = drawing['id'];
                        final double price = drawing['price'];
                        final String colorHex = drawing['color'];
                        final String label = drawing['label'];
                        final int colorVal =
                            int.parse(colorHex.replaceFirst('#', '0xFF'));

                        return ListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          leading: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Color(colorVal),
                              shape: BoxShape.circle,
                            ),
                          ),
                          title: Text(
                            label,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            'Nivel: \$${price.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11.5,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: AppColors.bear, size: 18),
                            tooltip: 'Eliminar nivel',
                            onPressed: () {
                              chartProvider.deleteDrawing(
                                  id, currentExchange, currentSymbol);
                            },
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}
