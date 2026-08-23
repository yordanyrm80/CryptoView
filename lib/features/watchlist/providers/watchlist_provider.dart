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

  // Fetch prices once
  Future<void> fetchCurrentPrices() async {
    if (_isLoading) return;
    _isLoading = _prices.isEmpty; // Only show loader on initial fetch
    if (_isLoading) notifyListeners();

    try {
      final newPrices = await ExchangeService.instance.fetchPrices(_currentExchange, _symbols);
      _prices.addAll(newPrices);
    } catch (e) {
      print('Error loading prices: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  // Start periodic polling (every 8 seconds)
  void startPricePolling() {
    _pollingTimer?.cancel();
    fetchCurrentPrices();
    _pollingTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      fetchCurrentPrices();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }
}
