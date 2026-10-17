import 'package:flutter/material.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/services/exchanges/exchange_service.dart';
import '../domain/models/chart_candle_model.dart';

class ChartProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _candles = [];
  List<ChartData> _chartData = [];
  List<Map<String, dynamic>> _drawings = [];
  bool _isLoading = false;
  bool _isLoadingMoreHistory = false;
  bool _hasReachedHistoryEnd = false;
  int _loadGeneration = 0;
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

  ChartProvider() {
    _loadSavedTimeframe();
  }

  Future<void> _loadSavedTimeframe() async {
    try {
      final tf = await DatabaseHelper.instance.getGeneralSetting('chart_timeframe');
      if (tf != null && tf.isNotEmpty) {
        _activeInterval = tf;
        notifyListeners();
      }
    } catch (_) {}
  }

  List<Map<String, dynamic>> get candles => _candles;
  List<ChartData> get chartData => _chartData;
  List<Map<String, dynamic>> get drawings => _drawings;
  bool get isLoading => _isLoading;
  bool get isLoadingMoreHistory => _isLoadingMoreHistory;
  bool get hasReachedHistoryEnd => _hasReachedHistoryEnd;
  int get loadGeneration => _loadGeneration;
  bool get isDrawingMode => _isDrawingMode;
  String get activeInterval => _activeInterval;
  String get activeTool => _activeTool;

  int _getIntervalSeconds(String interval) {
    switch (interval.toLowerCase()) {
      case '1m':
        return 60;
      case '3m':
        return 180;
      case '5m':
        return 300;
      case '15m':
        return 900;
      case '30m':
        return 1800;
      case '1h':
        return 3600;
      case '2h':
        return 7200;
      case '4h':
        return 14400;
      case '6h':
        return 21600;
      case '12h':
        return 43200;
      case '1d':
        return 86400;
      case '1w':
        return 604800;
      default:
        return 3600;
    }
  }

  void _rebuildChartData() {
    _chartData = _candles.map<ChartData>((c) {
      return ChartData(
        date: DateTime.fromMillisecondsSinceEpoch((c['time'] as int) * 1000),
        open: (c['open'] as num).toDouble(),
        high: (c['high'] as num).toDouble(),
        low: (c['low'] as num).toDouble(),
        close: (c['close'] as num).toDouble(),
      );
    }).toList();
  }

  /// Actualiza en vivo la última vela con el precio en tiempo real sin reiniciar el gráfico.
  /// Retorna `1` si se actualizó la última vela existente, `2` si se abrió una nueva vela, o `null` si no hubo cambio.
  int? updateLivePrice(double livePrice) {
    if (_candles.isEmpty || _chartData.isEmpty || livePrice <= 0) return null;

    final int intervalSec = _getIntervalSeconds(_activeInterval);
    final int nowUtcSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final int lastIdx = _candles.length - 1;
    final Map<String, dynamic> lastMap = _candles[lastIdx];
    final int lastTimeSec = (lastMap['time'] as num).toInt();

    if (nowUtcSec < lastTimeSec + intervalSec) {
      final double oldClose = (lastMap['close'] as num).toDouble();
      if ((oldClose - livePrice).abs() < 1e-10) return null;

      final double open = (lastMap['open'] as num).toDouble();
      final double oldHigh = (lastMap['high'] as num).toDouble();
      final double oldLow = (lastMap['low'] as num).toDouble();
      final double newHigh = livePrice > oldHigh ? livePrice : oldHigh;
      final double newLow = livePrice < oldLow ? livePrice : oldLow;

      final updatedMap = Map<String, dynamic>.from(lastMap);
      updatedMap['high'] = newHigh;
      updatedMap['low'] = newLow;
      updatedMap['close'] = livePrice;
      _candles[lastIdx] = updatedMap;

      _chartData[lastIdx] = ChartData(
        date: DateTime.fromMillisecondsSinceEpoch(lastTimeSec * 1000),
        open: open,
        high: newHigh,
        low: newLow,
        close: livePrice,
      );
      return 1;
    } else {
      final int newBucketSec = (nowUtcSec ~/ intervalSec) * intervalSec;
      final double prevClose = (lastMap['close'] as num).toDouble();
      final double newHigh = livePrice > prevClose ? livePrice : prevClose;
      final double newLow = livePrice < prevClose ? livePrice : prevClose;

      _candles.add({
        'time': newBucketSec,
        'open': prevClose,
        'high': newHigh,
        'low': newLow,
        'close': livePrice,
        'volume': 0.0,
      });

      _chartData.add(
        ChartData(
          date: DateTime.fromMillisecondsSinceEpoch(newBucketSec * 1000),
          open: prevClose,
          high: newHigh,
          low: newLow,
          close: livePrice,
        ),
      );
      return 2;
    }
  }

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
    if (_rulerStartPrice == null || _rulerEndPrice != null) {
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
    DatabaseHelper.instance.setGeneralSetting('chart_timeframe', newInterval);
    await loadChartData(exchange, symbol);
  }

  // Load candle data & SQLite drawings for selected exchange + symbol
  Future<void> loadChartData(String exchange, String symbol) async {
    // Clear current ruler when changing symbol/pair
    _rulerStartPrice = null;
    _rulerStartTime = null;
    _rulerEndPrice = null;
    _rulerEndTime = null;
    _rulerPercent = null;
    _isLoadingMoreHistory = false;
    _hasReachedHistoryEnd = false;
    _loadGeneration++;

    int? cachedOldestTime;

    // 1. Immediately load any previously saved candles from local SQLite
    try {
      final cached = await DatabaseHelper.instance.getCandles(
        exchange: exchange,
        symbol: symbol,
        interval: _activeInterval,
        limit: 1500,
      );
      if (cached.isNotEmpty) {
        cachedOldestTime = (cached.first['time'] as num).toInt();
        _candles = cached;
        _rebuildChartData();
        _isLoading = false;
        notifyListeners();
      } else {
        _isLoading = true;
        _candles = [];
        _rebuildChartData();
        notifyListeners();
      }
    } catch (e) {
      _isLoading = true;
      _candles = [];
      _rebuildChartData();
      notifyListeners();
    }

    try {
      // 2. Fetch fresh candles from Cloud Data Engine (or fallback exchange) using activeInterval
      List<Map<String, dynamic>> fetchedCandles = await ExchangeService.instance.fetchKlines(
        exchange,
        symbol,
        _activeInterval,
        limit: 1500,
      );

      if (fetchedCandles.isNotEmpty) {
        // 3. Save / Upsert fetched candles into SQLite
        await DatabaseHelper.instance.saveCandles(
          exchange: exchange,
          symbol: symbol,
          interval: _activeInterval,
          candles: fetchedCandles,
        );

        // 4. Retrieve complete merged history from SQLite
        final merged = await DatabaseHelper.instance.getCandles(
          exchange: exchange,
          symbol: symbol,
          interval: _activeInterval,
          limit: 1500,
        );
        _candles = merged.isNotEmpty ? merged : fetchedCandles;
        final int newOldestTime = (_candles.first['time'] as num).toInt();
        if (cachedOldestTime == null || newOldestTime != cachedOldestTime) {
          _loadGeneration++;
        }
        _rebuildChartData();
      }

      // 5. Fetch drawings from SQLite
      _drawings = List<Map<String, dynamic>>.from(await DatabaseHelper.instance.queryDrawings(symbol, exchange));
    } catch (e) {
      print('Error loading chart data: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Carga un bloque adicional de 1,500 velas históricas anteriores a la vela más antigua actual.
  /// Retorna la cantidad de velas antiguas nuevas agregadas al principio de la serie.
  Future<int> loadMoreHistory(String exchange, String symbol) async {
    if (_isLoading || _isLoadingMoreHistory || _hasReachedHistoryEnd || _candles.isEmpty) {
      return 0;
    }

    _isLoadingMoreHistory = true;

    try {
      final int oldestTimeSec = (_candles.first['time'] as num).toInt();
      final int beforeSec = oldestTimeSec - 1;

      List<Map<String, dynamic>> olderFetched = await ExchangeService.instance.fetchKlines(
        exchange,
        symbol,
        _activeInterval,
        limit: 1500,
        endTimeSec: beforeSec,
      );

      if (olderFetched.isNotEmpty) {
        await DatabaseHelper.instance.saveCandles(
          exchange: exchange,
          symbol: symbol,
          interval: _activeInterval,
          candles: olderFetched,
        );
      } else {
        olderFetched = await DatabaseHelper.instance.getCandles(
          exchange: exchange,
          symbol: symbol,
          interval: _activeInterval,
          limit: 1500,
          beforeTimeSec: beforeSec,
        );
      }

      final existingTimes = _candles.map((c) => (c['time'] as num).toInt()).toSet();
      final strictlyOlder = olderFetched
          .where((c) {
            final t = (c['time'] as num).toInt();
            return t < oldestTimeSec && !existingTimes.contains(t);
          })
          .toList();

      if (strictlyOlder.isEmpty) {
        _hasReachedHistoryEnd = true;
        _isLoadingMoreHistory = false;
        return 0;
      }

      strictlyOlder.sort((a, b) => (a['time'] as num).toInt().compareTo((b['time'] as num).toInt()));
      _candles = [...strictlyOlder, ..._candles];
      _rebuildChartData();
      _isLoadingMoreHistory = false;
      return strictlyOlder.length;
    } catch (e) {
      debugPrint('Error loading older chart history: $e');
      _isLoadingMoreHistory = false;
      return 0;
    }
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
