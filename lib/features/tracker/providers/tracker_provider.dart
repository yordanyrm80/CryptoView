import 'package:flutter/material.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/services/exchanges/exchange_service.dart';
import '../domain/transaction_model.dart';
import '../domain/match_model.dart';

class TrackerProvider extends ChangeNotifier {
  List<TransactionModel> _transactions = [];
  List<MatchModel> _matches = [];
  Map<String, double> _exchangeBalances = {};
  Map<String, double> _defaultBuyAmounts = {'KuCoin': 400.0, 'Binance': 400.0, 'Bybit': 400.0};
  bool _isLoading = false;
  bool _isFetchingBalance = false;

  double getBuyAmountForExchange(String exchange) {
    for (var k in _defaultBuyAmounts.keys) {
      if (k.toLowerCase() == exchange.toLowerCase()) {
        return _defaultBuyAmounts[k]!;
      }
    }
    return 400.0;
  }

  // Import progress state
  bool _isImporting = false;
  double _importProgress = 0.0;
  String _importStatusMessage = '';
  int _importFoundCount = 0;

  // Filter state
  bool _filterOnlyCurrentSymbol = true;
  String _activeSymbol = 'ETH/USDT';
  String _activeExchange = 'KuCoin';

  List<TransactionModel> get transactions => _transactions;
  List<MatchModel> get matches => _matches;
  Map<String, double> get exchangeBalances => _exchangeBalances;
  bool get isLoading => _isLoading;
  bool get isFetchingBalance => _isFetchingBalance;
  bool get isImporting => _isImporting;
  double get importProgress => _importProgress;
  String get importStatusMessage => _importStatusMessage;
  int get importFoundCount => _importFoundCount;
  bool get filterOnlyCurrentSymbol => _filterOnlyCurrentSymbol;
  String get activeSymbol => _activeSymbol;
  String get activeExchange => _activeExchange;

  int get totalMatchesCount => _matches.length;
  double get totalNetProfit => _matches.fold(0.0, (sum, m) => sum + m.profit);

  /// Helper to extract base and quote assets (e.g. 'ETH/USDT' -> base: 'ETH', quote: 'USDT')
  String get currentQuoteAsset {
    final parts = _activeSymbol.split('/');
    if (parts.length > 1) return parts[1].toUpperCase();
    if (_activeSymbol.contains('-')) return _activeSymbol.split('-')[1].toUpperCase();
    if (_activeSymbol.toUpperCase().endsWith('USDT')) return 'USDT';
    if (_activeSymbol.toUpperCase().endsWith('USDC')) return 'USDC';
    return 'USDT';
  }

  String get currentBaseAsset {
    final parts = _activeSymbol.split('/');
    if (parts.isNotEmpty) return parts[0].toUpperCase();
    if (_activeSymbol.contains('-')) return _activeSymbol.split('-')[0].toUpperCase();
    return _activeSymbol.toUpperCase();
  }

  /// Update active analysis context from Watchlist/Chart
  void updateActiveContext(String symbol, String exchange) {
    bool changed = false;
    if (_activeSymbol != symbol) {
      _activeSymbol = symbol;
      changed = true;
    }
    if (_activeExchange != exchange) {
      _activeExchange = exchange;
      changed = true;
    }
    if (changed) {
      fetchLiveBalance(exchange);
      notifyListeners();
    }
  }

  /// Toggle filtering between only active symbol and all symbols
  void setFilterOnlyCurrentSymbol(bool value) {
    _filterOnlyCurrentSymbol = value;
    notifyListeners();
  }

  // --- Filtered Getters based on Active Symbol / All ---

  bool _matchesSymbol(String? itemSymbol) {
    if (!_filterOnlyCurrentSymbol) return true;
    if (itemSymbol == null) return false;
    final cleanItem = itemSymbol.replaceAll('-', '/').toUpperCase();
    final cleanActive = _activeSymbol.replaceAll('-', '/').toUpperCase();
    return cleanItem == cleanActive;
  }

  List<TransactionModel> get filteredTransactions =>
      _transactions.where((tx) => _matchesSymbol(tx.symbol)).toList();

  List<MatchModel> get filteredMatches =>
      _matches.where((m) => _matchesSymbol(m.symbol)).toList();

  List<TransactionModel> get filteredOpenBuys =>
      _transactions.where((tx) => tx.type == 'buy' && !tx.isMatched && _matchesSymbol(tx.symbol)).toList();

  List<TransactionModel> get filteredOpenSells =>
      _transactions.where((tx) => tx.type == 'sell' && !tx.isMatched && _matchesSymbol(tx.symbol)).toList();

