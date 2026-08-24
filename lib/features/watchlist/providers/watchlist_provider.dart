import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/services/exchanges/exchange_service.dart';

class WatchlistProvider extends ChangeNotifier {
  String _currentExchange = 'KuCoin';
  String _selectedSymbol = 'ETH/USDT';
  final List<String> _symbols = ['BTC/USDT', 'ETH/USDT', 'SOL/USDT', 'XRP/USDT', 'ADA/USDT'];
  final Set<String> _favoriteSymbols = {'BTC/USDT', 'ETH/USDT'};
  final Map<String, double> _prices = {};
  bool _isLoading = false;
  Timer? _pollingTimer;

  String get currentExchange => _currentExchange;
  String get selectedSymbol => _selectedSymbol;
  List<String> get symbols => _symbols;
  Set<String> get favoriteSymbolsSet => _favoriteSymbols;
  List<String> get favoriteSymbols => _symbols.where((s) => _favoriteSymbols.contains(s)).toList();
  Map<String, double> get prices => _prices;
  bool get isLoading => _isLoading;

  WatchlistProvider() {
    _loadFavorites();
    startPricePolling();
  }

  Future<void> _loadFavorites() async {
    try {
      final saved = await DatabaseHelper.instance.queryFavorites();
      if (saved.isNotEmpty) {
        _favoriteSymbols.clear();
        _favoriteSymbols.addAll(saved);
        notifyListeners();
      } else {
        // Seed default favorites
        for (var s in ['BTC/USDT', 'ETH/USDT']) {
          await DatabaseHelper.instance.addFavorite(s);
        }
      }
    } catch (e) {
      // Ignored
    }
  }

  bool isFavorite(String symbol) => _favoriteSymbols.contains(symbol);

  Future<void> toggleFavorite(String symbol) async {
    if (_favoriteSymbols.contains(symbol)) {
      _favoriteSymbols.remove(symbol);
      await DatabaseHelper.instance.removeFavorite(symbol);
    } else {
      _favoriteSymbols.add(symbol);
      await DatabaseHelper.instance.addFavorite(symbol);
    }
    notifyListeners();
  }

  // Set the current active exchange
  void changeExchange(String newExchange) {
    if (_currentExchange == newExchange) return;
    _currentExchange = newExchange;
    _prices.clear(); // Reset cached prices for the new exchange
    notifyListeners();
    fetchCurrentPrices();
  }

  // Select a coin/pair to show on the chart
  void changeSymbol(String newSymbol) {
    if (_selectedSymbol == newSymbol) return;
    _selectedSymbol = newSymbol;
    notifyListeners();
  }

  // Add pair to watchlist
  void addSymbol(String symbol) {
    final cleanSymbol = symbol.trim().toUpperCase().replaceAll(' ', '');
    if (cleanSymbol.isEmpty) return;
    
    // Auto format symbol (ensure slash)
    String formatted = cleanSymbol;
    if (!formatted.contains('/') && formatted.endsWith('USDT')) {
      formatted = formatted.replaceFirst('USDT', '/USDT');
    }

    if (!_symbols.contains(formatted)) {
      _symbols.add(formatted);
      notifyListeners();
      fetchCurrentPrices();
    }
  }

  // Remove pair from watchlist
  void removeSymbol(String symbol) {
    if (_symbols.contains(symbol)) {
      _symbols.remove(symbol);
      _prices.remove(symbol);
      
      // If we deleted the currently selected symbol, select another one
      if (_selectedSymbol == symbol && _symbols.isNotEmpty) {
        _selectedSymbol = _symbols.first;
      }
      
      notifyListeners();
    }
  }

  bool _isFetchingPrices = false;

  // Fetch prices once
  Future<void> fetchCurrentPrices() async {
    if (_isFetchingPrices) return;
    _isFetchingPrices = true;

    final bool isInitial = _prices.isEmpty;
    if (isInitial) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      final newPrices = await ExchangeService.instance.fetchPrices(_currentExchange, _symbols);
      bool changed = false;
      for (var entry in newPrices.entries) {
        if (_prices[entry.key] != entry.value) {
          _prices[entry.key] = entry.value;
          changed = true;
        }
      }
      if (changed || isInitial) {
        notifyListeners();
      }
    } catch (e) {
      print('Error loading prices: $e');
    } finally {
      _isFetchingPrices = false;
      if (isInitial) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  // Start periodic polling (every 10 seconds)
  void startPricePolling() {
    _pollingTimer?.cancel();
    fetchCurrentPrices();
    _pollingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      fetchCurrentPrices();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }
}
