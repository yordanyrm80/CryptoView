import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/chart_provider.dart';

class ChartToolbar extends StatelessWidget {
  final ChartProvider chartProvider;
  final String currentExchange;
  final String currentSymbol;
  final VoidCallback onClearAll;

  const ChartToolbar({
    Key? key,
    required this.chartProvider,
    required this.currentExchange,
    required this.currentSymbol,
    required this.onClearAll,
  }) : super(key: key);

  Widget _toolButton({
    required BuildContext context,
    required String tool,
    required IconData icon,
    required String tooltip,
    required String snackbarMessage,
  }) {
    final bool isActive = chartProvider.activeTool == tool;
    return IconButton(
      icon: Icon(icon, size: 20),
      color: isActive ? AppColors.primary : AppColors.textSecondary,
      tooltip: tooltip,
      onPressed: () {
        chartProvider.setActiveTool(tool);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            backgroundColor: AppColors.surface,
            content: Text(
              snackbarMessage,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.border, width: 1),
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _toolButton(
            context: context,
            tool: 'none',
            icon: Icons.navigation_outlined,
            tooltip: 'Desactivar Dibujo (Navegar)',
            snackbarMessage: 'Modo Navegación Activo: Desplaza y haz zoom sobre el gráfico.',
          ),
          _toolButton(
            context: context,
            tool: 'horizontal_line',
            icon: Icons.border_horizontal,
            tooltip: 'Línea Horizontal (Soporte/Resistencia)',
            snackbarMessage: 'Línea Horizontal Activa: Toca el gráfico para colocar soporte/resistencia.',
          ),
          _toolButton(
            context: context,
            tool: 'ruler',
            icon: Icons.square_foot_outlined,
            tooltip: 'Regla de Medida (% de Ganancia)',
            snackbarMessage: 'Regla de Medida Activa: Toca el precio de inicio y luego el final para medir %.',
          ),
          _toolButton(
            context: context,
            tool: 'place_order',
            icon: Icons.add_shopping_cart,
            tooltip: 'Colocar Orden en Gráfico',
            snackbarMessage: 'Modo Orden: Toca un precio en el gráfico para preparar tu orden.',
          ),
          IconButton(
            icon: const Icon(Icons.clear, size: 18),
            color: chartProvider.rulerStartPrice != null ? AppColors.bear : AppColors.textMuted,
            tooltip: 'Limpiar Medición',
            onPressed: chartProvider.rulerStartPrice != null ? () => chartProvider.clearRuler() : null,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, size: 18),
            color: AppColors.textSecondary,
            tooltip: 'Borrar Todo',
            onPressed: onClearAll,
          ),
        ],
      ),
    );
  }
}