  // Legacy unfiltered getters
  List<TransactionModel> get openBuys =>
      _transactions.where((tx) => tx.type == 'buy' && !tx.isMatched).toList();

  List<TransactionModel> get openSells =>
      _transactions.where((tx) => tx.type == 'sell' && !tx.isMatched).toList();

  // --- Metrics Calculations ---

  double get filteredTotalProfit {
    return filteredMatches.fold(0.0, (sum, match) => sum + match.profit);
  }

  double get filteredWinRate {
    final list = filteredMatches;
    if (list.isEmpty) return 0.0;
    final winningTrades = list.where((m) => m.profit > 0).length;
    return (winningTrades / list.length) * 100;
  }

  double get totalProfit {
    return _matches.fold(0.0, (sum, match) => sum + match.profit);
  }

  double get winRate {
    if (_matches.isEmpty) return 0.0;
    final winningTrades = _matches.where((m) => m.profit > 0).length;
    return (winningTrades / _matches.length) * 100;
  }

  /// Capital currently invested in open buy orders (in quote currency / USDT)
  double get capitalInOpenBuys {
    return filteredOpenBuys.fold(0.0, (sum, tx) {
      final remaining = getRemainingAmount(tx);
      return sum + (tx.price * remaining);
    });
  }

  /// Total capital volume operated in quote currency (USDT)
  double get totalVolumeOperated {
    return filteredTransactions.fold(0.0, (sum, tx) => sum + (tx.price * tx.amount));
  }

  /// Available balance in quote currency (e.g. USDT) from Exchange API
  double get quoteAssetBalance {
    final quote = currentQuoteAsset;
    return _exchangeBalances[quote] ?? _exchangeBalances['USD'] ?? 0.0;
  }

  // --- Data Loading & Operations ---

  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();

