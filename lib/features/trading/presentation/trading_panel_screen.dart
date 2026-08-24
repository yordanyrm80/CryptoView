import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/trading_provider.dart';
import '../../watchlist/providers/watchlist_provider.dart';

class TradingPanelScreen extends StatefulWidget {
  const TradingPanelScreen({super.key});

  @override
  State<TradingPanelScreen> createState() => _TradingPanelScreenState();
}

class _TradingPanelScreenState extends State<TradingPanelScreen> with AutomaticKeepAliveClientMixin {
  String? _lastExchange;
  String? _lastSymbol;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final watchlistProvider = Provider.of<WatchlistProvider>(context);
    final tradingProvider = Provider.of<TradingProvider>(context, listen: false);

    final currentExchange = watchlistProvider.currentExchange;
    final currentSymbol = watchlistProvider.selectedSymbol;
    final currentPrice = watchlistProvider.prices[currentSymbol];

    if (_lastExchange != currentExchange || _lastSymbol != currentSymbol) {
      _lastExchange = currentExchange;
      _lastSymbol = currentSymbol;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          tradingProvider.init(currentExchange, currentSymbol, currentPrice);
        }
      });
    }
  }

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
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: actionColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(provider.isBuy ? Icons.shopping_cart : Icons.sell, color: actionColor, size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              'Confirmar $sideStr ($typeStr)',
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Par: ${provider.currentSymbol}', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(provider.currentExchange, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildDialogRow('Precio:', priceStr),
            _buildDialogRow('Cantidad:', sizeStr),
            _buildDialogRow('Total Estimado:', totalStr),
            const Divider(color: AppColors.border, height: 20),
            Row(
              children: const [
                Icon(Icons.info_outline, color: AppColors.textMuted, size: 14),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'La orden se enviará directamente a tu cuenta del Exchange vía API.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                ),
              ],
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
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
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
            child: const Text('Confirmar y Enviar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
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
    super.build(context);
    final tradingProvider = Provider.of<TradingProvider>(context);
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
                // 1. Sleek Buy / Sell Modern Segmented Switch
                Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      // BUY TAB
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(11),
                            onTap: () => tradingProvider.setSide(true),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              decoration: BoxDecoration(
                                color: isBuy ? AppColors.bull : Colors.transparent,
                                borderRadius: BorderRadius.circular(11),
                                boxShadow: isBuy
                                    ? [
                                        BoxShadow(
                                          color: AppColors.bull.withValues(alpha: 0.35),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        )
                                      ]
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.arrow_upward_rounded, size: 16, color: isBuy ? Colors.white : AppColors.textMuted),
                                  const SizedBox(width: 6),
                                  Text(
                                    'COMPRAR ${tradingProvider.baseAsset}',
                                    style: TextStyle(
                                      color: isBuy ? Colors.white : AppColors.textMuted,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // SELL TAB
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(11),
                            onTap: () => tradingProvider.setSide(false),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              decoration: BoxDecoration(
                                color: !isBuy ? AppColors.bear : Colors.transparent,
                                borderRadius: BorderRadius.circular(11),
                                boxShadow: !isBuy
                                    ? [
                                        BoxShadow(
                                          color: AppColors.bear.withValues(alpha: 0.35),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        )
                                      ]
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.arrow_downward_rounded, size: 16, color: !isBuy ? Colors.white : AppColors.textMuted),
                                  const SizedBox(width: 6),
                                  Text(
                                    'VENDER ${tradingProvider.baseAsset}',
                                    style: TextStyle(
                                      color: !isBuy ? Colors.white : AppColors.textMuted,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 2. Order Type & Balance Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Limit / Market Segmented Pills
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          _buildTypePill(
                            label: 'Límite',
                            isSelected: tradingProvider.isLimit,
                            onTap: () => tradingProvider.setOrderType(true),
                          ),
                          _buildTypePill(
                            label: 'Mercado',
                            isSelected: !tradingProvider.isLimit,
                            onTap: () => tradingProvider.setOrderType(false),
                          ),
                        ],
                      ),
                    ),

                    // Available Balance with Quick Max
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('Disponible', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                              Text(
                                isBuy
                                    ? '\$${tradingProvider.availableUSDT.toStringAsFixed(2)} USDT'
                                    : '${tradingProvider.availableCrypto.toStringAsFixed(4)} ${tradingProvider.baseAsset}',
                                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            borderRadius: BorderRadius.circular(4),
                            onTap: () => tradingProvider.setPercentage(1.0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('MAX', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 9)),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                            icon: tradingProvider.isLoadingBalances
                                ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.primary))
                                : const Icon(Icons.refresh, size: 14, color: AppColors.textMuted),
                            tooltip: 'Recargar Saldo',
                            onPressed: () => tradingProvider.loadBalances(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 3. Price Input (only if Limit, otherwise Market indicator)
                if (tradingProvider.isLimit) ...[
                  _buildInputField(
                    controller: tradingProvider.priceController,
                    label: 'Precio de la Orden',
                    suffix: tradingProvider.quoteAsset,
                    icon: Icons.attach_money,
                    onChanged: tradingProvider.onPriceChanged,
                  ),
                  const SizedBox(height: 12),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.bolt, color: AppColors.secondary, size: 18),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '⚡ Orden de Mercado: Se ejecutará al mejor precio disponible inmediatamente.',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // 4. Amount Input
                _buildInputField(
                  controller: tradingProvider.amountController,
                  label: 'Cantidad',
                  suffix: tradingProvider.baseAsset,
                  icon: Icons.token,
                  onChanged: tradingProvider.onAmountChanged,
                ),
                const SizedBox(height: 12),

                // 5. Total USDT Input
                _buildInputField(
                  controller: tradingProvider.totalController,
                  label: 'Total Estimado',
                  suffix: tradingProvider.quoteAsset,
                  icon: Icons.calculate_outlined,
                  onChanged: tradingProvider.onTotalChanged,
                ),
                const SizedBox(height: 14),

                // 6. Quick Percentage & Preset Blocks Row
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (isBuy) ...[
                        _buildPresetBlockButton('💎 \$100', () => tradingProvider.setStandardBlockAmount(100.0)),
                        const SizedBox(width: 6),
                        _buildPresetBlockButton('💎 \$400', () => tradingProvider.setStandardBlockAmount(400.0)),
                        const SizedBox(width: 6),
                        _buildPresetBlockButton('💎 \$1000', () => tradingProvider.setStandardBlockAmount(1000.0)),
                        const SizedBox(width: 8),
                      ],
                      _buildPctChip('25%', () => tradingProvider.setPercentage(0.25)),
                      const SizedBox(width: 6),
                      _buildPctChip('50%', () => tradingProvider.setPercentage(0.50)),
                      const SizedBox(width: 6),
                      _buildPctChip('75%', () => tradingProvider.setPercentage(0.75)),
                      const SizedBox(width: 6),
                      _buildPctChip('100%', () => tradingProvider.setPercentage(1.0)),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 7. Submit Action Button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeColor,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shadowColor: themeColor.withValues(alpha: 0.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: tradingProvider.isSubmitting ? null : () => _showConfirmOrderDialog(context, tradingProvider),
                    child: tradingProvider.isSubmitting
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(isBuy ? Icons.shopping_cart_checkout : Icons.sell, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                '${isBuy ? 'COMPRAR' : 'VENDER'} ${tradingProvider.baseAsset}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5),
                              ),
                            ],
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

  Widget _buildTypePill({required String label, required bool isSelected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.primary : AppColors.textMuted,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String suffix,
    required IconData icon,
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
          prefixIcon: Icon(icon, color: AppColors.textMuted, size: 16),
          prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          suffixText: suffix,
          suffixStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }

  Widget _buildPctChip(String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _buildPresetBlockButton(String label, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.6)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.bold)),
      ),
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
                    'Órdenes Abiertas en ${provider.currentExchange}',
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${orders.length}', style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold)),
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
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inbox_outlined, color: AppColors.textMuted, size: 28),
                    SizedBox(height: 6),
                    Text('No tienes órdenes límite pendientes.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  ],
                ),
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

                return Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
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
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${order.symbol} @ \$${order.price.toStringAsFixed(order.price < 1.0 ? 4 : 2)}',
                              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            const SizedBox(height: 2),
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
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
