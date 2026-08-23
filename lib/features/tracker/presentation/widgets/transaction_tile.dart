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

    // Parse base and quote assets
    final parts = tx.symbol.split('/');
    final baseAsset = parts.isNotEmpty ? parts[0] : 'ETH';
    final quoteAsset = parts.length > 1 ? parts[1] : (tx.symbol.contains('-') ? tx.symbol.split('-')[1] : 'USDT');

    // Totals in the right currency (quote asset, e.g. USDT)
    final totalQuoteValue = tx.price * tx.amount;
    final remainingQuoteValue = tx.price * remaining;

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
              // Row 1: Type & Symbol | Total Value in Right Currency (USDT)
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
                  // Prominent Total in Quote Currency (e.g. USDT)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Total: \$${totalQuoteValue.toStringAsFixed(2)} $quoteAsset',
                        style: TextStyle(
                          color: isBuy ? AppColors.primary : AppColors.secondary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Row 2: Price | Token Amount
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Precio: \$${tx.price.toStringAsFixed(2)} $quoteAsset',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                  Text(
                    'Cantidad: ${tx.amount} $baseAsset',
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
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
