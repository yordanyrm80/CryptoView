import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/chart_provider.dart';

class TimeframeSelectorBar extends StatelessWidget {
  final ChartProvider chartProvider;
  final String currentExchange;
  final String currentSymbol;
  final VoidCallback onOpenLayers;

  const TimeframeSelectorBar({
    Key? key,
    required this.chartProvider,
    required this.currentExchange,
    required this.currentSymbol,
    required this.onOpenLayers,
  }) : super(key: key);

  Widget _timeframeButton(String interval, String label) {
    final bool isActive = chartProvider.activeInterval == interval;
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: isActive ? AppColors.primary : AppColors.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        minimumSize: const Size(38, 30),
      ),
      onPressed: () {
        chartProvider.changeInterval(interval, currentExchange, currentSymbol);
      },
      child: Text(
        label,
        style: TextStyle(
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(
          bottom: BorderSide(color: AppColors.gridLine, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              _timeframeButton('1m', '1m'),
              _timeframeButton('5m', '5m'),
              _timeframeButton('15m', '15m'),
              _timeframeButton('1h', '1h'),
              _timeframeButton('4h', '4h'),
              _timeframeButton('1d', '1d'),
            ],
          ),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onOpenLayers,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.layers_outlined, color: AppColors.primary, size: 14),
                  SizedBox(width: 5),
                  Text(
                    'Capas',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
