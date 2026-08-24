import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/services/exchanges/exchange_service.dart';
import '../../../core/database/database_helper.dart';

class OpenOrderItem {
  final String id;
  final String symbol;
  final String side; // 'buy' or 'sell'
  final String type; // 'limit' or 'market'
  final double price;
  final double size;
  final double dealSize;
  final double funds;
  final DateTime createdAt;

  OpenOrderItem({
    required this.id,
    required this.symbol,
    required this.side,
    required this.type,
    required this.price,
    required this.size,
    required this.dealSize,
    required this.funds,
    required this.createdAt,
  });
}

class TradingProvider with ChangeNotifier {
  final ExchangeService _exchangeService = ExchangeService.instance;

  String _currentExchange = 'KuCoin';
  String _currentSymbol = 'ETH/USDT';

  bool _isInitialized = false;
  bool _isBuy = true;
  bool _isLimit = true;
  bool _isSubmitting = false;
  bool _isLoadingOrders = false;
  bool _isLoadingBalances = false;
  String? _statusMessage;
  bool _isSuccess = false;
  double? _lastMarketPrice;

  final TextEditingController priceController = TextEditingController();
  final TextEditingController amountController = TextEditingController();
  final TextEditingController totalController = TextEditingController();

  double _availableUSDT = 0.0;
  double _availableCrypto = 0.0;
  List<OpenOrderItem> _openOrders = [];
  Timer? _openOrdersTimer;

  bool get isInitialized => _isInitialized;
  bool get isBuy => _isBuy;
  bool get isLimit => _isLimit;
  bool get isSubmitting => _isSubmitting;
  bool get isLoadingOrders => _isLoadingOrders;
  bool get isLoadingBalances => _isLoadingBalances;
  String? get statusMessage => _statusMessage;
  bool get isSuccess => _isSuccess;
  double get availableUSDT => _availableUSDT;
  double get availableCrypto => _availableCrypto;
  List<OpenOrderItem> get openOrders => _openOrders;
  String get currentExchange => _currentExchange;
  String get currentSymbol => _currentSymbol;

  String get baseAsset {
    final parts = _currentSymbol.replaceAll('-', '/').split('/');
    return parts.isNotEmpty ? parts[0] : 'ETH';
  }

  String get quoteAsset {
    final parts = _currentSymbol.replaceAll('-', '/').split('/');
    return parts.length > 1 ? parts[1] : 'USDT';
  }

  /// Initializes trading data only when symbol/exchange change or on first load.
  void init(String exchange, String symbol, double? marketPrice, {bool force = false}) {
    final bool exchangeChanged = _currentExchange != exchange;
    final bool symbolChanged = _currentSymbol != symbol;
    final bool needsRefresh = !_isInitialized || exchangeChanged || symbolChanged || force;

    _currentExchange = exchange;
    _currentSymbol = symbol;
    _lastMarketPrice = marketPrice;

    if (needsRefresh) {
      _isInitialized = true;
      if (marketPrice != null && marketPrice > 0) {
        if (priceController.text.isEmpty || symbolChanged || double.tryParse(priceController.text) == 0.0) {
          priceController.text = marketPrice.toStringAsFixed(marketPrice < 1.0 ? 4 : 2);
          onPriceChanged(priceController.text);
        }
      }
      loadBalances();
      loadOpenOrders();
      _startOrdersPolling();
    }
  }

