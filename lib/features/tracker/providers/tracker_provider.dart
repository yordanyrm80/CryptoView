import 'package:flutter/material.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/utils/exchange_service.dart';
import '../domain/transaction_model.dart';
import '../domain/match_model.dart';

class TrackerProvider extends ChangeNotifier {
  List<TransactionModel> _transactions = [];
  List<MatchModel> _matches = [];
  bool _isLoading = false;

  List<TransactionModel> get transactions => _transactions;
  List<MatchModel> get matches => _matches;
  bool get isLoading => _isLoading;

  // Filtered lists
  List<TransactionModel> get openBuys => _transactions
      .where((tx) => tx.type == 'buy' && !tx.isMatched)
      .toList();

  List<TransactionModel> get openSells => _transactions
      .where((tx) => tx.type == 'sell' && !tx.isMatched)
      .toList();

  // Load transactions and matches
  Future<void> loadData() async {
    _isLoading = true;
    notifyListeners();

    try {
      final txData = await DatabaseHelper.instance.queryAllTransactions();
      _transactions = txData.map((map) => TransactionModel.fromMap(map)).toList();

      final matchData = await DatabaseHelper.instance.queryAllMatches();
      _matches = matchData.map((map) => MatchModel.fromMap(map)).toList();
    } catch (e) {
      print('Error loading tracker data: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  // Add new transaction
  Future<void> addTransaction(TransactionModel transaction) async {
    await DatabaseHelper.instance.insertTransaction(transaction.toMap());
    await loadData();
  }

  // Delete a transaction
  Future<void> deleteTransaction(int id) async {
    await DatabaseHelper.instance.deleteTransaction(id);
    await loadData();
  }

  // Calculate remaining available amount for a transaction dynamically
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

  // Core Matching logic ("Casar compras y ventas")
  Future<bool> matchTransactions({
    required TransactionModel buy,
    required TransactionModel sell,
    required double amountToMatch,
  }) async {
    if (buy.id == null || sell.id == null) return false;

    final remainingBuy = getRemainingAmount(buy);
    final remainingSell = getRemainingAmount(sell);

    if (amountToMatch > remainingBuy || amountToMatch > remainingSell) {
      return false; // Cannot match more than available
    }

    // Calculate proportional fees
    final buyFeeShare = (amountToMatch / buy.amount) * buy.fee;
    final sellFeeShare = (amountToMatch / sell.amount) * sell.fee;
    
    // Profit = (sellPrice - buyPrice) * amount - fees
    final grossProfit = (sell.price - buy.price) * amountToMatch;
    final netProfit = grossProfit - buyFeeShare - sellFeeShare;

    // Create the match
    final match = MatchModel(
      buyTransactionId: buy.id!,
      sellTransactionId: sell.id!,
      matchedAmount: amountToMatch,
      profit: netProfit,
      date: DateTime.now(),
    );

    await DatabaseHelper.instance.insertMatch(match.toMap());

    // Update is_matched status if fully consumed
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

  // Delete a match and revert transaction statuses
  Future<void> deleteMatch(MatchModel match) async {
    if (match.id == null) return;

    await DatabaseHelper.instance.deleteMatch(match.id!);

    // Fetch original transactions and restore isMatched to false since volume is freed up
    final db = await DatabaseHelper.instance.database;
    
    await db.update(
      'transactions',
      {'is_matched': 0},
      where: 'id IN (?, ?)',
      whereArgs: [match.buyTransactionId, match.sellTransactionId],
    );

    await loadData();
  }

  // Helper calculation metrics
  double get totalProfit {
    return _matches.fold(0.0, (sum, match) => sum + match.profit);
  }

  double get winRate {
    if (_matches.isEmpty) return 0.0;
    final winningTrades = _matches.where((m) => m.profit > 0).length;
    return (winningTrades / _matches.length) * 100;
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
  }

  Future<void> deleteCredentials(String exchange) async {
    await DatabaseHelper.instance.deleteApiKey(exchange);
  }

  // --- API Sync Date Operations ---

  Future<DateTime?> getLastSyncDateForSymbol(String exchange, String symbol) async {
    return await DatabaseHelper.instance.getLastSyncDate(exchange, symbol);
  }

  // --- Import transactions from Exchange ---

  Future<int> importTransactionsForSymbol(String exchange, String symbol) async {
    final credentials = await getCredentials(exchange);
    if (credentials == null) {
      throw Exception('No se encontraron credenciales de API para $exchange guardadas.');
    }

    final apiKey = credentials['api_key'] as String;
    final apiSecret = credentials['api_secret'] as String;
    final apiPassphrase = credentials['api_passphrase'] as String? ?? '';

    // Determine start sync date (clamp to max 90 days ago)
    final now = DateTime.now();
    final ninetyDaysAgo = now.subtract(const Duration(days: 90));
    DateTime? lastSync = await DatabaseHelper.instance.getLastSyncDate(exchange, symbol);

    if (lastSync == null || lastSync.isBefore(ninetyDaysAgo)) {
      lastSync = ninetyDaysAgo;
    }

    List<Map<String, dynamic>> fills = [];

    if (exchange.toLowerCase() == 'kucoin') {
      fills = await ExchangeService.instance.fetchKucoinFills(
        symbol: symbol,
        apiKey: apiKey,
        apiSecret: apiSecret,
        apiPassphrase: apiPassphrase,
        startAt: lastSync,
      );
    } else if (exchange.toLowerCase() == 'binance') {
      fills = await ExchangeService.instance.fetchBinanceFills(
        symbol: symbol,
        apiKey: apiKey,
        apiSecret: apiSecret,
        startAt: lastSync,
      );
    } else if (exchange.toLowerCase() == 'bingx') {
      fills = await ExchangeService.instance.fetchBingXFills(
        symbol: symbol,
        apiKey: apiKey,
        apiSecret: apiSecret,
        startAt: lastSync,
      );
    } else {
      throw Exception('Exchange $exchange no soportado.');
    }

    if (fills.isEmpty) {
      // Even if no transactions, update sync date to avoid querying 90 days next time
      await DatabaseHelper.instance.updateLastSyncDate(exchange, symbol, now);
      return 0;
    }

    // Query existing transactions for exchange and symbol to check for duplicates
    final db = await DatabaseHelper.instance.database;
    final existingTxData = await db.query(
      'transactions',
      where: 'exchange = ? AND symbol = ?',
      whereArgs: [exchange, symbol],
    );

    // Create a set of unique transaction keys: symbol_type_price_amount_fee_date
    final existingKeys = existingTxData.map((row) {
      final type = row['type'] as String;
      final price = (row['price'] as num).toDouble();
      final amount = (row['amount'] as num).toDouble();
      final fee = (row['fee'] as num).toDouble();
      final dateStr = row['date'] as String;
      
      // Parse to ensure consistent format (ISO8601)
      final parsedDate = DateTime.parse(dateStr).toIso8601String();
      return '${symbol}_${type}_${price}_${amount}_${fee}_$parsedDate';
    }).toSet();

    int importedCount = 0;

    for (var fill in fills) {
      final type = fill['side'] == 'buy' ? 'buy' : 'sell';
      final price = fill['price'] as double;
      final amount = fill['amount'] as double;
      final fee = fill['fee'] as double;
      final createdAtMs = fill['createdAt'] as int;
      final date = DateTime.fromMillisecondsSinceEpoch(createdAtMs);
      
      final key = '${symbol}_${type}_${price}_${amount}_${fee}_${date.toIso8601String()}';

      if (!existingKeys.contains(key)) {
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
        importedCount++;
      }
    }

    // Update sync date to current time
    await DatabaseHelper.instance.updateLastSyncDate(exchange, symbol, now);

    // Refresh memory
    await loadData();

    return importedCount;
  }
}
