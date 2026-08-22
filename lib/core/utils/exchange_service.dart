import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class ExchangeService {
  static final ExchangeService instance = ExchangeService._init();
  ExchangeService._init();

  // Fetch K-line (candlestick) history from Binance
  Future<List<Map<String, dynamic>>> fetchBinanceKlines(String symbol, String interval, {int limit = 150}) async {
    // Format symbol: remove dashes (BTC-USDT -> BTCUSDT)
    final formattedSymbol = symbol.replaceAll('-', '').replaceAll('/', '').toUpperCase();
    final url = Uri.parse('https://api.binance.com/api/v3/klines?symbol=$formattedSymbol&interval=$interval&limit=$limit');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map<Map<String, dynamic>>((item) {
          return {
            // Binance time is in milliseconds, lightweight-charts needs seconds (int)
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
      print('Error fetching Binance klines: $e');
      return [];
    }
  }

  // Fetch K-line (candlestick) history from KuCoin
  Future<List<Map<String, dynamic>>> fetchKucoinKlines(String symbol, String interval) async {
    // Format symbol: ensure dash (BTC-USDT)
    String formattedSymbol = symbol.replaceAll('/', '-').toUpperCase();
    if (!formattedSymbol.contains('-')) {
      // Guess standard pairs, insert dash before USDT
      if (formattedSymbol.endsWith('USDT')) {
        formattedSymbol = formattedSymbol.replaceFirst('USDT', '-USDT');
      }
    }

    // Interval mapping (Kucoin uses: 1min, 5min, 15min, 1hour, 4hour, 1day, 1week)
    String kucoinInterval = '1day';
    if (interval == '1m') kucoinInterval = '1min';
    else if (interval == '5m') kucoinInterval = '5min';
    else if (interval == '15m') kucoinInterval = '15min';
    else if (interval == '1h') kucoinInterval = '1hour';
    else if (interval == '4h') kucoinInterval = '4hour';
    else if (interval == '1d') kucoinInterval = '1day';

    final url = Uri.parse('https://api.kucoin.com/api/v1/market/candles?symbol=$formattedSymbol&type=$kucoinInterval');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final Map<String, dynamic> root = json.decode(response.body);
        if (root['code'] == '200000') {
          final List<dynamic> data = root['data'];
          // Kucoin returns candles in reverse order (newest first), and values:
          // [time, open, close, high, low, volume, turnover]
          final List<Map<String, dynamic>> candles = [];
          for (var item in data) {
            candles.add({
              'time': int.parse(item[0].toString()), // Kucoin time is already in seconds
              'open': double.parse(item[1].toString()),
              'high': double.parse(item[3].toString()),
              'low': double.parse(item[4].toString()),
              'close': double.parse(item[2].toString()),
            });
          }
          // Reverse to make it chronological (oldest first)
          return candles.reversed.toList();
        }
      }
      throw Exception('Failed to load KuCoin candles: ${response.statusCode}');
    } catch (e) {
      print('Error fetching KuCoin klines: $e');
      return [];
    }
  }

  // Fetch K-line (candlestick) history from BingX
  Future<List<Map<String, dynamic>>> fetchBingXKlines(String symbol, String interval, {int limit = 150}) async {
    // Format symbol: ensure dash (BTC-USDT)
    String formattedSymbol = symbol.replaceAll('/', '-').toUpperCase();
    if (!formattedSymbol.contains('-')) {
      if (formattedSymbol.endsWith('USDT')) {
        formattedSymbol = formattedSymbol.replaceFirst('USDT', '-USDT');
      }
    }

    // Interval mapping (BingX uses: 1m, 5m, 15m, 30m, 1h, 4h, 1d, 1w)
    final url = Uri.parse('https://open-api.bingx.com/openApi/spot/v2/market/kline?symbol=$formattedSymbol&interval=$interval&limit=$limit');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final Map<String, dynamic> root = json.decode(response.body);
        if (root['code'] == 0) {
          final List<dynamic> data = root['data'];
          // BingX returns list of objects:
          // { "open": "...", "close": "...", "high": "...", "low": "...", "volume": "...", "time": timestampMs }
          // Ordered oldest to newest or newest to oldest? Usually oldest to newest, but let's sort just in case.
          final List<Map<String, dynamic>> candles = data.map<Map<String, dynamic>>((item) {
            return {
              'time': (item['time'] as int) ~/ 1000,
              'open': double.parse(item['open'].toString()),
              'high': double.parse(item['high'].toString()),
              'low': double.parse(item['low'].toString()),
              'close': double.parse(item['close'].toString()),
            };
          }).toList();
          
          candles.sort((a, b) => (a['time'] as int).compareTo(b['time'] as int));
          return candles;
        }
      }
      throw Exception('Failed to load BingX candles: ${response.statusCode}');
    } catch (e) {
      print('Error fetching BingX klines: $e');
      return [];
    }
  }

  // Fetch prices for a list of predefined popular symbols across all exchanges
  Future<Map<String, double>> fetchPrices(String exchange, List<String> symbols) async {
    final Map<String, double> priceMap = {};
    for (var symbol in symbols) {
      priceMap[symbol] = 0.0;
    }

    try {
      if (exchange.toLowerCase() == 'binance') {
        final url = Uri.parse('https://api.binance.com/api/v3/ticker/price');
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final List<dynamic> data = json.decode(response.body);
          for (var item in data) {
            final sym = item['symbol'].toString();
            // Match with standard formats (e.g. BTCUSDT)
            for (var target in symbols) {
              final formattedTarget = target.replaceAll('-', '').replaceAll('/', '').toUpperCase();
              if (sym == formattedTarget) {
                priceMap[target] = double.parse(item['price'].toString());
              }
            }
          }
        }
      } else if (exchange.toLowerCase() == 'kucoin') {
        final url = Uri.parse('https://api.kucoin.com/api/v1/market/allTickers');
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final Map<String, dynamic> root = json.decode(response.body);
          if (root['code'] == '200000') {
            final List<dynamic> tickers = root['data']['ticker'];
            for (var item in tickers) {
              final sym = item['symbol'].toString(); // e.g. BTC-USDT
              for (var target in symbols) {
                final formattedTarget = target.replaceAll('/', '-').toUpperCase();
                if (sym == formattedTarget) {
                  priceMap[target] = double.parse(item['last'].toString());
                }
              }
            }
          }
        }
      } else if (exchange.toLowerCase() == 'bingx') {
        // BingX spot ticker price
        final url = Uri.parse('https://open-api.bingx.com/openApi/spot/v1/ticker/price');
        final response = await http.get(url);
        if (response.statusCode == 200) {
          final Map<String, dynamic> root = json.decode(response.body);
          if (root['code'] == 0) {
            final List<dynamic> data = root['data'];
            for (var item in data) {
              final sym = item['symbol'].toString(); // e.g. BTC-USDT
              for (var target in symbols) {
                final formattedTarget = target.replaceAll('/', '-').toUpperCase();
                if (sym == formattedTarget) {
                  priceMap[target] = double.parse(item['price'].toString());
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error fetching prices for $exchange: $e');
    }

    return priceMap;
  }

  // Helper methods to sign KuCoin requests
  String _generateKucoinSignature(String secret, String timestamp, String method, String requestPath, String body) {
    final prehash = timestamp + method + requestPath + body;
    final key = utf8.encode(secret);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(utf8.encode(prehash));
    return base64.encode(digest.bytes);
  }

  String _generateKucoinPassphrase(String secret, String passphrase) {
    final key = utf8.encode(secret);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(utf8.encode(passphrase));
    return base64.encode(digest.bytes);
  }

  // Fetch private transaction history (fills) for a specific symbol on KuCoin
  Future<List<Map<String, dynamic>>> fetchKucoinFills({
    required String symbol,
    required String apiKey,
    required String apiSecret,
    required String apiPassphrase,
    required DateTime startAt,
  }) async {
    // Format symbol: convert BTC/USDT to BTC-USDT
    final formattedSymbol = symbol.replaceAll('/', '-').toUpperCase();
    final now = DateTime.now();

    // KuCoin restricts time range to 7 days per query. We will loop back in 7-day increments.
    final List<Map<String, dynamic>> allFills = [];
    DateTime currentEnd = now;

    while (currentEnd.isAfter(startAt)) {
      DateTime currentStart = currentEnd.subtract(const Duration(days: 7));
      if (currentStart.isBefore(startAt)) {
        currentStart = startAt;
      }

      final startMs = currentStart.millisecondsSinceEpoch;
      final endMs = currentEnd.millisecondsSinceEpoch;
      
      final endpoint = '/api/v1/fills';
      final queryParams = 'endAt=$endMs&limit=100&startAt=$startMs&symbol=$formattedSymbol';
      final requestPath = '$endpoint?$queryParams';
      final url = Uri.parse('https://api.kucoin.com$requestPath');
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

      try {
        final signature = _generateKucoinSignature(apiSecret, timestamp, 'GET', requestPath, '');
        final encryptedPassphrase = _generateKucoinPassphrase(apiSecret, apiPassphrase);

        final response = await http.get(
          url,
          headers: {
            'KC-API-KEY': apiKey,
            'KC-API-SIGN': signature,
            'KC-API-TIMESTAMP': timestamp,
            'KC-API-PASSPHRASE': encryptedPassphrase,
            'KC-API-KEY-VERSION': '2',
            'Content-Type': 'application/json',
          },
        );

        if (response.statusCode == 200) {
          final Map<String, dynamic> root = json.decode(response.body);
          if (root['code'] == '200000') {
            final Map<String, dynamic> data = root['data'];
            final List<dynamic>? items = data['items'];
            if (items != null) {
              for (var item in items) {
                // Map the trade fields to expected Dart Map
                allFills.add({
                  'tradeId': item['tradeId'],
                  'orderId': item['orderId'] ?? item['tradeId'],
                  'symbol': symbol, // Keep user format (BTC/USDT)
                  'side': item['side'], // 'buy' or 'sell'
                  'price': double.parse(item['price'].toString()),
                  'amount': double.parse(item['size'].toString()),
                  'fee': double.parse(item['fee'].toString()),
                  'createdAt': int.parse(item['createdAt'].toString()),
                });
              }
            }
          } else {
            print('KuCoin API warning: ${root['msg']}');
            break;
          }
        } else {
          print('KuCoin API HTTP error: ${response.statusCode} | ${response.body}');
          break;
        }
      } catch (e) {
        print('Error fetching fills block: $e');
        break;
      }

      currentEnd = currentStart;
      await Future.delayed(const Duration(milliseconds: 200)); // Respect rate limits
    }

    // Merge multiple fills belonging to the same orderId
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var fill in allFills) {
      final orderId = fill['orderId'] as String;
      grouped.putIfAbsent(orderId, () => []).add(fill);
    }

    final List<Map<String, dynamic>> mergedFills = [];
    grouped.forEach((orderId, fillsList) {
      if (fillsList.length == 1) {
        mergedFills.add(fillsList.first);
      } else {
        final first = fillsList.first;
        double totalAmount = 0.0;
        double totalFunds = 0.0;
        double totalFee = 0.0;
        int latestCreatedAt = 0;

        for (var fill in fillsList) {
          final amt = fill['amount'] as double;
          final prc = fill['price'] as double;
          totalAmount += amt;
          totalFunds += prc * amt;
          totalFee += fill['fee'] as double;
          final created = fill['createdAt'] as int;
          if (created > latestCreatedAt) {
            latestCreatedAt = created;
          }
        }

        final averagePrice = totalAmount > 0 ? totalFunds / totalAmount : first['price'] as double;

        mergedFills.add({
          'tradeId': orderId, // Use orderId as key to prevent duplicates in DB
          'orderId': orderId,
          'symbol': first['symbol'],
          'side': first['side'],
          'price': averagePrice,
          'amount': totalAmount,
          'fee': totalFee,
          'createdAt': latestCreatedAt,
        });
      }
    });

    return mergedFills;
  }

  // Fetch private transaction history (fills) for a specific symbol on Binance
  Future<List<Map<String, dynamic>>> fetchBinanceFills({
    required String symbol,
    required String apiKey,
    required String apiSecret,
    required DateTime startAt,
  }) async {
    // Format symbol: remove slashes and dashes (BTC/USDT -> BTCUSDT)
    final formattedSymbol = symbol.replaceAll('/', '').replaceAll('-', '').toUpperCase();
    final now = DateTime.now();

    final List<Map<String, dynamic>> allFills = [];
    DateTime currentEnd = now;

    // Binance allows querying in large chunks, let's query in 30-day blocks
    while (currentEnd.isAfter(startAt)) {
      DateTime currentStart = currentEnd.subtract(const Duration(days: 30));
      if (currentStart.isBefore(startAt)) {
        currentStart = startAt;
      }

      final startMs = currentStart.millisecondsSinceEpoch;
      final endMs = currentEnd.millisecondsSinceEpoch;
      
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final queryParams = 'symbol=$formattedSymbol&startTime=$startMs&endTime=$endMs&recvWindow=5000&timestamp=$timestamp';
      
      // Sign with API Secret
      final key = utf8.encode(apiSecret);
      final hmac = Hmac(sha256, key);
      final digest = hmac.convert(utf8.encode(queryParams));
      final signature = digest.toString(); // Hex encoding

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
          print('Binance API HTTP error: ${response.statusCode} | ${response.body}');
          break;
        }
      } catch (e) {
        print('Error fetching Binance fills block: $e');
        break;
      }

      currentEnd = currentStart;
      await Future.delayed(const Duration(milliseconds: 200));
    }

    return allFills;
  }

  // Fetch private transaction history (fills) for a specific symbol on BingX
  Future<List<Map<String, dynamic>>> fetchBingXFills({
    required String symbol,
    required String apiKey,
    required String apiSecret,
    required DateTime startAt,
  }) async {
    // Format symbol: replace slash with dash (BTC/USDT -> BTC-USDT)
    final formattedSymbol = symbol.replaceAll('/', '-').toUpperCase();
    final now = DateTime.now();

    final List<Map<String, dynamic>> allFills = [];
    DateTime currentEnd = now;

    // BingX allows querying in 30-day blocks
    while (currentEnd.isAfter(startAt)) {
      DateTime currentStart = currentEnd.subtract(const Duration(days: 30));
      if (currentStart.isBefore(startAt)) {
        currentStart = startAt;
      }

      final startMs = currentStart.millisecondsSinceEpoch;
      final endMs = currentEnd.millisecondsSinceEpoch;
      
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      // Parameters must be sorted alphabetically by key: endTime -> recvWindow -> startTime -> symbol -> timestamp
      final queryParams = 'endTime=$endMs&recvWindow=5000&startTime=$startMs&symbol=$formattedSymbol&timestamp=$timestamp';
      
      // Sign with API Secret
      final key = utf8.encode(apiSecret);
      final hmac = Hmac(sha256, key);
      final digest = hmac.convert(utf8.encode(queryParams));
      final signature = digest.toString(); // Hex encoding

      final url = Uri.parse('https://open-api.bingx.com/openApi/spot/v1/trade/myTrades?$queryParams&signature=$signature');

      try {
        final response = await http.get(
          url,
          headers: {
            'X-BX-APIKEY': apiKey,
            'Content-Type': 'application/json',
          },
        );

        if (response.statusCode == 200) {
          final Map<String, dynamic> root = json.decode(response.body);
          if (root['code'] == 0) {
            final List<dynamic>? data = root['data'];
            if (data != null) {
              for (var item in data) {
                allFills.add({
                  'tradeId': item['id'].toString(),
                  'symbol': symbol,
                  'side': item['isBuyer'] == true ? 'buy' : 'sell',
                  'price': double.parse(item['price'].toString()),
                  'amount': double.parse((item['quantity'] ?? item['qty'] ?? item['size']).toString()),
                  'fee': double.parse((item['commission'] ?? item['fee'] ?? 0.0).toString()),
                  'createdAt': item['time'] as int,
                });
              }
            }
          } else {
            print('BingX API warning: ${root['msg']}');
            break;
          }
        } else {
          print('BingX API HTTP error: ${response.statusCode} | ${response.body}');
          break;
        }
      } catch (e) {
        print('Error fetching BingX fills block: $e');
        break;
      }

      currentEnd = currentStart;
      await Future.delayed(const Duration(milliseconds: 200));
    }

    return allFills;
  }
}
