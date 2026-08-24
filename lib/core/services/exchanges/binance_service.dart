import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class BinanceService {
  static final BinanceService instance = BinanceService._init();
  BinanceService._init();

  /// Fetch K-line (candlestick) history from Binance
  Future<List<Map<String, dynamic>>> fetchKlines(String symbol, String interval, {int limit = 150}) async {
    final formattedSymbol = symbol.replaceAll('-', '').replaceAll('/', '').toUpperCase();
    final url = Uri.parse('https://api.binance.com/api/v3/klines?symbol=$formattedSymbol&interval=$interval&limit=$limit');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map<Map<String, dynamic>>((item) {
          return {
            'time': (item[0] as int) ~/ 1000,
            'open': double.parse(item[1].toString()),
            'high': double.parse(item[2].toString()),
            'low': double.parse(item[3].toString()),
            'close': double.parse(item[4].toString()),
          };
        }).toList();
      } else {
        throw Exception('Failed to load Binance candles: ${response.statusCode}');
      }
    } catch (e) {
      return [];
    }
  }

  /// Fetch ticker prices for given symbols from Binance
  Future<Map<String, double>> fetchPrices(List<String> symbols) async {
    final Map<String, double> priceMap = {for (var s in symbols) s: 0.0};
    try {
      final url = Uri.parse('https://api.binance.com/api/v3/ticker/price');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        for (var item in data) {
          final sym = item['symbol'].toString();
          for (var target in symbols) {
            final formattedTarget = target.replaceAll('-', '').replaceAll('/', '').toUpperCase();
            if (sym == formattedTarget) {
              priceMap[target] = double.parse(item['price'].toString());
            }
          }
        }
      }
    } catch (e) {
      // Ignored
    }
    return priceMap;
  }

  /// Fetch private balances from Binance
  Future<Map<String, double>> fetchBalances({
    required String apiKey,
    required String apiSecret,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final queryParams = 'recvWindow=5000&timestamp=$timestamp';
    final key = utf8.encode(apiSecret);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(utf8.encode(queryParams));
    final signature = digest.toString();
    final url = Uri.parse('https://api.binance.com/api/v3/account?$queryParams&signature=$signature');

    try {
      final response = await http.get(
        url,
        headers: {
          'X-MBX-APIKEY': apiKey,
          'Content-Type': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final List<dynamic>? balancesList = data['balances'];
        final Map<String, double> balances = {};
        if (balancesList != null) {
          for (var item in balancesList) {
            final asset = item['asset'].toString().toUpperCase();
            final free = double.tryParse(item['free'].toString()) ?? 0.0;
            if (free > 0) balances[asset] = free;
          }
        }
        return balances;
      }
    } catch (e) {
      // Ignored
    }
    return {};
  }

  /// Fetch private transaction history (myTrades) from Binance
  Future<List<Map<String, dynamic>>> fetchFills({
    required String symbol,
    required String apiKey,
    required String apiSecret,
    required DateTime startAt,
    void Function(double progress, String statusMessage, int foundCount)? onProgress,
  }) async {
    final formattedSymbol = symbol.replaceAll('/', '').replaceAll('-', '').toUpperCase();
    final now = DateTime.now();
    final List<Map<String, dynamic>> allFills = [];
    DateTime currentEnd = now;

    final totalSpanDays = now.difference(startAt).inDays;
    final totalChunks = (totalSpanDays / 30.0).ceil().clamp(1, 100);
    int completedChunks = 0;

    while (currentEnd.isAfter(startAt)) {
      DateTime currentStart = currentEnd.subtract(const Duration(days: 30));
      if (currentStart.isBefore(startAt)) {
        currentStart = startAt;
      }

      completedChunks++;
      final progress = (completedChunks / totalChunks).clamp(0.0, 1.0);
      final startLabel = '${currentStart.day}/${currentStart.month}/${currentStart.year}';
      final endLabel = '${currentEnd.day}/${currentEnd.month}/${currentEnd.year}';
      if (onProgress != null) {
        onProgress(progress, 'Binance: Consultando $startLabel al $endLabel ($completedChunks/$totalChunks)', allFills.length);
      }

      final startMs = currentStart.millisecondsSinceEpoch;
      final endMs = currentEnd.millisecondsSinceEpoch;
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final queryParams = 'symbol=$formattedSymbol&startTime=$startMs&endTime=$endMs&recvWindow=5000&timestamp=$timestamp';

      final key = utf8.encode(apiSecret);
      final hmac = Hmac(sha256, key);
      final digest = hmac.convert(utf8.encode(queryParams));
      final signature = digest.toString();

      final url = Uri.parse('https://api.binance.com/api/v3/myTrades?$queryParams&signature=$signature');

      try {
        final response = await http.get(
          url,
          headers: {
            'X-MBX-APIKEY': apiKey,
            'Content-Type': 'application/json',
          },
        );

        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body);
          for (var item in data) {
            allFills.add({
              'tradeId': item['id'].toString(),
              'symbol': symbol,
              'side': item['isBuyer'] == true ? 'buy' : 'sell',
              'price': double.parse(item['price'].toString()),
              'amount': double.parse(item['qty'].toString()),
              'fee': double.parse(item['commission'].toString()),
              'createdAt': item['time'] as int,
            });
          }
        } else {
          break;
        }
      } catch (e) {
        break;
      }

      currentEnd = currentStart;
      await Future.delayed(const Duration(milliseconds: 150));
    }

    return allFills;
  }

  /// Fetch level 2 order book (depth) from Binance
  Future<Map<String, dynamic>> fetchOrderBook(String symbol, {int limit = 20}) async {
    final formattedSymbol = symbol.replaceAll('-', '').replaceAll('/', '').toUpperCase();
    final url = Uri.parse('https://api.binance.com/api/v3/depth?symbol=$formattedSymbol&limit=$limit');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        final List<dynamic> rawBids = data['bids'] ?? [];
        final List<dynamic> rawAsks = data['asks'] ?? [];

        final List<List<double>> bids = rawBids.map<List<double>>((b) => [
          double.parse(b[0].toString()),
          double.parse(b[1].toString()),
        ]).toList();

        final List<List<double>> asks = rawAsks.map<List<double>>((a) => [
          double.parse(a[0].toString()),
          double.parse(a[1].toString()),
        ]).toList();

        return {'bids': bids, 'asks': asks};
      }
    } catch (_) {}
    return {'bids': <List<double>>[], 'asks': <List<double>>[]};
  }

  /// Fetch public recent trades from Binance
  Future<List<Map<String, dynamic>>> fetchRecentTrades(String symbol, {int limit = 50}) async {
    final formattedSymbol = symbol.replaceAll('-', '').replaceAll('/', '').toUpperCase();
    final url = Uri.parse('https://api.binance.com/api/v3/trades?symbol=$formattedSymbol&limit=$limit');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map<Map<String, dynamic>>((t) => {
          'price': double.parse(t['price'].toString()),
          'size': double.parse(t['qty'].toString()),
          'side': t['isBuyerMaker'] == true ? 'sell' : 'buy',
          'time': t['time'] as int,
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Fetch open active orders from Binance
  Future<List<Map<String, dynamic>>> fetchOpenOrders({
    required String apiKey,
    required String apiSecret,
    String? symbol,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    var queryParams = 'recvWindow=5000&timestamp=$timestamp';
    if (symbol != null && symbol.isNotEmpty) {
      final formattedSymbol = symbol.replaceAll('-', '').replaceAll('/', '').toUpperCase();
      queryParams = 'symbol=$formattedSymbol&$queryParams';
    }
    final key = utf8.encode(apiSecret);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(utf8.encode(queryParams));
    final signature = digest.toString();
    final url = Uri.parse('https://api.binance.com/api/v3/openOrders?$queryParams&signature=$signature');

    try {
      final response = await http.get(
        url,
        headers: {
          'X-MBX-APIKEY': apiKey,
          'Content-Type': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map<Map<String, dynamic>>((o) => {
          'id': o['orderId'].toString(),
          'symbol': o['symbol'].toString(),
          'side': o['side'].toString().toLowerCase(),
          'type': o['type'].toString().toLowerCase(),
          'price': double.tryParse(o['price'].toString()) ?? 0.0,
          'size': double.tryParse(o['origQty'].toString()) ?? 0.0,
          'dealSize': double.tryParse(o['executedQty'].toString()) ?? 0.0,
          'funds': (double.tryParse(o['price'].toString()) ?? 0.0) * (double.tryParse(o['origQty'].toString()) ?? 0.0),
          'createdAt': o['time'] as int,
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Place a limit or market order on Binance
  Future<Map<String, dynamic>> placeOrder({
    required String apiKey,
    required String apiSecret,
    required String symbol,
    required String side, // 'BUY' or 'SELL'
    required String type, // 'LIMIT' or 'MARKET'
    double? price,
    double? size,
    double? funds,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final formattedSymbol = symbol.replaceAll('-', '').replaceAll('/', '').toUpperCase();
    var queryParams = 'symbol=$formattedSymbol&side=${side.toUpperCase()}&type=${type.toUpperCase()}&recvWindow=5000&timestamp=$timestamp';

    if (type.toUpperCase() == 'LIMIT') {
      if (price == null || price <= 0 || size == null || size <= 0) {
        throw Exception('Precio y cantidad son requeridos para órdenes límite.');
      }
      queryParams += '&timeInForce=GTC&price=$price&quantity=$size';
    } else {
      if (side.toUpperCase() == 'BUY' && funds != null && funds > 0) {
        queryParams += '&quoteOrderQty=$funds';
      } else if (size != null && size > 0) {
        queryParams += '&quantity=$size';
      }
    }

    final key = utf8.encode(apiSecret);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(utf8.encode(queryParams));
    final signature = digest.toString();
    final url = Uri.parse('https://api.binance.com/api/v3/order?$queryParams&signature=$signature');

    final response = await http.post(
      url,
      headers: {
        'X-MBX-APIKEY': apiKey,
        'Content-Type': 'application/json',
      },
    );

    final Map<String, dynamic> data = json.decode(response.body);
    if (response.statusCode == 200) {
      return data;
    } else {
      throw Exception(data['msg'] ?? 'Error al colocar orden en Binance (${data['code']})');
    }
  }

  /// Cancel an active order on Binance
  Future<bool> cancelOrder({
    required String apiKey,
    required String apiSecret,
    required String symbol,
    required String orderId,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final formattedSymbol = symbol.replaceAll('-', '').replaceAll('/', '').toUpperCase();
    final queryParams = 'symbol=$formattedSymbol&orderId=$orderId&recvWindow=5000&timestamp=$timestamp';

    final key = utf8.encode(apiSecret);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(utf8.encode(queryParams));
    final signature = digest.toString();
    final url = Uri.parse('https://api.binance.com/api/v3/order?$queryParams&signature=$signature');

    final response = await http.delete(
      url,
      headers: {
        'X-MBX-APIKEY': apiKey,
        'Content-Type': 'application/json',
      },
    );

    final Map<String, dynamic> data = json.decode(response.body);
    if (response.statusCode == 200) {
      return true;
    } else {
      throw Exception(data['msg'] ?? 'Error al cancelar orden en Binance (${data['code']})');
    }
  }
}
