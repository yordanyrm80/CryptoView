import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/match_model.dart';
import '../../providers/tracker_provider.dart';

class MatchTile extends StatelessWidget {
  final MatchModel match;
  final TrackerProvider provider;

  const MatchTile({Key? key, required this.match, required this.provider}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isExpense = match.isExpenseMatch;
    final profit = match.profit;
    final isProfit = profit >= 0;
    final dateStr = '${match.date.day}/${match.date.month}/${match.date.year}';

    final symbol = match.symbol ?? 'ETH/USDT';
    final parts = symbol.split('/');
    final baseAsset = parts.isNotEmpty ? parts[0] : 'ETH';
    final quoteAsset = parts.length > 1 ? parts[1] : (symbol.contains('-') ? symbol.split('-')[1] : 'USDT');

    final buyPrice = match.buyPrice ?? 0.0;
    final sellPrice = match.sellPrice ?? 0.0;
    final matchedAmount = match.matchedAmount;

    final buyTotalQuote = buyPrice * matchedAmount;
    final sellTotalQuote = sellPrice * matchedAmount;
    final profitPercent = buyTotalQuote > 0 ? (profit / buyTotalQuote) * 100 : 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isExpense
              ? Colors.orange.withValues(alpha: 0.3)
              : (isProfit ? AppColors.bull.withValues(alpha: 0.3) : AppColors.bear.withValues(alpha: 0.3)),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Symbol & Match badge | Net Profit or Expense Tag
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isExpense
                            ? Colors.orange.withValues(alpha: 0.12)
                            : (isProfit ? AppColors.bull.withValues(alpha: 0.1) : AppColors.bear.withValues(alpha: 0.1)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isExpense ? Icons.shopping_bag_outlined : (isProfit ? Icons.trending_up : Icons.trending_down),
                        color: isExpense ? Colors.orange : (isProfit ? AppColors.bull : AppColors.bear),
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          symbol,
                          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        if (isExpense)
                          Text(
                            match.expenseCategory ?? 'Gasto Personal',
                            style: const TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                      ],
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (isExpense) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.bull.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'CONCILIADO',
                          style: TextStyle(color: AppColors.bull, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '\$${buyTotalQuote.toStringAsFixed(2)} $quoteAsset',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                      ),
                    ] else ...[
                      Text(
                        '${isProfit ? '+' : ''}\$${profit.toStringAsFixed(2)} $quoteAsset',
                        style: TextStyle(color: isProfit ? AppColors.bull : AppColors.bear, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        '${profitPercent >= 0 ? '+' : ''}${profitPercent.toStringAsFixed(2)}%',
                        style: TextStyle(color: isProfit ? AppColors.bull : AppColors.bear, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ],
                ),
              ],
            ),

            const SizedBox(height: 10),

            // Row 2: Price Comparison with USDT totals
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('COMPRA', style: TextStyle(color: AppColors.bull, fontSize: 10, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text('\$${buyPrice.toStringAsFixed(2)}', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                      Text('Total: \$${buyTotalQuote.toStringAsFixed(2)} $quoteAsset', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ],
                  ),
                  const Icon(Icons.arrow_forward, color: AppColors.textSecondary, size: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        isExpense ? 'GASTO / CONSUMO' : 'VENTA',
                        style: TextStyle(color: isExpense ? Colors.orange : AppColors.bear, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isExpense ? (match.notes.isNotEmpty ? match.notes : (match.expenseDescription ?? 'Gasto')) : '\$${sellPrice.toStringAsFixed(2)}',
                        style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (!isExpense)
                        Text('Total: \$${sellTotalQuote.toStringAsFixed(2)} $quoteAsset', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Row 3: Matched Volume in base coin & date | Undo Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Volumen casado: $matchedAmount $baseAsset · $dateStr',
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
                IconButton(
                  icon: const Icon(Icons.undo, color: AppColors.textMuted, size: 18),
                  tooltip: 'Deshacer Casamiento',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => provider.deleteMatch(match),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
