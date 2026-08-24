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
  bool _showBuyLabels = true;
  bool _showSellLines = true;
  bool _showSellLabels = true;
  bool _showOpenOrders = true;
  bool _showOpenOrderLabels = true;
  bool _showDrawings = true;
  bool _showDrawingLabels = true;
  bool _showCurrentPriceLine = true;
  bool _showCurrentPriceLabel = true;

  double _watchlistWidth = 300.0;
  double _trackerWidth = 380.0;

  bool _isLoaded = false;

  SettingsProvider() {
    loadSettings();
  }

  String get buyLineColorHex => _buyLineColorHex;
  String get sellLineColorHex => _sellLineColorHex;
  String get currentPriceColorHex => _currentPriceColorHex;

  bool get showBuyLines => _showBuyLines;
  bool get showBuyLabels => _showBuyLabels;
  bool get showSellLines => _showSellLines;
  bool get showSellLabels => _showSellLabels;
  bool get showOpenOrders => _showOpenOrders;
  bool get showOpenOrderLabels => _showOpenOrderLabels;
  bool get showDrawings => _showDrawings;
  bool get showDrawingLabels => _showDrawingLabels;
  bool get showCurrentPriceLine => _showCurrentPriceLine;
  bool get showCurrentPriceLabel => _showCurrentPriceLabel;

  bool get areAllLabelsVisible =>
      _showBuyLabels && _showSellLabels && _showOpenOrderLabels && _showDrawingLabels && _showCurrentPriceLabel;

  bool get areAllLinesVisible =>
      _showBuyLines && _showSellLines && _showOpenOrders && _showDrawings && _showCurrentPriceLine;

  double get watchlistWidth => _watchlistWidth;
  double get trackerWidth => _trackerWidth;
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

      _showBuyLines = (await db.getGeneralSetting('show_buy_lines', defaultValue: '1')) == '1';
      _showBuyLabels = (await db.getGeneralSetting('show_buy_labels', defaultValue: '1')) == '1';

      _showSellLines = (await db.getGeneralSetting('show_sell_lines', defaultValue: '1')) == '1';
      _showSellLabels = (await db.getGeneralSetting('show_sell_labels', defaultValue: '1')) == '1';

      _showOpenOrders = (await db.getGeneralSetting('show_open_orders', defaultValue: '1')) == '1';
      _showOpenOrderLabels = (await db.getGeneralSetting('show_open_order_labels', defaultValue: '1')) == '1';

      _showDrawings = (await db.getGeneralSetting('show_drawings', defaultValue: '1')) == '1';
      _showDrawingLabels = (await db.getGeneralSetting('show_drawing_labels', defaultValue: '1')) == '1';

      _showCurrentPriceLine = (await db.getGeneralSetting('show_current_price_line', defaultValue: '1')) == '1';
      _showCurrentPriceLabel = (await db.getGeneralSetting('show_current_price_label', defaultValue: '1')) == '1';

      final wWidthStr = await db.getGeneralSetting('watchlist_width', defaultValue: '300.0');
      _watchlistWidth = double.tryParse(wWidthStr ?? '300.0') ?? 300.0;

      final tWidthStr = await db.getGeneralSetting('tracker_width', defaultValue: '380.0');
      _trackerWidth = double.tryParse(tWidthStr ?? '380.0') ?? 380.0;

      _isLoaded = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }
  }

  Future<void> setWatchlistWidth(double w) async {
    _watchlistWidth = w.clamp(180.0, 550.0);
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('watchlist_width', _watchlistWidth.toStringAsFixed(1));
  }

  Future<void> setTrackerWidth(double w) async {
    _trackerWidth = w.clamp(240.0, 700.0);
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('tracker_width', _trackerWidth.toStringAsFixed(1));
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

  Future<void> setShowBuyLabels(bool show) async {
    _showBuyLabels = show;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('show_buy_labels', show ? '1' : '0');
  }

  Future<void> setShowSellLines(bool show) async {
    _showSellLines = show;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('show_sell_lines', show ? '1' : '0');
  }

  Future<void> setShowSellLabels(bool show) async {
    _showSellLabels = show;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('show_sell_labels', show ? '1' : '0');
  }

  Future<void> setShowOpenOrders(bool show) async {
    _showOpenOrders = show;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('show_open_orders', show ? '1' : '0');
  }

  Future<void> setShowOpenOrderLabels(bool show) async {
    _showOpenOrderLabels = show;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('show_open_order_labels', show ? '1' : '0');
  }

  Future<void> setShowDrawings(bool show) async {
    _showDrawings = show;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('show_drawings', show ? '1' : '0');
  }

  Future<void> setShowDrawingLabels(bool show) async {
    _showDrawingLabels = show;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('show_drawing_labels', show ? '1' : '0');
  }

  Future<void> setShowCurrentPriceLine(bool show) async {
    _showCurrentPriceLine = show;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('show_current_price_line', show ? '1' : '0');
  }

  Future<void> setShowCurrentPriceLabel(bool show) async {
    _showCurrentPriceLabel = show;
    notifyListeners();
    await DatabaseHelper.instance.setGeneralSetting('show_current_price_label', show ? '1' : '0');
  }

  /// Master switch: Toggle all labels (text) ON or OFF across all line categories with 1 click
  Future<void> toggleAllLabels(bool show) async {
    _showBuyLabels = show;
    _showSellLabels = show;
    _showOpenOrderLabels = show;
    _showDrawingLabels = show;
    _showCurrentPriceLabel = show;
    notifyListeners();

    final db = DatabaseHelper.instance;
    final val = show ? '1' : '0';
    await db.setGeneralSetting('show_buy_labels', val);
    await db.setGeneralSetting('show_sell_labels', val);
    await db.setGeneralSetting('show_open_order_labels', val);
    await db.setGeneralSetting('show_drawing_labels', val);
    await db.setGeneralSetting('show_current_price_label', val);
  }

  /// Master switch: Toggle all lines ON or OFF across all categories with 1 click
  Future<void> toggleAllLines(bool show) async {
    _showBuyLines = show;
    _showSellLines = show;
    _showOpenOrders = show;
    _showDrawings = show;
    _showCurrentPriceLine = show;
    notifyListeners();

    final db = DatabaseHelper.instance;
    final val = show ? '1' : '0';
    await db.setGeneralSetting('show_buy_lines', val);
    await db.setGeneralSetting('show_sell_lines', val);
    await db.setGeneralSetting('show_open_orders', val);
    await db.setGeneralSetting('show_drawings', val);
    await db.setGeneralSetting('show_current_price_line', val);
  }

  Future<void> resetToDefaults() async {
    _buyLineColorHex = defaultBuyLineColor;
    _sellLineColorHex = defaultSellLineColor;
    _currentPriceColorHex = defaultCurrentPriceColor;
    _showBuyLines = true;
    _showBuyLabels = true;
    _showSellLines = true;
    _showSellLabels = true;
    _showOpenOrders = true;
    _showOpenOrderLabels = true;
    _showCurrentPriceLine = true;
    _showCurrentPriceLabel = true;
    _showDrawings = true;
    _showDrawingLabels = true;
    notifyListeners();

    final db = DatabaseHelper.instance;
    await db.setGeneralSetting('buy_line_color', defaultBuyLineColor);
    await db.setGeneralSetting('sell_line_color', defaultSellLineColor);
    await db.setGeneralSetting('current_price_color', defaultCurrentPriceColor);
    await db.setGeneralSetting('show_buy_lines', '1');
    await db.setGeneralSetting('show_buy_labels', '1');
    await db.setGeneralSetting('show_sell_lines', '1');
    await db.setGeneralSetting('show_sell_labels', '1');
    await db.setGeneralSetting('show_open_orders', '1');
    await db.setGeneralSetting('show_open_order_labels', '1');
    await db.setGeneralSetting('show_current_price_line', '1');
    await db.setGeneralSetting('show_current_price_label', '1');
    await db.setGeneralSetting('show_drawings', '1');
    await db.setGeneralSetting('show_drawing_labels', '1');
  }
}