    try {
      final txData = await DatabaseHelper.instance.queryAllTransactions();
      _transactions = txData.map((map) => TransactionModel.fromMap(map)).toList();

      final matchData = await DatabaseHelper.instance.queryAllMatches();
      _matches = matchData.map((map) => MatchModel.fromMap(map)).toList();

      final exchanges = ['KuCoin', 'Binance', 'Bybit', 'OKX', 'Gate.io', 'MEXC', 'Coinbase'];
      for (var ex in exchanges) {
        _defaultBuyAmounts[ex] = await DatabaseHelper.instance.getDefaultBuyAmount(ex);
      }

      // Attempt to load balance
      await fetchLiveBalance(_activeExchange);
    } catch (e) {
      // Ignored
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> fetchLiveBalance(String exchange) async {
    final credentials = await getCredentials(exchange);
    if (credentials == null) return;

    final apiKey = credentials['api_key'] as String? ?? '';
    final apiSecret = credentials['api_secret'] as String? ?? '';
    final apiPassphrase = credentials['api_passphrase'] as String? ?? '';

    if (apiKey.isEmpty || apiSecret.isEmpty) return;

    _isFetchingBalance = true;
    notifyListeners();

    try {
      final balances = await ExchangeService.instance.fetchBalances(
        exchange: exchange,
        apiKey: apiKey,
        apiSecret: apiSecret,
        apiPassphrase: apiPassphrase,
      );
      _exchangeBalances = balances;
    } catch (e) {
      // Ignored
    }

    _isFetchingBalance = false;
    notifyListeners();
  }

  Future<void> addTransaction(TransactionModel transaction) async {
    await DatabaseHelper.instance.insertTransaction(transaction.toMap());
    await loadData();
  }

  Future<void> deleteTransaction(int id) async {
    await DatabaseHelper.instance.deleteTransaction(id);
    await loadData();
  }

  double getRemainingAmount(TransactionModel tx) {
    if (tx.id == null) return tx.amount;

    double matchedSum = 0.0;
    for (var match in _matches) {
      if (tx.type == 'buy' && match.buyTransactionId == tx.id) {
        matchedSum += match.matchedAmount;
      } else if (tx.type == 'sell' && match.sellTransactionId == tx.id) {
        matchedSum += match.matchedAmount;
      }
    }

    final remaining = tx.amount - matchedSum;
    return remaining > 0.000001 ? remaining : 0.0;
  }

  Future<bool> matchTransactions({
    required TransactionModel buy,
    required TransactionModel sell,
    required double amountToMatch,
  }) async {
    if (buy.id == null || sell.id == null) return false;

    final remainingBuy = getRemainingAmount(buy);
    final remainingSell = getRemainingAmount(sell);

    if (amountToMatch > remainingBuy || amountToMatch > remainingSell) {
      return false;
    }

    final buyFeeShare = (amountToMatch / buy.amount) * buy.fee;
    final sellFeeShare = (amountToMatch / sell.amount) * sell.fee;
    
    final grossProfit = (sell.price - buy.price) * amountToMatch;
    final netProfit = grossProfit - buyFeeShare - sellFeeShare;

    final match = MatchModel(
      buyTransactionId: buy.id!,
      sellTransactionId: sell.id!,
      matchedAmount: amountToMatch,
      profit: netProfit,
      date: DateTime.now(),
    );

    await DatabaseHelper.instance.insertMatch(match.toMap());

    final newRemainingBuy = remainingBuy - amountToMatch;
    final newRemainingSell = remainingSell - amountToMatch;

    if (newRemainingBuy < 0.00001) {
      await DatabaseHelper.instance.updateTransaction(
        buy.copyWith(isMatched: true).toMap(),
      );
    }
    if (newRemainingSell < 0.00001) {
      await DatabaseHelper.instance.updateTransaction(
        sell.copyWith(isMatched: true).toMap(),
      );
    }

    await loadData();
    return true;
  }

  Future<void> deleteMatch(MatchModel match) async {
    if (match.id == null) return;

    await DatabaseHelper.instance.deleteMatch(match.id!);

    final db = await DatabaseHelper.instance.database;
    await db.update(
      'transactions',
      {'is_matched': 0},
      where: 'id IN (?, ?)',
      whereArgs: [match.buyTransactionId, match.sellTransactionId],
    );

    await loadData();
  }

  /// Manually dismiss / close dust residual for a transaction (marks as fully matched/closed)
  Future<void> dismissDust(TransactionModel tx) async {
    if (tx.id == null) return;
    await DatabaseHelper.instance.updateTransaction(
      tx.copyWith(isMatched: true).toMap(),
    );
    await loadData();
  }

  // --- API Credentials Operations ---

  Future<Map<String, dynamic>?> getCredentials(String exchange) async {
    return await DatabaseHelper.instance.queryApiKey(exchange);
  }

  Future<void> saveCredentials(String exchange, String key, String secret, {String? passphrase}) async {
    await DatabaseHelper.instance.insertApiKey({
      'exchange': exchange,
      'api_key': key,
      'api_secret': secret,
      'api_passphrase': passphrase ?? '',
    });
    await fetchLiveBalance(exchange);
  }

  Future<void> deleteCredentials(String exchange) async {
    await DatabaseHelper.instance.deleteApiKey(exchange);
    _exchangeBalances.clear();
    notifyListeners();
  }

  Future<DateTime?> getLastSyncDateForSymbol(String exchange, String symbol) async {
    return await DatabaseHelper.instance.getLastSyncDate(exchange, symbol);
  }

  // --- Import transactions from Exchange ---

  // --- Default Buy Amount Settings ---

  Future<double> getDefaultBuyAmount(String exchange) async {
    return await DatabaseHelper.instance.getDefaultBuyAmount(exchange);
  }

  Future<void> setDefaultBuyAmount(String exchange, double amount) async {
    _defaultBuyAmounts[exchange] = amount;
    await DatabaseHelper.instance.setDefaultBuyAmount(exchange, amount);
    notifyListeners();
  }

  // --- Import transactions from Exchange ---

  Future<int> importTransactionsForSymbol(
    String exchange,
    String symbol, {
    int lookbackDays = 730,
    bool updateProviderState = true,
  }) async {
    final credentials = await getCredentials(exchange);
    if (credentials == null) {
      throw Exception('No se encontraron credenciales de API para $exchange guardadas.');
    }

    final apiKey = credentials['api_key'] as String;
    final apiSecret = credentials['api_secret'] as String;
    final apiPassphrase = credentials['api_passphrase'] as String? ?? '';

    final now = DateTime.now();
    final lookbackDate = now.subtract(Duration(days: lookbackDays));

    if (updateProviderState) {
      _isImporting = true;
      _importProgress = 0.0;
      _importStatusMessage = 'Iniciando consulta histórica en $exchange...';
      _importFoundCount = 0;
      notifyListeners();
    }

    try {
      List<Map<String, dynamic>> fills = [];

      void handleProgress(double progress, String statusMessage, int foundCount) {
        if (updateProviderState) {
          _importProgress = progress;
          _importStatusMessage = statusMessage;
          _importFoundCount = foundCount;
          notifyListeners();
        }
      }

      if (exchange.toLowerCase() == 'kucoin') {
        fills = await ExchangeService.instance.fetchKucoinFills(
          symbol: symbol,
          apiKey: apiKey,
          apiSecret: apiSecret,
          apiPassphrase: apiPassphrase,
          startAt: lookbackDate,
          onProgress: handleProgress,
        );
      } else if (exchange.toLowerCase() == 'binance') {
        fills = await ExchangeService.instance.fetchBinanceFills(
          symbol: symbol,
          apiKey: apiKey,
          apiSecret: apiSecret,
          startAt: lookbackDate,
          onProgress: handleProgress,
        );
      } else if (exchange.toLowerCase() == 'bingx') {
        fills = await ExchangeService.instance.fetchBingXFills(
          symbol: symbol,
          apiKey: apiKey,
          apiSecret: apiSecret,
          startAt: lookbackDate,
          onProgress: handleProgress,
        );
      } else {
        throw Exception('Exchange $exchange no soportado.');
      }

      if (updateProviderState) {
        _importStatusMessage = 'Procesando ${fills.length} operaciones encontradas en $symbol...';
        _importProgress = 0.95;
        notifyListeners();
      }

      if (fills.isEmpty) {
        await DatabaseHelper.instance.updateLastSyncDate(exchange, symbol, now);
        return 0;
      }

      final db = await DatabaseHelper.instance.database;
      final existingTxData = await db.query(
        'transactions',
        where: 'exchange = ? AND symbol = ?',
        whereArgs: [exchange, symbol],
      );

      final existingTxList = existingTxData.map((row) {
        return {
          'type': row['type'] as String,
          'price': (row['price'] as num).toDouble(),
          'amount': (row['amount'] as num).toDouble(),
          'date': DateTime.parse(row['date'] as String).toUtc(),
        };
      }).toList();

      int importedCount = 0;

      for (var fill in fills) {
        final type = fill['side'] == 'buy' ? 'buy' : 'sell';
        final price = fill['price'] as double;
        final amount = fill['amount'] as double;
        final fee = fill['fee'] as double;
        final createdAtMs = fill['createdAt'] as int;
        final date = DateTime.fromMillisecondsSinceEpoch(createdAtMs, isUtc: true);

        final alreadyExists = existingTxList.any((tx) {
          if (tx['type'] != type) return false;
          final priceDiff = ((tx['price'] as double) - price).abs();
          if (priceDiff > 0.001) return false;
          final amountDiff = ((tx['amount'] as double) - amount).abs();
          if (amountDiff > 0.0001) return false;
          final txDate = (tx['date'] as DateTime).toUtc();
          return txDate.difference(date).inSeconds.abs() <= 60;
        });

        if (!alreadyExists) {
          final tx = TransactionModel(
            exchange: exchange,
            symbol: symbol,
            type: type,
            price: price,
            amount: amount,
            fee: fee,
            date: date,
          );

          await DatabaseHelper.instance.insertTransaction(tx.toMap());
          existingTxList.add({
            'type': type,
            'price': price,
            'amount': amount,
            'date': date,
          });
          importedCount++;
        }
      }

      await DatabaseHelper.instance.updateLastSyncDate(exchange, symbol, now);
      return importedCount;
    } finally {
      if (updateProviderState) {
        await loadData();
        await fetchLiveBalance(exchange);
        _isImporting = false;
        _importProgress = 1.0;
        notifyListeners();
      }
    }
  }

  /// Batch import for a list of favorite symbols
  Future<int> importBatchTransactions({
    required String exchange,
    required List<String> symbols,
    required int lookbackDays,
  }) async {
    if (symbols.isEmpty) {
      throw Exception('No hay monedas favoritas seleccionadas para sincronizar.');
    }

    _isImporting = true;
    _importProgress = 0.0;
    _importStatusMessage = 'Iniciando sincronización masiva de ${symbols.length} favoritas...';
    _importFoundCount = 0;
    notifyListeners();

    int totalImported = 0;

    try {
      for (int i = 0; i < symbols.length; i++) {
        final symbol = symbols[i];
        final symbolIndex = i + 1;
        
        _importStatusMessage = '[$symbolIndex/${symbols.length}] Sincronizando $symbol en $exchange...';
        _importProgress = (i / symbols.length).clamp(0.0, 1.0);
        notifyListeners();

        try {
          final count = await importTransactionsForSymbol(
            exchange,
            symbol,
            lookbackDays: lookbackDays,
            updateProviderState: false,
          );
          totalImported += count;
          _importFoundCount += count;
        } catch (e) {
          // Log and continue to next symbol
          print('Error sincronizando $symbol: $e');
        }

        _importProgress = ((i + 1) / symbols.length).clamp(0.0, 1.0);
        notifyListeners();
      }

      await loadData();
      await fetchLiveBalance(exchange);
      return totalImported;
    } finally {
      _isImporting = false;
      _importProgress = 1.0;
      _importStatusMessage = 'Sincronización masiva completada: $totalImported operaciones nuevas.';
      notifyListeners();
    }
  }
}
