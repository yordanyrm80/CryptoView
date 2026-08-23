import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class MetricsHeaderCard extends StatelessWidget {
  final double totalProfit;
  final double winRate;
  final int totalMatches;

  const MetricsHeaderCard({
    Key? key,
    required this.totalProfit,
    required this.winRate,
    required this.totalMatches,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(
            children: [
              const Text('GANANCIA NETA TOTAL', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                '${totalProfit >= 0 ? '+' : ''}\$${totalProfit.toStringAsFixed(2)}',
                style: TextStyle(
                  color: totalProfit >= 0 ? AppColors.bull : AppColors.bear,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Container(width: 1, height: 40, color: AppColors.border),
          Column(
            children: [
              const Text('WIN RATE', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                '${winRate.toStringAsFixed(1)}%',
                style: const TextStyle(color: AppColors.secondary, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Container(width: 1, height: 40, color: AppColors.border),
          Column(
            children: [
              const Text('CASAMIENTOS', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(
                '$totalMatches',
                style: const TextStyle(color: AppColors.primary, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
