import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/trading_provider.dart';
import '../../watchlist/providers/watchlist_provider.dart';

class TradingPanelScreen extends StatelessWidget {
  const TradingPanelScreen({Key? key}) : super(key: key);

  void _showConfirmOrderDialog(BuildContext context, TradingProvider provider) {
    final sideStr = provider.isBuy ? 'COMPRA' : 'VENTA';
    final actionColor = provider.isBuy ? AppColors.bull : AppColors.bear;
    final typeStr = provider.isLimit ? 'LÍMITE' : 'MERCADO';
    final priceStr = provider.isLimit ? '\$${provider.priceController.text}' : 'Al mejor precio de mercado';
    final sizeStr = '${provider.amountController.text} ${provider.baseAsset}';
    final totalStr = '\$${provider.totalController.text} ${provider.quoteAsset}';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Row(
          children: [
            Icon(provider.isBuy ? Icons.shopping_cart : Icons.sell, color: actionColor, size: 22),
            const SizedBox(width: 8),
            Text('Confirmar $sideStr ($typeStr)', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Par: ${provider.currentSymbol} (${provider.currentExchange})', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            _buildDialogRow('Precio:', priceStr),
            _buildDialogRow('Cantidad:', sizeStr),
            _buildDialogRow('Total Estimado:', totalStr),
            const Divider(color: AppColors.border, height: 20),
            const Text(
              'La orden se enviará directamente a tu cuenta del Exchange vía API.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: actionColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await provider.executeOrder();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: success ? AppColors.bull : AppColors.bear,
                    content: Text(
                      provider.statusMessage ?? (success ? 'Orden enviada con éxito' : 'Error al enviar orden'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              }
            },
            child: const Text('Confirmar y Enviar'),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tradingProvider = Provider.of<TradingProvider>(context);
    final watchlistProvider = Provider.of<WatchlistProvider>(context);

    final currentExchange = watchlistProvider.currentExchange;
    final currentSymbol = watchlistProvider.selectedSymbol;
    final currentPrice = watchlistProvider.prices[currentSymbol];

    tradingProvider.init(currentExchange, currentSymbol, currentPrice);

    final isBuy = tradingProvider.isBuy;
    final themeColor = isBuy ? AppColors.bull : AppColors.bear;

    return Container(
      color: const Color(0xFF0B0E11),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Buy / Sell Side Selector
                Container(
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => tradingProvider.setSide(true),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isBuy ? AppColors.bull : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'COMPRAR ${tradingProvider.baseAsset}',
                              style: TextStyle(
                                color: isBuy ? Colors.white : AppColors.textMuted,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => tradingProvider.setSide(false),
                          child: Container(
                            decoration: BoxDecoration(
                              color: !isBuy ? AppColors.bear : Colors.transparent,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              'VENDER ${tradingProvider.baseAsset}',
                              style: TextStyle(
                                color: !isBuy ? Colors.white : AppColors.textMuted,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 2. Order Type & Balance Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Limit / Market Segmented
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text('Límite', style: TextStyle(fontSize: 11)),
                          selected: tradingProvider.isLimit,
                          selectedColor: AppColors.primary.withValues(alpha: 0.2),
                          onSelected: (_) => tradingProvider.setOrderType(true),
                          labelStyle: TextStyle(color: tradingProvider.isLimit ? AppColors.primary : AppColors.textMuted),
                        ),
                        const SizedBox(width: 6),
                        ChoiceChip(
                          label: const Text('Mercado', style: TextStyle(fontSize: 11)),
                          selected: !tradingProvider.isLimit,
                          selectedColor: AppColors.primary.withValues(alpha: 0.2),
                          onSelected: (_) => tradingProvider.setOrderType(false),
                          labelStyle: TextStyle(color: !tradingProvider.isLimit ? AppColors.primary : AppColors.textMuted),
                        ),
                      ],
                    ),

                    // Available Balance
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Disponible:', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                        Text(
                          isBuy
                              ? '\$${tradingProvider.availableUSDT.toStringAsFixed(2)} USDT'
                              : '${tradingProvider.availableCrypto.toStringAsFixed(4)} ${tradingProvider.baseAsset}',
                          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 3. Price Input (only if Limit)
                if (tradingProvider.isLimit) ...[
                  _buildInputField(
                    controller: tradingProvider.priceController,
                    label: 'Precio de la Orden',
                    suffix: tradingProvider.quoteAsset,
                    onChanged: tradingProvider.onPriceChanged,
                  ),
                  const SizedBox(height: 12),
                ],

                // 4. Amount Input
                _buildInputField(
                  controller: tradingProvider.amountController,
                  label: 'Cantidad',
                  suffix: tradingProvider.baseAsset,
                  onChanged: tradingProvider.onAmountChanged,
                ),
                const SizedBox(height: 12),

                // 5. Total USDT Input
                _buildInputField(
                  controller: tradingProvider.totalController,
                  label: 'Total Estimado',
                  suffix: tradingProvider.quoteAsset,
                  onChanged: tradingProvider.onTotalChanged,
                ),
                const SizedBox(height: 14),

                // 6. Quick Percentage & $400 Buttons Row
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (isBuy) ...[
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            minimumSize: const Size(60, 32),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onPressed: () => tradingProvider.setStandardBlockAmount(400.0),
                          child: const Text('💎 \$400 USDT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(width: 8),
                      ],
                      _buildPctButton('25%', () => tradingProvider.setPercentage(0.25)),
                      const SizedBox(width: 6),
                      _buildPctButton('50%', () => tradingProvider.setPercentage(0.50)),
                      const SizedBox(width: 6),
                      _buildPctButton('75%', () => tradingProvider.setPercentage(0.75)),
                      const SizedBox(width: 6),
                      _buildPctButton('100%', () => tradingProvider.setPercentage(1.0)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 7. Submit Action Button
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 2,
                    ),
                    onPressed: tradingProvider.isSubmitting ? null : () => _showConfirmOrderDialog(context, tradingProvider),
                    child: tradingProvider.isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Text(
                            '${isBuy ? 'COMPRAR' : 'VENDER'} ${tradingProvider.baseAsset}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                  ),
                ),
                const SizedBox(height: 24),

                // 8. Open Active Orders Section
                _buildOpenOrdersSection(context, tradingProvider),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String suffix,
    required void Function(String) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          suffixText: suffix,
          suffixStyle: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 12),
          border: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildPctButton(String label, VoidCallback onTap) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        minimumSize: const Size(44, 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }

  Widget _buildOpenOrdersSection(BuildContext context, TradingProvider provider) {
    final orders = provider.openOrders;
    final timeFormat = DateFormat('dd/MM HH:mm');

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.list_alt, color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Órdenes Abiertas en ${provider.currentExchange} (${orders.length})',
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 16, color: AppColors.textSecondary),
                tooltip: 'Recargar Órdenes Abiertas',
                onPressed: () => provider.loadOpenOrders(),
              ),
            ],
          ),
          const Divider(color: AppColors.border, height: 16),
          if (provider.isLoadingOrders && orders.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator(color: AppColors.primary)))
          else if (orders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text('No tienes órdenes límite pendientes.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: orders.length,
              separatorBuilder: (_, __) => const Divider(color: AppColors.border, height: 12),
              itemBuilder: (context, index) {
                final order = orders[index];
                final isBuy = order.side == 'buy';
                final color = isBuy ? AppColors.bull : AppColors.bear;

                return Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: color.withValues(alpha: 0.5)),
                      ),
                      child: Text(
                        isBuy ? 'COMPRA' : 'VENTA',
                        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 9),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${order.symbol} @ \$${order.price.toStringAsFixed(order.price < 1.0 ? 4 : 2)}',
                            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          Text(
                            'Cant: ${order.size.toStringAsFixed(4)} · ${timeFormat.format(order.createdAt)}',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.bear, size: 18),
                      tooltip: 'Cancelar Orden',
                      onPressed: () async {
                        final ok = await provider.cancelOrder(order.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: ok ? AppColors.bull : AppColors.bear,
                              content: Text(ok ? 'Orden cancelada con éxito' : 'Error al cancelar orden'),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
