import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/transaction_model.dart';
import '../../providers/tracker_provider.dart';
import '../../../watchlist/providers/watchlist_provider.dart';

class TransactionDetailSheet extends StatelessWidget {
  final TransactionModel tx;
  final TrackerProvider provider;

  const TransactionDetailSheet({Key? key, required this.tx, required this.provider}) : super(key: key);

  String _formatAmount(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    String s = value.toStringAsFixed(6);
    s = s.replaceAll(RegExp(r'0+$'), '');
    s = s.replaceAll(RegExp(r'\.$'), '');
    return s;
  }

  Widget _detailField({required String title, required String value, Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(color: valueColor ?? AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBuy = tx.type == 'buy';
    final totalValue = tx.price * tx.amount;
    final remaining = provider.getRemainingAmount(tx);
    final isFullyMatched = remaining == 0;
    final dateStr = '${tx.date.day.toString().padLeft(2, '0')}/${tx.date.month.toString().padLeft(2, '0')}/${tx.date.year} ${tx.date.hour.toString().padLeft(2, '0')}:${tx.date.minute.toString().padLeft(2, '0')}';

    final parts = tx.symbol.split('/');
    final quoteAsset = parts.length > 1 ? parts[1] : (tx.symbol.contains('-') ? tx.symbol.split('-')[1] : 'USDT');
    final baseAsset = parts.isNotEmpty ? parts[0] : 'ETH';

    final matches = provider.matches.where((m) => m.buyTransactionId == tx.id || m.sellTransactionId == tx.id).toList();

    // Standard buy size for exchange
    final standardBuySize = provider.getBuyAmountForExchange(tx.exchange);

    // BUY: Live Price & PnL
    final watchlistProvider = Provider.of<WatchlistProvider>(context, listen: false);
    final double? currentMarketPrice = watchlistProvider.prices[tx.symbol];

    double? buyDiffPct;
    double? buyDiffUsdt;
    bool isBuyProfit = false;

    if (isBuy && currentMarketPrice != null && currentMarketPrice > 0) {
      buyDiffPct = ((currentMarketPrice - tx.price) / tx.price) * 100;
      buyDiffUsdt = (currentMarketPrice - tx.price) * remaining;
      isBuyProfit = buyDiffPct >= 0;
    }

    // SELL: Exact vs Approximate
    double? sellExactProfitUsdt;
    double? sellExactProfitPct;
    double? sellApproxProfitUsdt;
    double? sellApproxProfitPct;

    if (!isBuy) {
      if (isFullyMatched && matches.isNotEmpty) {
        final profitSum = matches.fold<double>(0.0, (double sum, m) => sum + m.profit);
        final totalBuyCost = matches.fold<double>(0.0, (double sum, m) => sum + ((m.buyPrice ?? 0.0) * m.matchedAmount));
        sellExactProfitUsdt = profitSum;
        sellExactProfitPct = totalBuyCost > 0 ? (profitSum / totalBuyCost) * 100 : 0.0;
      } else {
        final approxBaseCost = standardBuySize * (remaining / tx.amount);
        sellApproxProfitUsdt = (tx.price * remaining) - approxBaseCost;
        sellApproxProfitPct = approxBaseCost > 0 ? (sellApproxProfitUsdt / approxBaseCost) * 100 : 0.0;
      }
    }

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.textMuted.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isBuy ? AppColors.bull.withValues(alpha: 0.15) : AppColors.bear.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isBuy ? 'COMPRA' : 'VENTA',
                          style: TextStyle(
                            color: isBuy ? AppColors.bull : AppColors.bear,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(tx.symbol, style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Exchange: ${tx.exchange}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
              Text(dateStr, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),

          // 1. BUY: Live Market PnL Card
          if (isBuy && buyDiffPct != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (isBuyProfit ? AppColors.bull : AppColors.bear).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: (isBuyProfit ? AppColors.bull : AppColors.bear).withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rendimiento con Precio Actual (En Cartera)',
                        style: TextStyle(color: isBuyProfit ? AppColors.bull : AppColors.bear, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Precio Actual: \$${currentMarketPrice!.toStringAsFixed(currentMarketPrice < 1 ? 4 : 2)} $quoteAsset',
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${isBuyProfit ? '+' : ''}${buyDiffPct.toStringAsFixed(2)}%',
                        style: TextStyle(color: isBuyProfit ? AppColors.bull : AppColors.bear, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      if (buyDiffUsdt != null && remaining > 0)
                        Text(
                          '${isBuyProfit ? '+' : ''}\$${buyDiffUsdt.abs().toStringAsFixed(2)} $quoteAsset',
                          style: TextStyle(color: isBuyProfit ? AppColors.bull : AppColors.bear, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ]

          // 2. SELL (Unmatched): Estimated Profit Card vs standard $400 purchase
          else if (!isBuy && !isFullyMatched && sellApproxProfitPct != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (sellApproxProfitPct >= 0 ? AppColors.bull : AppColors.bear).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: (sellApproxProfitPct >= 0 ? AppColors.bull : AppColors.bear).withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.secondary.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'APROXIMADO',
                              style: TextStyle(color: AppColors.secondary, fontSize: 10, fontWeight: FontWeight.w900),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Ganancia Estimada',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '~${sellApproxProfitPct >= 0 ? '+' : ''}${sellApproxProfitPct.toStringAsFixed(2)}%',
                            style: TextStyle(
                              color: sellApproxProfitPct >= 0 ? AppColors.bull : AppColors.bear,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '~${sellApproxProfitPct >= 0 ? '+' : ''}\$${sellApproxProfitUsdt!.abs().toStringAsFixed(2)} USDT',
                            style: TextStyle(
                              color: sellApproxProfitPct >= 0 ? AppColors.bull : AppColors.bear,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Estimado basado en compras habituales de \$${standardBuySize.toStringAsFixed(0)} USDT. Casa esta venta para fijar la ganancia exacta.',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],

          const Divider(color: AppColors.border, height: 32),
          Row(
            children: [
              Expanded(child: _detailField(title: isBuy ? 'Precio de Compra' : 'Precio de Venta', value: '\$${tx.price.toStringAsFixed(tx.price > 1 ? 2 : 6)} $quoteAsset')),
              Expanded(child: _detailField(title: 'Cantidad', value: '${_formatAmount(tx.amount)} $baseAsset')),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _detailField(
                  title: isBuy ? 'Total Invertido' : 'Total Obtenido',
                  value: '\$${totalValue.toStringAsFixed(quoteAsset == 'USDT' || quoteAsset == 'USDC' ? 2 : 6)} $quoteAsset',
                  valueColor: isBuy ? AppColors.primary : AppColors.secondary,
                ),
              ),
              Expanded(child: _detailField(title: 'Comisión', value: '${tx.fee} $quoteAsset')),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _detailField(
                  title: 'Cantidad Disponible',
                  value: '${_formatAmount(remaining)} / ${_formatAmount(tx.amount)} $baseAsset',
                  valueColor: remaining > 0 ? AppColors.primary : AppColors.textMuted,
                ),
              ),
              Expanded(
                child: _detailField(
                  title: 'Estado de Casamiento',
                  value: remaining == 0 ? 'Totalmente casado' : (remaining == tx.amount ? 'Sin casar' : 'Parcialmente casado'),
                  valueColor: remaining == 0 ? AppColors.bull : (remaining == tx.amount ? AppColors.bear : AppColors.secondary),
                ),
              ),
            ],
          ),
          if (matches.isNotEmpty) ...[
            const Divider(color: AppColors.border, height: 32),
            const Text('Casamientos Relacionados', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 150),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: matches.length,
                itemBuilder: (context, i) {
                  final m = matches[i];
                  final matchedText = isBuy
                      ? 'Casado con venta a \$${m.sellPrice?.toStringAsFixed(2)}'
                      : 'Casado con compra a \$${m.buyPrice?.toStringAsFixed(2)}';
                  
                  final buyPrice = m.buyPrice ?? 1.0;
                  final percent = buyPrice > 0 ? (m.profit / (buyPrice * m.matchedAmount) * 100).toStringAsFixed(1) : '0';
                  final profitText = 'Ganancia: \$${m.profit.toStringAsFixed(2)} ($percent%)';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(matchedText, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)),
                            const SizedBox(height: 2),
                            Text('Volumen casado: ${_formatAmount(m.matchedAmount)} $baseAsset', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                          ],
                        ),
                        Text(
                          profitText,
                          style: TextStyle(
                            color: m.profit >= 0 ? AppColors.bull : AppColors.bear,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: AppColors.bear),
                onPressed: () async {
                  if (tx.id != null) {
                    await provider.deleteTransaction(tx.id!);
                  }
                  if (context.mounted) {
                    Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.delete, size: 16),
                label: const Text('Eliminar'),
              ),
              if (remaining > 0 && (remaining < tx.amount || (tx.price * remaining) < 5.0)) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.secondary,
                    side: const BorderSide(color: AppColors.secondary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    await provider.dismissDust(tx);
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: AppColors.surface,
                          content: Text(
                            'Remanente de ${_formatAmount(remaining)} $baseAsset liquidado y compra cerrada con éxito.',
                            style: const TextStyle(color: AppColors.textPrimary),
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.cleaning_services, size: 14),
                  label: const Text('Liquidar Polvillo', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
