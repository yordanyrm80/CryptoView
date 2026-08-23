import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/transaction_model.dart';
import '../../providers/tracker_provider.dart';
import '../../../watchlist/providers/watchlist_provider.dart';

class TransactionTile extends StatelessWidget {
  final TransactionModel tx;
  final TrackerProvider provider;
  final bool isSelected;
  final VoidCallback onSelectForMatch;
  final VoidCallback onTapDetail;

  const TransactionTile({
    Key? key,
    required this.tx,
    required this.provider,
    required this.isSelected,
    required this.onSelectForMatch,
    required this.onTapDetail,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isBuy = tx.type == 'buy';
    final remaining = provider.getRemainingAmount(tx);
    final isPartiallyMatched = remaining < tx.amount;
    final dateStr = '${tx.date.day.toString().padLeft(2, '0')}/${tx.date.month.toString().padLeft(2, '0')}/${tx.date.year}';

    // Parse base and quote assets
    final parts = tx.symbol.split('/');
    final baseAsset = parts.isNotEmpty ? parts[0] : 'ETH';
    final quoteAsset = parts.length > 1 ? parts[1] : (tx.symbol.contains('-') ? tx.symbol.split('-')[1] : 'USDT');

    // Totals in the right currency (quote asset, e.g. USDT)
    final totalQuoteValue = tx.price * tx.amount;
    final remainingQuoteValue = tx.price * remaining;

    // Live Price & PnL calculations
    final watchlistProvider = Provider.of<WatchlistProvider>(context);
    final double? currentMarketPrice = watchlistProvider.prices[tx.symbol];

    double? diffPct;
    double? diffUsdt;
    bool isProfit = false;

    if (currentMarketPrice != null && currentMarketPrice > 0) {
      if (isBuy) {
        diffPct = ((currentMarketPrice - tx.price) / tx.price) * 100;
        diffUsdt = (currentMarketPrice - tx.price) * remaining;
        isProfit = diffPct >= 0;
      } else {
        // For sells: difference vs current price
        diffPct = ((tx.price - currentMarketPrice) / currentMarketPrice) * 100;
        diffUsdt = (tx.price - currentMarketPrice) * remaining;
        isProfit = diffPct >= 0;
      }
    }

    final pnlColor = isProfit ? AppColors.bull : AppColors.bear;
    final sign = isProfit ? '+' : '';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? (isBuy ? AppColors.bull.withValues(alpha: 0.15) : AppColors.bear.withValues(alpha: 0.15)) : AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? (isBuy ? AppColors.bull : AppColors.bear) : AppColors.border,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTapDetail,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: Type & Symbol | Live PnL % Badge & Total Value
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                      Text(
                        tx.symbol,
                        style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),

                  // Prominent Live PnL Badge (Green if Profit, Red if Loss)
                  if (diffPct != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: pnlColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: pnlColor, width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isProfit ? Icons.arrow_upward : Icons.arrow_downward,
                            color: pnlColor,
                            size: 13,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '$sign${diffPct.toStringAsFixed(2)}%',
                            style: TextStyle(
                              color: pnlColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          if (diffUsdt != null) ...[
                            Text(
                              ' ($sign\$${diffUsdt.abs().toStringAsFixed(2)})',
                              style: TextStyle(
                                color: pnlColor.withValues(alpha: 0.9),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 10),

              // Row 2: Price (and Current Market Price) | Token Amount & Total Value
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Precio de Orden: \$${tx.price.toStringAsFixed(tx.price < 1 ? 4 : 2)} $quoteAsset',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      if (currentMarketPrice != null && currentMarketPrice > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Precio Actual: \$${currentMarketPrice.toStringAsFixed(currentMarketPrice < 1 ? 4 : 2)} $quoteAsset',
                            style: TextStyle(color: pnlColor, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${tx.amount} $baseAsset',
                        style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Total: \$${totalQuoteValue.toStringAsFixed(2)} $quoteAsset',
                        style: TextStyle(
                          color: isBuy ? AppColors.primary : AppColors.secondary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 8),
              const Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 8),

              // Row 3: Available (Disp in USDT and Base) | Match Button & Date
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('Disponible: ', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                          Text(
                            '\$${remainingQuoteValue.toStringAsFixed(2)} $quoteAsset',
                            style: TextStyle(
                              color: isPartiallyMatched ? AppColors.secondary : AppColors.bull,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          Text(' ($remaining $baseAsset)', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('${tx.exchange} · $dateStr', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSelected ? (isBuy ? AppColors.bull : AppColors.bear) : AppColors.card,
                      foregroundColor: isSelected ? Colors.white : AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      minimumSize: const Size(70, 32),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: isSelected ? Colors.transparent : AppColors.border),
                      ),
                    ),
                    onPressed: onSelectForMatch,
                    icon: Icon(isSelected ? Icons.check : Icons.link, size: 14),
                    label: Text(isSelected ? 'Listo' : 'Casar', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
