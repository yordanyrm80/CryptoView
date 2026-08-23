import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/transaction_model.dart';
import '../../providers/tracker_provider.dart';

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
    final dateStr = '${tx.date.day}/${tx.date.month}/${tx.date.year}';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? (isBuy ? AppColors.bull.withOpacity(0.15) : AppColors.bear.withOpacity(0.15)) : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? (isBuy ? AppColors.bull : AppColors.bear) : AppColors.border,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        onTap: onTapDetail,
        leading: GestureDetector(
          onTap: onSelectForMatch,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: isSelected ? (isBuy ? AppColors.bull : AppColors.bear) : AppColors.border.withOpacity(0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isSelected ? Icons.check : (isBuy ? Icons.arrow_downward : Icons.arrow_upward),
              color: isSelected ? AppColors.background : (isBuy ? AppColors.bull : AppColors.bear),
              size: 20,
            ),
          ),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              tx.symbol,
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Text(
              '\$${tx.price.toStringAsFixed(2)}',
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Disp: $remaining ${isPartiallyMatched ? '(${tx.amount})' : ''}',
                  style: TextStyle(
                    color: isPartiallyMatched ? AppColors.secondary : AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                Text('${tx.exchange} · $dateStr', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ],
        ),
        trailing: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: isSelected ? (isBuy ? AppColors.bull : AppColors.bear) : AppColors.card,
            foregroundColor: isSelected ? Colors.white : AppColors.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            minimumSize: const Size(60, 30),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(color: isSelected ? Colors.transparent : AppColors.border),
            ),
          ),
          onPressed: onSelectForMatch,
          child: Text(isSelected ? 'Listo' : 'Casar', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}
