import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../settings/providers/settings_provider.dart';

class ChartLayerFilterBar extends StatelessWidget {
  final SettingsProvider settingsProvider;

  const ChartLayerFilterBar({
    Key? key,
    required this.settingsProvider,
  }) : super(key: key);

  Widget _layerChip({
    required BuildContext context,
    required String label,
    required bool isVisible,
    required Color activeColor,
    required IconData icon,
    required VoidCallback onToggle,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isVisible ? activeColor.withValues(alpha: 0.15) : AppColors.background.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isVisible ? activeColor.withValues(alpha: 0.7) : AppColors.border,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isVisible ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 13,
                color: isVisible ? activeColor : AppColors.textMuted,
              ),
              const SizedBox(width: 5),
              Icon(
                icon,
                size: 12,
                color: isVisible ? activeColor : AppColors.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: isVisible ? AppColors.textPrimary : AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: isVisible ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 0.8),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Icon(Icons.layers_outlined, size: 14, color: AppColors.textMuted),
            const SizedBox(width: 6),
            const Text('Capas:', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),

            // 1. Mis Líneas (Trazos Manuales)
            _layerChip(
              context: context,
              label: 'Mis Líneas',
              isVisible: settingsProvider.showDrawings,
              activeColor: AppColors.primary,
              icon: Icons.edit_road,
              onToggle: () => settingsProvider.setShowDrawings(!settingsProvider.showDrawings),
              tooltip: 'Mostrar u ocultar tus líneas y soportes manuales',
            ),
            const SizedBox(width: 6),

            // 2. Compras
            _layerChip(
              context: context,
              label: 'Compras',
              isVisible: settingsProvider.showBuyLines,
              activeColor: settingsProvider.buyLineColor,
              icon: Icons.shopping_cart_outlined,
              onToggle: () => settingsProvider.setShowBuyLines(!settingsProvider.showBuyLines),
              tooltip: 'Mostrar u ocultar líneas de órdenes de compra abiertas',
            ),
            const SizedBox(width: 6),

            // 3. Ventas
            _layerChip(
              context: context,
              label: 'Ventas',
              isVisible: settingsProvider.showSellLines,
              activeColor: settingsProvider.sellLineColor,
              icon: Icons.sell_outlined,
              onToggle: () => settingsProvider.setShowSellLines(!settingsProvider.showSellLines),
              tooltip: 'Mostrar u ocultar líneas de órdenes de venta abiertas',
            ),
            const SizedBox(width: 6),

            // 4. Precio Actual
            _layerChip(
              context: context,
              label: 'Precio Actual',
              isVisible: settingsProvider.showCurrentPriceLine,
              activeColor: settingsProvider.currentPriceColor,
              icon: Icons.show_chart,
              onToggle: () => settingsProvider.setShowCurrentPriceLine(!settingsProvider.showCurrentPriceLine),
              tooltip: 'Mostrar u ocultar la línea del precio actual de mercado en tiempo real',
            ),
          ],
        ),
      ),
    );
  }
}