  void _startOrdersPolling() {
    _openOrdersTimer?.cancel();
    _openOrdersTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      loadOpenOrders(silent: true);
      loadBalances(silent: true);
    });
  }

  @override
  void dispose() {
    _openOrdersTimer?.cancel();
    priceController.dispose();
    amountController.dispose();
    totalController.dispose();
    super.dispose();
  }

  void setSide(bool isBuy) {
    if (_isBuy == isBuy) return;
    _isBuy = isBuy;
    _statusMessage = null;
    notifyListeners();
  }

  void setOrderType(bool isLimit) {
    if (_isLimit == isLimit) return;
    _isLimit = isLimit;
    _statusMessage = null;
    notifyListeners();
  }

  void preloadFromPrice(double price, {String? side}) {
    _isLimit = true;
    if (side != null) {
      _isBuy = side.toLowerCase() == 'buy';
    }
    priceController.text = price.toStringAsFixed(price < 1.0 ? 4 : 2);
    onPriceChanged(priceController.text);
    notifyListeners();
  }

  void onPriceChanged(String val) {
    final price = double.tryParse(val) ?? 0.0;
    final amt = double.tryParse(amountController.text) ?? 0.0;
    if (price > 0 && amt > 0) {
      totalController.text = (price * amt).toStringAsFixed(2);
    }
    notifyListeners();
  }

  void onAmountChanged(String val) {
    final amt = double.tryParse(val) ?? 0.0;
    final price = double.tryParse(priceController.text) ?? 0.0;
    if (price > 0 && amt > 0) {
      totalController.text = (price * amt).toStringAsFixed(2);
    }
    notifyListeners();
  }

  void onTotalChanged(String val) {
    final total = double.tryParse(val) ?? 0.0;
    final price = double.tryParse(priceController.text) ?? 0.0;
    if (price > 0 && total >= 0) {
      amountController.text = (total / price).toStringAsFixed(6);
    }
    notifyListeners();
  }

  void setStandardBlockAmount(double usdtAmount) {
    totalController.text = usdtAmount.toStringAsFixed(2);
    onTotalChanged(totalController.text);
  }

  void setPercentage(double pct) {
    final price = double.tryParse(priceController.text) ?? 0.0;
    if (_isBuy) {
      final total = _availableUSDT * pct;
      totalController.text = total.toStringAsFixed(2);
      if (price > 0) {
        amountController.text = (total / price).toStringAsFixed(6);
      }
    } else {
      final amt = _availableCrypto * pct;
      amountController.text = amt.toStringAsFixed(6);
      if (price > 0) {
        totalController.text = (amt * price).toStringAsFixed(2);
      }
    }
    notifyListeners();
  }

  Future<void> loadBalances({bool silent = false}) async {
    if (_isLoadingBalances) return;
    _isLoadingBalances = true;
    if (!silent) notifyListeners();

    try {
      final db = DatabaseHelper.instance;
      final keys = await db.getApiKey(_currentExchange);
      if (keys == null || keys['api_key'] == null || keys['api_key'].toString().isEmpty) {
        _isLoadingBalances = false;
        if (!silent) notifyListeners();
        return;
      }

      final balances = await _exchangeService.fetchBalances(
        exchange: _currentExchange,
        apiKey: keys['api_key'],
        apiSecret: keys['api_secret'],
        apiPassphrase: keys['api_passphrase'],
      );

      final newUSDT = balances['USDT'] ?? 0.0;
      final newCrypto = balances[baseAsset] ?? 0.0;
      if (newUSDT != _availableUSDT || newCrypto != _availableCrypto || !silent) {
        _availableUSDT = newUSDT;
        _availableCrypto = newCrypto;
      }
    } catch (_) {
      // Ignored
    } finally {
      _isLoadingBalances = false;
      notifyListeners();
    }
  }

  Future<void> loadOpenOrders({bool silent = false}) async {
    if (_isLoadingOrders) return;
    _isLoadingOrders = true;
    if (!silent) {
      notifyListeners();
    }

    try {
      final db = DatabaseHelper.instance;
      final keys = await db.getApiKey(_currentExchange);
      if (keys == null || keys['api_key'] == null || keys['api_key'].toString().isEmpty) {
        _openOrders = [];
        return;
      }

      final rawOrders = await _exchangeService.fetchOpenOrders(
        exchange: _currentExchange,
        apiKey: keys['api_key'],
        apiSecret: keys['api_secret'],
        apiPassphrase: keys['api_passphrase'],
        symbol: _currentSymbol,
      );

      _openOrders = rawOrders.map<OpenOrderItem>((o) {
        return OpenOrderItem(
          id: o['id'].toString(),
          symbol: o['symbol'].toString(),
          side: o['side'].toString(),
          type: o['type'].toString(),
          price: (o['price'] as num).toDouble(),
          size: (o['size'] as num).toDouble(),
          dealSize: (o['dealSize'] as num).toDouble(),
          funds: (o['funds'] as num).toDouble(),
          createdAt: DateTime.fromMillisecondsSinceEpoch(o['createdAt'] as int),
        );
      }).toList();
    } catch (_) {
      // Ignored
    } finally {
      _isLoadingOrders = false;
      notifyListeners();
    }
  }

  Future<bool> executeOrder() async {
    _isSubmitting = true;
    _statusMessage = null;
    _isSuccess = false;
    notifyListeners();

    try {
      final db = DatabaseHelper.instance;
      final keys = await db.getApiKey(_currentExchange);
      if (keys == null || keys['api_key'] == null || keys['api_key'].toString().isEmpty) {
        throw Exception('No tienes API Keys configuradas para $_currentExchange.');
      }

      final sideStr = _isBuy ? 'buy' : 'sell';
      final typeStr = _isLimit ? 'limit' : 'market';
      final price = double.tryParse(priceController.text);
      final size = double.tryParse(amountController.text);
      final funds = double.tryParse(totalController.text);

      if (_isLimit) {
        if (price == null || price <= 0) throw Exception('Ingresa un precio válido.');
        if (size == null || size <= 0) throw Exception('Ingresa una cantidad válida.');
      } else {
        if (_isBuy && (funds == null || funds <= 0) && (size == null || size <= 0)) {
          throw Exception('Ingresa el monto a comprar.');
        }
        if (!_isBuy && (size == null || size <= 0)) {
          throw Exception('Ingresa la cantidad a vender.');
        }
      }

      await _exchangeService.placeOrder(
        exchange: _currentExchange,
        apiKey: keys['api_key'],
        apiSecret: keys['api_secret'],
        apiPassphrase: keys['api_passphrase'],
        symbol: _currentSymbol,
        side: sideStr,
        type: typeStr,
        price: price,
        size: size,
        funds: funds,
      );

      _isSuccess = true;
      _statusMessage = '¡Orden ${sideStr.toUpperCase()} ($typeStr) enviada con éxito!';
      
      // Refresh balances and open orders
      await loadBalances();
      await loadOpenOrders();
      return true;
    } catch (e) {
      _isSuccess = false;
      _statusMessage = e.toString().replaceAll('Exception:', '').trim();
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<bool> cancelOrder(String orderId) async {
    try {
      final db = DatabaseHelper.instance;
      final keys = await db.getApiKey(_currentExchange);
      if (keys == null) return false;

      final success = await _exchangeService.cancelOrder(
        exchange: _currentExchange,
        apiKey: keys['api_key'],
        apiSecret: keys['api_secret'],
        apiPassphrase: keys['api_passphrase'],
        orderId: orderId,
        symbol: _currentSymbol,
      );

      if (success) {
        await loadOpenOrders();
        await loadBalances();
      }
      return success;
    } catch (e) {
      _statusMessage = 'Error cancelando orden: $e';
      notifyListeners();
      return false;
    }
  }
}
