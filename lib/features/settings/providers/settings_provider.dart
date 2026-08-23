import 'package:flutter/material.dart';
import '../../../core/database/database_helper.dart';

class SettingsProvider with ChangeNotifier {
  // Default values
  static const String defaultBuyLineColor = '#00E676'; // Neon Green
  static const String defaultSellLineColor = '#FF5252'; // Neon Red
  static const String defaultCurrentPriceColor = '#00E5FF'; // Electric Cyan

  String _buyLineColorHex = defaultBuyLineColor;
  String _sellLineColorHex = defaultSellLineColor;
  String _currentPriceColorHex = defaultCurrentPriceColor;

  bool _showBuyLines = true;
  bool _showSellLines = true;
  bool _showCurrentPriceLine = true;

  bool _isLoaded = false;

  SettingsProvider() {
    loadSettings();
  }

  String get buyLineColorHex => _buyLineColorHex;
  String get sellLineColorHex => _sellLineColorHex;
  String get currentPriceColorHex => _currentPriceColorHex;

  bool get showBuyLines => _showBuyLines;
  bool get showSellLines => _showSellLines;
  bool get showCurrentPriceLine => _showCurrentPriceLine;
  bool get isLoaded => _isLoaded;

  Color get buyLineColor => _parseColor(_buyLineColorHex, const Color(0xFF00E676));
  Color get sellLineColor => _parseColor(_sellLineColorHex, const Color(0xFFFF5252));
  Color get currentPriceColor => _parseColor(_currentPriceColorHex, const Color(0xFF00E5FF));

  Color _parseColor(String hexString, Color fallback) {
    try {
      final buffer = StringBuffer();
      if (hexString.length == 6 || hexString.length == 7) buffer.write('ff');
      buffer.write(hexString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (_) {
      return fallback;
    }
  }

  Future<void> loadSettings() async {
    try {
      final db = DatabaseHelper.instance;
      _buyLineColorHex = await db.getGeneralSetting('buy_line_color', defaultValue: defaultBuyLineColor) ?? defaultBuyLineColor;
      _sellLineColorHex = await db.getGeneralSetting('sell_line_color', defaultValue: defaultSellLineColor) ?? defaultSellLineColor;
      _currentPriceColorHex = await db.getGeneralSetting('current_price_color', defaultValue: defaultCurrentPriceColor) ?? defaultCurrentPriceColor;

      final showBuyStr = await db.getGeneralSetting('show_buy_lines', defaultValue: '1');
      _showBuyLines = showBuyStr == '1';

      final showSellStr = await db.getGeneralSetting('show_sell_lines', defaultValue: '1');
      _showSellLines = showSellStr == '1';

      final showCurrentPriceStr = await db.getGeneralSetting('show_current_price_line', defaultValue: '1');
      _showCurrentPriceLine = showCurrentPriceStr == '1';

      _isLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
  }

  Future<void> setBuyLineColor(String hex) async {
    _buyLineColorHex = hex;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('buy_line_color', hex);
  }

  Future<void> setSellLineColor(String hex) async {
    _sellLineColorHex = hex;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('sell_line_color', hex);
  }

  Future<void> setCurrentPriceColor(String hex) async {
    _currentPriceColorHex = hex;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('current_price_color', hex);
  }

  Future<void> setShowBuyLines(bool show) async {
    _showBuyLines = show;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('show_buy_lines', show ? '1' : '0');
  }

  Future<void> setShowSellLines(bool show) async {
    _showSellLines = show;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('show_sell_lines', show ? '1' : '0');
  }

  Future<void> setShowCurrentPriceLine(bool show) async {
    _showCurrentPriceLine = show;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('show_current_price_line', show ? '1' : '0');
  }

  Future<void> resetToDefaults() async {
    _buyLineColorHex = defaultBuyLineColor;
    _sellLineColorHex = defaultSellLineColor;
    _currentPriceColorHex = defaultCurrentPriceColor;
    _showBuyLines = true;
    _showSellLines = true;
    _showCurrentPriceLine = true;
    notifyListeners();

    final db = DatabaseHelper.instance;
    await db.setGeneralSetting('buy_line_color', defaultBuyLineColor);
    await db.setGeneralSetting('sell_line_color', defaultSellLineColor);
    await db.setGeneralSetting('current_price_color', defaultCurrentPriceColor);
    await db.setGeneralSetting('show_buy_lines', '1');
    await db.setGeneralSetting('show_sell_lines', '1');
    await db.setGeneralSetting('show_current_price_line', '1');
  }
}
