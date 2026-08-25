import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/services/exchanges/exchange_service.dart';

class WatchlistProvider extends ChangeNotifier {
  String _currentExchange = 'KuCoin';
  String _selectedSymbol = 'ETH/USDT';
  List<String> _symbols = ['BTC/USDT', 'ETH/USDT', 'SOL/USDT', 'XRP/USDT', 'ADA/USDT'];
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
    _initWatchlist();
  }

  Future<void> _initWatchlist() async {
    await _loadWatchlistState();
    startPricePolling();
  }

  Future<void> _loadWatchlistState() async {
    try {
      final db = DatabaseHelper.instance;

      // 1. Load Watchlist Symbols
      final savedSymbolsJson = await db.getGeneralSetting('watchlist_symbols');
      if (savedSymbolsJson != null && savedSymbolsJson.isNotEmpty) {
        try {
          final List<dynamic> decoded = jsonDecode(savedSymbolsJson);
          if (decoded.isNotEmpty) {
            _symbols = decoded.map((e) => e.toString()).toList();
          }
        } catch (_) {}
      } else {
        // Save initial default symbols
        await db.setGeneralSetting('watchlist_symbols', jsonEncode(_symbols));
      }

      // 2. Load Selected Exchange
      final savedExchange = await db.getGeneralSetting('selected_exchange');
      if (savedExchange != null && savedExchange.isNotEmpty) {
        _currentExchange = savedExchange;
      }

      // 3. Load Selected Symbol
      final savedSymbol = await db.getGeneralSetting('selected_symbol');
      if (savedSymbol != null && savedSymbol.isNotEmpty && _symbols.contains(savedSymbol)) {
        _selectedSymbol = savedSymbol;
      } else if (_symbols.isNotEmpty && !_symbols.contains(_selectedSymbol)) {
        _selectedSymbol = _symbols.first;
      }

      // 4. Load Favorites
      final savedFavs = await db.queryFavorites();
      if (savedFavs.isNotEmpty) {
        _favoriteSymbols.clear();
        _favoriteSymbols.addAll(savedFavs);
      } else {
        for (var s in ['BTC/USDT', 'ETH/USDT']) {
          await db.addFavorite(s);
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading watchlist state: $e');
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
    DatabaseHelper.instance.setGeneralSetting('selected_exchange', newExchange);
    fetchCurrentPrices();
  }

  // Select a coin/pair to show on the chart
  void changeSymbol(String newSymbol) {
    if (_selectedSymbol == newSymbol) return;
    _selectedSymbol = newSymbol;
    notifyListeners();
    DatabaseHelper.instance.setGeneralSetting('selected_symbol', newSymbol);
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
      DatabaseHelper.instance.setGeneralSetting('watchlist_symbols', jsonEncode(_symbols));
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
        DatabaseHelper.instance.setGeneralSetting('selected_symbol', _selectedSymbol);
      }
      
      notifyListeners();
      DatabaseHelper.instance.setGeneralSetting('watchlist_symbols', jsonEncode(_symbols));
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
