import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/exchanges/exchange_service.dart';

class OrderBookItem {
  final double price;
  final double amount;
  final double total;
  final double cumulativeAmount;

  OrderBookItem({
    required this.price,
    required this.amount,
    required this.total,
    required this.cumulativeAmount,
  });
}

class RecentTradeItem {
  final double price;
  final double amount;
  final String side; // 'buy' or 'sell'
  final DateTime time;

  RecentTradeItem({
    required this.price,
    required this.amount,
    required this.side,
    required this.time,
  });
}

class OrderBookProvider with ChangeNotifier {
  final ExchangeService _exchangeService = ExchangeService.instance;

  String _currentExchange = 'KuCoin';
  String _currentSymbol = 'ETH/USDT';

  List<OrderBookItem> _bids = [];
  List<OrderBookItem> _asks = [];
  List<RecentTradeItem> _recentTrades = [];

  double _maxCumulative = 0.0;
  bool _isLoading = false;
  String? _errorMessage;

  Timer? _pollingTimer;

  String get currentExchange => _currentExchange;
  String get currentSymbol => _currentSymbol;
  List<OrderBookItem> get bids => _bids;
  List<OrderBookItem> get asks => _asks;
  List<RecentTradeItem> get recentTrades => _recentTrades;
  double get maxCumulative => _maxCumulative;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  double get spread {
    if (_asks.isNotEmpty && _bids.isNotEmpty) {
      return _asks.first.price - _bids.first.price;
    }
    return 0.0;
  }

  double get spreadPct {
    if (_asks.isNotEmpty && _bids.isNotEmpty && _bids.first.price > 0) {
      return (spread / _bids.first.price) * 100;
    }
    return 0.0;
  }

  void init(String exchange, String symbol) {
    if (_currentExchange != exchange || _currentSymbol != symbol || _pollingTimer == null) {
      _currentExchange = exchange;
      _currentSymbol = symbol;
      fetchOrderBookAndTrades();
      _startPolling();
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      fetchOrderBookAndTrades(silent: true);
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> fetchOrderBookAndTrades({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      final futures = await Future.wait([
        _exchangeService.fetchOrderBook(_currentExchange, _currentSymbol, limit: 25),
        _exchangeService.fetchRecentTrades(_currentExchange, _currentSymbol, limit: 30),
      ]);

      final obData = futures[0] as Map<String, dynamic>;
      final tradesData = futures[1] as List<Map<String, dynamic>>;

      // Process Bids
      final rawBids = obData['bids'] as List<List<double>>? ?? [];
      double cumBid = 0.0;
      final List<OrderBookItem> processedBids = [];
      for (var b in rawBids) {
        final p = b[0];
        final a = b[1];
        cumBid += a;
        processedBids.add(OrderBookItem(
          price: p,
          amount: a,
          total: p * a,
          cumulativeAmount: cumBid,
        ));
      }

      // Process Asks (reversed so highest price is at top)
      final rawAsks = obData['asks'] as List<List<double>>? ?? [];
      double cumAsk = 0.0;
      final List<OrderBookItem> processedAsks = [];
      for (var a in rawAsks) {
        final p = a[0];
        final amt = a[1];
        cumAsk += amt;
        processedAsks.add(OrderBookItem(
          price: p,
          amount: amt,
          total: p * amt,
          cumulativeAmount: cumAsk,
        ));
      }

      _maxCumulative = (cumBid > cumAsk ? cumBid : cumAsk).clamp(0.0001, double.infinity);
      _bids = processedBids;
      _asks = processedAsks;

      // Process Trades
      _recentTrades = tradesData.map<RecentTradeItem>((t) {
        return RecentTradeItem(
          price: (t['price'] as num).toDouble(),
          amount: (t['size'] as num).toDouble(),
          side: t['side'] as String,
          time: DateTime.fromMillisecondsSinceEpoch(t['time'] as int),
        );
      }).toList();

      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
