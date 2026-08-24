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

  String _formatAmount(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    String s = value.toStringAsFixed(6);
    s = s.replaceAll(RegExp(r'0+$'), '');
    s = s.replaceAll(RegExp(r'\.$'), '');
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final isBuy = tx.type == 'buy';
    final remaining = provider.getRemainingAmount(tx);
    final isPartiallyMatched = remaining < tx.amount;
    final isFullyMatched = remaining == 0;
    final dateStr = '${tx.date.day.toString().padLeft(2, '0')}/${tx.date.month.toString().padLeft(2, '0')}/${tx.date.year}';

    // Parse base and quote assets
    final parts = tx.symbol.split('/');
    final baseAsset = parts.isNotEmpty ? parts[0] : 'ETH';
    final quoteAsset = parts.length > 1 ? parts[1] : (tx.symbol.contains('-') ? tx.symbol.split('-')[1] : 'USDT');

    // Totals in quote currency (USDT)
    final totalQuoteValue = tx.price * tx.amount;
    final remainingQuoteValue = tx.price * remaining;

    // Standard buy size configured for this exchange (e.g. $400 USDT)
    final standardBuySize = provider.getBuyAmountForExchange(tx.exchange);

    // BUY calculation: vs Current Market Price
    final watchlistProvider = Provider.of<WatchlistProvider>(context);
    final double? currentMarketPrice = watchlistProvider.prices[tx.symbol];

    double? buyDiffPct;
    double? buyDiffUsdt;
    bool isBuyProfit = false;

    if (isBuy && currentMarketPrice != null && currentMarketPrice > 0) {
      buyDiffPct = ((currentMarketPrice - tx.price) / tx.price) * 100;
      buyDiffUsdt = (currentMarketPrice - tx.price) * remaining;
      isBuyProfit = buyDiffPct >= 0;
    }

    // SELL calculation:
    // If fully matched -> Exact profit from matches
    // If unmatched / partially unmatched -> Estimated profit vs standard $400 buy block
    double? sellExactProfitUsdt;
    double? sellExactProfitPct;
    double? sellApproxProfitUsdt;
    double? sellApproxProfitPct;

    if (!isBuy) {
      if (isFullyMatched) {
        final matchedRecords = provider.matches.where((m) => m.sellTransactionId == tx.id).toList();
        if (matchedRecords.isNotEmpty) {
          final profitSum = matchedRecords.fold<double>(0.0, (double sum, m) => sum + m.profit);
          final totalBuyCost = matchedRecords.fold<double>(0.0, (double sum, m) => sum + ((m.buyPrice ?? 0.0) * m.matchedAmount));
          sellExactProfitUsdt = profitSum;
          sellExactProfitPct = totalBuyCost > 0 ? (profitSum / totalBuyCost) * 100 : 0.0;
        }
      } else {
        // Approximate profit calculation for unmatched sell
        final approxBaseCost = standardBuySize * (remaining / tx.amount);
        sellApproxProfitUsdt = remainingQuoteValue - approxBaseCost;
        sellApproxProfitPct = approxBaseCost > 0 ? (sellApproxProfitUsdt / approxBaseCost) * 100 : 0.0;
      }
    }

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
              // Row 1: Type & Symbol | Dynamic PnL / Estimate Badge
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

                  // 1. BUY: Live PnL Badge vs Current Market Price
                  if (isBuy && buyDiffPct != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: (isBuyProfit ? AppColors.bull : AppColors.bear).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: isBuyProfit ? AppColors.bull : AppColors.bear, width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isBuyProfit ? Icons.arrow_upward : Icons.arrow_downward,
                            color: isBuyProfit ? AppColors.bull : AppColors.bear,
                            size: 13,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${isBuyProfit ? '+' : ''}${buyDiffPct.toStringAsFixed(2)}%',
                            style: TextStyle(
                              color: isBuyProfit ? AppColors.bull : AppColors.bear,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          if (buyDiffUsdt != null) ...[
                            Text(
                              ' (${isBuyProfit ? '+' : ''}\$${buyDiffUsdt.abs().toStringAsFixed(2)})',
                              style: TextStyle(
                                color: (isBuyProfit ? AppColors.bull : AppColors.bear).withValues(alpha: 0.9),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ]

                  // 2. SELL (Fully Matched): Exact Realized Profit Badge
                  else if (!isBuy && isFullyMatched && sellExactProfitPct != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: AppColors.bull.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.bull, width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.link, color: AppColors.bull, size: 13),
                          const SizedBox(width: 4),
                          Text(
                            '+${sellExactProfitPct.toStringAsFixed(1)}%',
                            style: const TextStyle(color: AppColors.bull, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          Text(
                            ' (+\$${sellExactProfitUsdt!.toStringAsFixed(2)})',
                            style: TextStyle(color: AppColors.bull.withValues(alpha: 0.9), fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ]

                  // 3. SELL (Unmatched): Distinct ESTIMATED Badge based on standard $400 buy
                  else if (!isBuy && sellApproxProfitPct != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: (sellApproxProfitPct >= 0 ? AppColors.bull : AppColors.bear).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: (sellApproxProfitPct >= 0 ? AppColors.bull : AppColors.bear).withValues(alpha: 0.6),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            margin: const EdgeInsets.only(right: 5),
                            decoration: BoxDecoration(
                              color: AppColors.secondary.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              'APROX',
                              style: TextStyle(
                                color: AppColors.secondary,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          Text(
                            '~${sellApproxProfitPct >= 0 ? '+' : ''}${sellApproxProfitPct.toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: sellApproxProfitPct >= 0 ? AppColors.bull : AppColors.bear,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            ' (~${sellApproxProfitPct >= 0 ? '+' : ''}\$${sellApproxProfitUsdt!.abs().toStringAsFixed(2)})',
                            style: TextStyle(
                              color: (sellApproxProfitPct >= 0 ? AppColors.bull : AppColors.bear).withValues(alpha: 0.85),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 10),

              // Row 2: Price (and live market price or approx basis) | Token Amount & Total
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isBuy ? 'Precio de Compra: \$${tx.price.toStringAsFixed(tx.price < 1 ? 4 : 2)} $quoteAsset'
                              : 'Precio de Venta: \$${tx.price.toStringAsFixed(tx.price < 1 ? 4 : 2)} $quoteAsset',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      if (isBuy && currentMarketPrice != null && currentMarketPrice > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Precio Actual: \$${currentMarketPrice.toStringAsFixed(currentMarketPrice < 1 ? 4 : 2)} $quoteAsset',
                            style: TextStyle(
                              color: isBuyProfit ? AppColors.bull : AppColors.bear,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      else if (!isBuy && !isFullyMatched)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Base estimada: ~\$${standardBuySize.toStringAsFixed(0)} USDT',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontStyle: FontStyle.italic),
                          ),
                        ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${_formatAmount(tx.amount)} $baseAsset',
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
                              color: isPartiallyMatched ? AppColors.secondary : (isBuy ? AppColors.bull : AppColors.bear),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          Text(' (${_formatAmount(remaining)} $baseAsset)', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
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
