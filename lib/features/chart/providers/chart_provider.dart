import 'package:flutter/material.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/utils/exchange_service.dart';

class ChartProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _candles = [];
  List<Map<String, dynamic>> _drawings = [];
  bool _isLoading = false;
  bool _isDrawingMode = false; // Kept for backwards compatibility
  String _activeInterval = '1h'; // default 1 hour

  // Tool states: 'none', 'horizontal_line', 'ruler'
  String _activeTool = 'none';

  // Ruler (Medidor de Porcentaje) states
  double? _rulerStartPrice;
  DateTime? _rulerStartTime;
  double? _rulerEndPrice;
  DateTime? _rulerEndTime;
  double? _rulerPercent;

  List<Map<String, dynamic>> get candles => _candles;
  List<Map<String, dynamic>> get drawings => _drawings;
  bool get isLoading => _isLoading;
  bool get isDrawingMode => _isDrawingMode;
  String get activeInterval => _activeInterval;
  String get activeTool => _activeTool;

  // Ruler getters
  double? get rulerStartPrice => _rulerStartPrice;
  DateTime? get rulerStartTime => _rulerStartTime;
  double? get rulerEndPrice => _rulerEndPrice;
  DateTime? get rulerEndTime => _rulerEndTime;
  double? get rulerPercent => _rulerPercent;

  void toggleDrawingMode() {
    _isDrawingMode = !_isDrawingMode;
    if (_isDrawingMode) {
      _activeTool = 'horizontal_line';
    } else {
      _activeTool = 'none';
    }
    notifyListeners();
  }

  void setDrawingMode(bool active) {
    _isDrawingMode = active;
    if (active) {
      _activeTool = 'horizontal_line';
    } else {
      _activeTool = 'none';
    }
    notifyListeners();
  }

  // Change active drawing tool
  void setActiveTool(String tool) {
    _activeTool = tool;
    _isDrawingMode = (tool == 'horizontal_line');
    // Reset ruler workspace when switching tools
    _rulerStartPrice = null;
    _rulerStartTime = null;
    notifyListeners();
  }

  // Handle ruler tap coordinates
  void handleRulerTap(double price, DateTime time) {
    if (_rulerStartPrice == null) {
      _rulerStartPrice = price;
      _rulerStartTime = time;
      _rulerEndPrice = null;
      _rulerEndTime = null;
      _rulerPercent = null;
      notifyListeners();
    } else {
      _rulerEndPrice = price;
      _rulerEndTime = time;
      _rulerPercent = ((_rulerEndPrice! - _rulerStartPrice!) / _rulerStartPrice!) * 100;
      // Do not reset tool automatically, so the user can see the calculation.
      notifyListeners();
    }
  }

  // Clear ruler measurement
  void clearRuler() {
    _rulerStartPrice = null;
    _rulerStartTime = null;
    _rulerEndPrice = null;
    _rulerEndTime = null;
    _rulerPercent = null;
    notifyListeners();
  }

  // Update ruler start price while dragging
  void updateRulerStartPrice(double price) {
    _rulerStartPrice = price;
    if (_rulerEndPrice != null) {
      _rulerPercent = ((_rulerEndPrice! - _rulerStartPrice!) / _rulerStartPrice!) * 100;
    }
    notifyListeners();
  }

  // Update ruler end price while dragging
  void updateRulerEndPrice(double price) {
    _rulerEndPrice = price;
    if (_rulerStartPrice != null) {
      _rulerPercent = ((_rulerEndPrice! - _rulerStartPrice!) / _rulerStartPrice!) * 100;
    }
    notifyListeners();
  }

  // Update ruler start time while dragging
  void updateRulerStartTime(DateTime time) {
    _rulerStartTime = time;
    notifyListeners();
  }

  // Update ruler end time while dragging
  void updateRulerEndTime(DateTime time) {
    _rulerEndTime = time;
    notifyListeners();
  }

  // Change interval dynamically
  Future<void> changeInterval(String newInterval, String exchange, String symbol) async {
    _activeInterval = newInterval;
    await loadChartData(exchange, symbol);
  }

  // Load candle data & SQLite drawings for selected exchange + symbol
  Future<void> loadChartData(String exchange, String symbol) async {
    _isLoading = true;
    _candles = [];
    _drawings = [];
    
    // Clear current ruler when changing symbol/pair
    _rulerStartPrice = null;
    _rulerStartTime = null;
    _rulerEndPrice = null;
    _rulerEndTime = null;
    _rulerPercent = null;
    
    notifyListeners();

    try {
      // 1. Fetch candles from exchange using activeInterval
      List<Map<String, dynamic>> fetchedCandles = await ExchangeService.instance.fetchKlines(
        exchange,
        symbol,
        _activeInterval,
      );
      _candles = fetchedCandles;

      // 2. Fetch drawings from SQLite
      _drawings = List<Map<String, dynamic>>.from(await DatabaseHelper.instance.queryDrawings(symbol, exchange));
    } catch (e) {
      print('Error loading chart data: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  // Add drawing to SQLite
  Future<void> addDrawing({
    required String exchange,
    required String symbol,
    required double price,
    required String color,
    required String label,
  }) async {
    final drawing = {
      'exchange': exchange,
      'symbol': symbol,
      'price': price,
      'color': color,
      'label': label,
    };
    await DatabaseHelper.instance.insertDrawing(drawing);
    _drawings = List<Map<String, dynamic>>.from(await DatabaseHelper.instance.queryDrawings(symbol, exchange));
    notifyListeners();
  }

  // Delete drawing from SQLite
  Future<void> deleteDrawing(int id, String exchange, String symbol) async {
    await DatabaseHelper.instance.deleteDrawing(id);
    _drawings = List<Map<String, dynamic>>.from(await DatabaseHelper.instance.queryDrawings(symbol, exchange));
    notifyListeners();
  }

  // Update drawing price in memory while dragging (optimistic UI update)
  void updateDrawingPriceInMemory(int index, double price) {
    if (index >= 0 && index < _drawings.length) {
      final updated = Map<String, dynamic>.from(_drawings[index]);
      updated['price'] = price;
      _drawings[index] = updated;
      notifyListeners();
    }
  }

  // Save the dragged drawing price to SQLite on drag release
  Future<void> saveDrawingPrice(int id, double price, String exchange, String symbol) async {
    await DatabaseHelper.instance.updateDrawingPrice(id, price);
    _drawings = List<Map<String, dynamic>>.from(await DatabaseHelper.instance.queryDrawings(symbol, exchange));
    notifyListeners();
  }

  // Clear all drawings (SQLite lines + Ruler)
  Future<void> clearAllDrawings(String exchange, String symbol) async {
    await DatabaseHelper.instance.clearDrawings(symbol, exchange);
    _drawings = [];
    clearRuler();
    notifyListeners();
  }
}
