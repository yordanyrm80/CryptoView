import 'binance_service.dart';
import 'kucoin_service.dart';
import 'bingx_service.dart';

/// Unified façade for all cryptocurrency exchanges supported by CryptoView
class ExchangeService {
  static final ExchangeService instance = ExchangeService._init();
  ExchangeService._init();

  final BinanceService _binance = BinanceService.instance;
  final KucoinService _kucoin = KucoinService.instance;
  final BingxService _bingx = BingxService.instance;

  /// Fetch K-lines / candlesticks from specified exchange
  Future<List<Map<String, dynamic>>> fetchKlines(String exchange, String symbol, String interval, {int limit = 150}) async {
    final ex = exchange.toLowerCase();
    if (ex == 'binance') {
      return await _binance.fetchKlines(symbol, interval, limit: limit);
    } else if (ex == 'kucoin') {
      return await _kucoin.fetchCandles(symbol, interval);
    } else if (ex == 'bingx') {
      return await _bingx.fetchKlines(symbol, interval, limit: limit);
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> fetchBinanceKlines(String symbol, String interval, {int limit = 150}) =>
      _binance.fetchKlines(symbol, interval, limit: limit);

  Future<List<Map<String, dynamic>>> fetchKucoinKlines(String symbol, String interval) =>
      _kucoin.fetchCandles(symbol, interval);

  Future<List<Map<String, dynamic>>> fetchBingXKlines(String symbol, String interval, {int limit = 150}) =>
      _bingx.fetchKlines(symbol, interval, limit: limit);

  /// Fetch current prices for a list of symbols from specified exchange
  Future<Map<String, double>> fetchPrices(String exchange, List<String> symbols) async {
    final ex = exchange.toLowerCase();
    if (ex == 'binance') {
      return await _binance.fetchPrices(symbols);
    } else if (ex == 'kucoin') {
      return await _kucoin.fetchPrices(symbols);
    } else if (ex == 'bingx') {
      return await _bingx.fetchPrices(symbols);
    }
    return {for (var s in symbols) s: 0.0};
  }

  /// Fetch private balances for specified exchange
  Future<Map<String, double>> fetchBalances({
    required String exchange,
    required String apiKey,
    required String apiSecret,
    String? apiPassphrase,
  }) async {
    final ex = exchange.toLowerCase();
    if (ex == 'kucoin') {
      return await _kucoin.fetchBalances(
        apiKey: apiKey,
        apiSecret: apiSecret,
        apiPassphrase: apiPassphrase ?? '',
      );
    } else if (ex == 'binance') {
      return await _binance.fetchBalances(
        apiKey: apiKey,
        apiSecret: apiSecret,
      );
    } else if (ex == 'bingx') {
      return await _bingx.fetchBalances(
        apiKey: apiKey,
        apiSecret: apiSecret,
      );
    }
    return {};
  }

  /// Fetch private fills from KuCoin
  Future<List<Map<String, dynamic>>> fetchKucoinFills({
    required String symbol,
    required String apiKey,
    required String apiSecret,
    required String apiPassphrase,
    required DateTime startAt,
  }) => _kucoin.fetchFills(
    symbol: symbol,
    apiKey: apiKey,
    apiSecret: apiSecret,
    apiPassphrase: apiPassphrase,
    startAt: startAt,
  );

  /// Fetch private fills from Binance
  Future<List<Map<String, dynamic>>> fetchBinanceFills({
    required String symbol,
    required String apiKey,
    required String apiSecret,
    required DateTime startAt,
  }) => _binance.fetchFills(
    symbol: symbol,
    apiKey: apiKey,
    apiSecret: apiSecret,
    startAt: startAt,
  );

  /// Fetch private fills from BingX
  Future<List<Map<String, dynamic>>> fetchBingXFills({
    required String symbol,
    required String apiKey,
    required String apiSecret,
    required DateTime startAt,
  }) => _bingx.fetchFills(
    symbol: symbol,
    apiKey: apiKey,
    apiSecret: apiSecret,
    startAt: startAt,
  );
}
