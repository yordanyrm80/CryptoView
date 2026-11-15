import 'package:flutter_test/flutter_test.dart';
import 'package:cryptoview/core/constants/app_info.dart';
import 'package:cryptoview/features/bots/providers/bots_provider.dart';
import 'package:cryptoview/features/chart/providers/chart_provider.dart';

void main() {
  group('Mobile optimizations & v1.0.1 branding', () {
    test('AppInfo exposes version 1.0.1 build 2', () {
      expect(AppInfo.appName, 'CryptoView');
      expect(AppInfo.version, '1.0.1');
      expect(AppInfo.buildNumber, 2);
      expect(AppInfo.fullVersion, '1.0.1+2');
    });

    test('ChartProvider supports compact mobile candle limit and ignores invalid values', () {
      final chartProvider = ChartProvider();
      expect(chartProvider.preferredInitialLimit, 1500);

      chartProvider.setPreferredInitialLimit(400);
      expect(chartProvider.preferredInitialLimit, 400);

      chartProvider.setPreferredInitialLimit(0);
      chartProvider.setPreferredInitialLimit(-50);
      expect(chartProvider.preferredInitialLimit, 400);
    });

    test('BotsProvider avoids eager startup loading before tab activation', () {
      final botsProvider = BotsProvider();
      expect(botsProvider.isLoading, isFalse);
      expect(botsProvider.todosLosBots, isEmpty);
    });
  });
}
