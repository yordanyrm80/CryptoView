import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/tracker_provider.dart';

class MetricsHeaderCard extends StatelessWidget {
  final TrackerProvider provider;
  final VoidCallback onRefreshBalance;

  const MetricsHeaderCard({
    Key? key,
    required this.provider,
    required this.onRefreshBalance,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final quoteAsset = provider.currentQuoteAsset;
    final totalProfit = provider.filteredTotalProfit;
    final winRate = provider.filteredWinRate;
    final totalMatches = provider.filteredMatches.length;
    final balance = provider.quoteAssetBalance;
    final capitalInBuys = provider.capitalInOpenBuys;
    final isOnlyCurrent = provider.filterOnlyCurrentSymbol;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          // Filter Selector Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.filter_list, size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    isOnlyCurrent ? 'Filtrando: ${provider.activeSymbol}' : 'Mostrando: Todas las Monedas',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              // Segmented Toggle Button
              Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => provider.setFilterOnlyCurrentSymbol(true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isOnlyCurrent ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          provider.currentBaseAsset,
                          style: TextStyle(
                            color: isOnlyCurrent ? AppColors.background : AppColors.textSecondary,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => provider.setFilterOnlyCurrentSymbol(false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: !isOnlyCurrent ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'TODOS',
                          style: TextStyle(
                            color: !isOnlyCurrent ? AppColors.background : AppColors.textSecondary,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(color: AppColors.border, height: 20),

          // Main Balance & PnL Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 1. Live Exchange Balance in Quote Asset (USDT)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'SALDO $quoteAsset (${provider.activeExchange})',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 4),
                        if (provider.isFetchingBalance)
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(strokeWidth: 1.5, valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary)),
                          )
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '\$${balance.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Capital Invested in Open Buys
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'EN COMPRAS ($quoteAsset)',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '\$${capitalInBuys.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: AppColors.buyOrder,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

              // 3. Total Net Realized Profit
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'GANANCIA PnL',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${totalProfit >= 0 ? '+' : ''}\$${totalProfit.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: totalProfit >= 0 ? AppColors.bull : AppColors.bear,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Secondary metrics badge row (Win Rate & Matched Count)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('Win Rate: ', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    Text(
                      '${winRate.toStringAsFixed(1)}%',
                      style: const TextStyle(color: AppColors.secondary, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('Operaciones Casadas: ', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                    Text(
                      '$totalMatches',
                      style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
