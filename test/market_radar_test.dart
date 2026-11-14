import 'package:flutter_test/flutter_test.dart';
import 'package:cryptoview/features/bots/domain/bot_models.dart';
import 'package:cryptoview/features/bots/providers/bots_provider.dart';

void main() {
  group('MarketRadarData & Multi-Asset Presets', () {
    test('MarketRadarData.fromJson parses all macro telemetry & Pi Cycle fields', () {
      final radar = MarketRadarData.fromJson({
        'symbol': 'ETH/USDT',
        'calculated_at': '2026-11-14T12:00:00Z',
        'current_price': 2150.5,
        'ath_price': 4868.0,
        'daily_ema_200': 2400.0,
        'daily_ema_50': 2100.0,
        'daily_rsi': 34.2,
        'dist_daily_ema_200_pct': -10.4,
        'drawdown_from_ath_pct': -55.8,
        'days_above_daily_ema_200': 0.0,
        'days_since_last_halving': 574,
        'entry_radar': {
          'status': 'PANIC_CAPITULATION',
          'traffic_light': 'GREEN',
          'title': 'Pozo de Capitulación',
          'recommendation': 'Sobreventa profunda.',
          'is_ideal_entry': true,
          'historical_win_rate_1y_pct': 100.0,
          'historical_avg_return_1y_pct': 136.0,
        },
        'exit_radar': {
          'status': 'HEALTHY_TREND',
          'traffic_light': 'GREEN',
          'title': 'Normal',
          'recommendation': 'Sin alertas.',
          'is_exit_warning': false,
          'suggested_action': 'NONE',
        },
        'pi_cycle_metrics': {
          'sma_111d': 2200.0,
          'sma_350d_x2': 4900.0,
          'pi_ratio': 0.449,
          'is_triggered': false,
        },
      });

      expect(radar.symbol, 'ETH/USDT');
      expect(radar.currentPrice, 2150.5);
      expect(radar.athPrice, 4868.0);
      expect(radar.drawdownFromAthPct, -55.8);
      expect(radar.distDailyEma200Pct, -10.4);
      expect(radar.dailyRsi, 34.2);
      expect(radar.daysSinceLastHalving, 574);
      expect(radar.entryRadar.isIdealEntry, isTrue);
      expect(radar.piCycleMetrics.piRatio, 0.449);
      expect(radar.piCycleMetrics.isTriggered, isFalse);
    });

    test('BotsProvider.mejorPresetParaSimbolo selects coin preset generically with fallback', () {
      final provider = BotsProvider();

      final ethPreset = provider.mejorPresetParaSimbolo('ETH/USDT');
      expect(ethPreset.id, 'recommended_eth_ultra');
      expect(ethPreset.takeProfitPct, 4.2);
      expect(ethPreset.pesoTendencia, 0.85);
      expect(ethPreset.pesosTramosSuelo, [0.50, 0.35, 0.25]);

      final btcPreset = provider.mejorPresetParaSimbolo('BTC/USDT');
      expect(btcPreset.id, 'recommended_btc_quantum_evolution');

      final kcsPreset = provider.mejorPresetParaSimbolo('KCS/USDT');
      expect(kcsPreset.id, 'recommended_btc_quantum_evolution');

      final customPreset = provider.mejorPresetParaSimbolo('SOL-USDT');
      expect(customPreset.id, 'recommended_btc_quantum_evolution');
    });
  });
}
