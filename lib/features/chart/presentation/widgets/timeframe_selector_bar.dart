import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/chart_provider.dart';

class TimeframeSelectorBar extends StatelessWidget {
  final ChartProvider chartProvider;
  final String currentExchange;
  final String currentSymbol;

  const TimeframeSelectorBar({
    Key? key,
    required this.chartProvider,
    required this.currentExchange,
    required this.currentSymbol,
  }) : super(key: key);

  Widget _timeframeButton(String interval, String label) {
    final bool isActive = chartProvider.activeInterval == interval;
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: isActive ? AppColors.primary : AppColors.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        minimumSize: const Size(40, 32),
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
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(
          bottom: BorderSide(color: AppColors.gridLine, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _timeframeButton('1m', '1m'),
          _timeframeButton('5m', '5m'),
          _timeframeButton('15m', '15m'),
          _timeframeButton('1h', '1h'),
          _timeframeButton('4h', '4h'),
          _timeframeButton('1d', '1d'),
        ],
      ),
    );
  }
}
