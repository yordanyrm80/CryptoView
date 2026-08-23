import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/chart_provider.dart';

class ChartDrawingListPanel extends StatelessWidget {
  final ChartProvider chartProvider;
  final String currentExchange;
  final String currentSymbol;

  const ChartDrawingListPanel({
    Key? key,
    required this.chartProvider,
    required this.currentExchange,
    required this.currentSymbol,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.surface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'SOPORTES Y RESISTENCIAS DIBUJADOS',
                  style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 11),
                ),
                Text(
                  '${chartProvider.drawings.length} líneas',
                  style: const TextStyle(color: AppColors.primary, fontSize: 11),
                ),
              ],
            ),
          ),
          Expanded(
            child: chartProvider.drawings.isEmpty
                ? const Center(
                    child: Text(
                      'No hay líneas guardadas en este par.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    itemCount: chartProvider.drawings.length,
                    itemBuilder: (context, index) {
                      final drawing = chartProvider.drawings[index];
                      final int id = drawing['id'];
                      final double price = drawing['price'];
                      final String colorHex = drawing['color'];
                      final String label = drawing['label'];
                      final int colorVal = int.parse(colorHex.replaceFirst('#', '0xFF'));

                      return ListTile(
                        leading: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Color(colorVal),
                            shape: BoxShape.circle,
                          ),
                        ),
                        title: Text(
                          label,
                          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        subtitle: Text(
                          'Precio: \$${price.toStringAsFixed(2)}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.bear, size: 20),
                          onPressed: () {
                            chartProvider.deleteDrawing(id, currentExchange, currentSymbol);
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
