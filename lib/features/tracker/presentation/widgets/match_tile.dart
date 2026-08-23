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
    final profit = match.profit;
    final isProfit = profit >= 0;
    final dateStr = '${match.date.day}/${match.date.month}/${match.date.year}';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isProfit ? AppColors.bull.withOpacity(0.3) : AppColors.bear.withOpacity(0.3), width: 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isProfit ? AppColors.bull.withOpacity(0.1) : AppColors.bear.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isProfit ? Icons.trending_up : Icons.trending_down,
            color: isProfit ? AppColors.bull : AppColors.bear,
          ),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              match.symbol ?? 'Par Cerrado',
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              '${isProfit ? '+' : ''}\$${profit.toStringAsFixed(2)}',
              style: TextStyle(color: isProfit ? AppColors.bull : AppColors.bear, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Text(
              'Compra: \$${match.buyPrice?.toStringAsFixed(2)}  ➔  Venta: \$${match.sellPrice?.toStringAsFixed(2)}',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Volumen casado: ${match.matchedAmount}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                Text(dateStr, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            )
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.undo, color: AppColors.textMuted, size: 18),
          tooltip: 'Deshacer Casamiento',
          onPressed: () => provider.deleteMatch(match),
        ),
      ),
    );
  }
}
