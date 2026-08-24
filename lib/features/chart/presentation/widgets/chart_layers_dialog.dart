import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../settings/providers/settings_provider.dart';

class ChartLayersDialog extends StatelessWidget {
  final SettingsProvider settingsProvider;

  const ChartLayersDialog({
    Key? key,
    required this.settingsProvider,
  }) : super(key: key);

  Widget _buildCategoryCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required Color color,
    required bool lineVisible,
    required ValueChanged<bool> onLineToggle,
    required bool labelVisible,
    required ValueChanged<bool> onLabelToggle,
    required String labelText,
    String? subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: lineVisible ? color.withValues(alpha: 0.35) : AppColors.border,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main Line Switch Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: lineVisible ? 0.15 : 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: lineVisible ? color : AppColors.textMuted, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: lineVisible ? AppColors.textPrimary : AppColors.textMuted,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                      ],
                    ],
                  ),
                ],
              ),
              Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: lineVisible,
                  activeColor: color,
                  onChanged: onLineToggle,
                ),
              ),
            ],
          ),

          // Sub-row: Text Label Switch
          if (lineVisible) ...[
            const Divider(color: AppColors.border, height: 14),
            Padding(
              padding: const EdgeInsets.only(left: 36, right: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.label_outline, size: 13, color: labelVisible ? AppColors.textSecondary : AppColors.textMuted),
                      const SizedBox(width: 6),
                      Text(
                        labelText,
                        style: TextStyle(
                          color: labelVisible ? AppColors.textSecondary : AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: labelVisible ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  Transform.scale(
                    scale: 0.75,
                    child: Switch(
                      value: labelVisible,
                      activeColor: AppColors.primary,
                      onChanged: onLabelToggle,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final areAllLabelsOn = settingsProvider.areAllLabelsVisible;
    final areAllLinesOn = settingsProvider.areAllLinesVisible;

    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      titlePadding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      contentPadding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Row(
            children: [
              Icon(Icons.layers_outlined, color: AppColors.primary, size: 22),
              SizedBox(width: 8),
              Text(
                'Capas y Visibilidad',
                style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.textMuted, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Master Action Buttons Bar
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Master Labels Toggle
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: areAllLabelsOn ? AppColors.primary : AppColors.textMuted,
                        side: BorderSide(color: areAllLabelsOn ? AppColors.primary : AppColors.border),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => settingsProvider.toggleAllLabels(!areAllLabelsOn),
                      icon: Icon(areAllLabelsOn ? Icons.label : Icons.label_off_outlined, size: 14),
                      label: Text(
                        areAllLabelsOn ? 'Ocultar Etiquetas' : 'Mostrar Etiquetas',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),

                    // Master Lines Toggle
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: areAllLinesOn ? AppColors.primary : AppColors.textMuted,
                        side: BorderSide(color: areAllLinesOn ? AppColors.primary : AppColors.border),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => settingsProvider.toggleAllLines(!areAllLinesOn),
                      icon: Icon(areAllLinesOn ? Icons.visibility : Icons.visibility_off, size: 14),
                      label: Text(
                        areAllLinesOn ? 'Ocultar Líneas' : 'Mostrar Líneas',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

              // 1. Mis Compras Abiertas
              _buildCategoryCard(
                context: context,
                icon: Icons.shopping_bag_outlined,
                title: 'Compras Abiertas (Diario)',
                subtitle: 'Líneas verdes con precios de compra registrados',
                color: settingsProvider.buyLineColor,
                lineVisible: settingsProvider.showBuyLines,
                onLineToggle: (val) => settingsProvider.setShowBuyLines(val),
                labelVisible: settingsProvider.showBuyLabels,
                onLabelToggle: (val) => settingsProvider.setShowBuyLabels(val),
                labelText: 'Mostrar texto (Precio, Tokens y % PnL)',
              ),

              // 2. Mis Ventas Abiertas
              _buildCategoryCard(
                context: context,
                icon: Icons.sell_outlined,
                title: 'Ventas Abiertas (Diario)',
                subtitle: 'Líneas rojas de órdenes de venta registradas',
                color: settingsProvider.sellLineColor,
                lineVisible: settingsProvider.showSellLines,
                onLineToggle: (val) => settingsProvider.setShowSellLines(val),
                labelVisible: settingsProvider.showSellLabels,
                onLabelToggle: (val) => settingsProvider.setShowSellLabels(val),
                labelText: 'Mostrar texto (Precio y Tokens de venta)',
              ),

              // 3. Órdenes Límite del Exchange
              _buildCategoryCard(
                context: context,
                icon: Icons.pending_actions,
                title: 'Órdenes Límite en Exchange',
                subtitle: 'Órdenes vivas esperando ejecución en KuCoin / Binance',
                color: Colors.amber,
                lineVisible: settingsProvider.showOpenOrders,
                onLineToggle: (val) => settingsProvider.setShowOpenOrders(val),
                labelVisible: settingsProvider.showOpenOrderLabels,
                onLabelToggle: (val) => settingsProvider.setShowOpenOrderLabels(val),
                labelText: 'Mostrar texto (Tipo, Precio y Tamaño de orden)',
              ),

              // 4. Soportes y Resistencias
              _buildCategoryCard(
                context: context,
                icon: Icons.edit_road,
                title: 'Soportes y Resistencias (Dibujos)',
                subtitle: 'Líneas y niveles clave dibujados manualmente',
                color: AppColors.primary,
                lineVisible: settingsProvider.showDrawings,
                onLineToggle: (val) => settingsProvider.setShowDrawings(val),
                labelVisible: settingsProvider.showDrawingLabels,
                onLabelToggle: (val) => settingsProvider.setShowDrawingLabels(val),
                labelText: 'Mostrar texto (Nombre de línea y Precio)',
              ),

              // 5. Precio de Mercado Actual
              _buildCategoryCard(
                context: context,
                icon: Icons.show_chart,
                title: 'Precio de Mercado en Vivo',
                subtitle: 'Línea de cotización en tiempo real',
                color: settingsProvider.currentPriceColor,
                lineVisible: settingsProvider.showCurrentPriceLine,
                onLineToggle: (val) => settingsProvider.setShowCurrentPriceLine(val),
                labelVisible: settingsProvider.showCurrentPriceLabel,
                onLabelToggle: (val) => settingsProvider.setShowCurrentPriceLabel(val),
                labelText: 'Mostrar etiqueta con precio en vivo',
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
