import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class KucoinService {
  static final KucoinService instance = KucoinService._init();
  KucoinService._init();

  String _mapInterval(String interval) {
    switch (interval) {
      case '1m': return '1min';
      case '5m': return '5min';
      case '15m': return '15min';
      case '1h': return '1hour';
      case '4h': return '4hour';
      case '1d': return '1day';
      default: return '1hour';
    }
  }

  String _formatSymbol(String symbol) {
    String formatted = symbol.replaceAll('/', '-').toUpperCase();
    if (!formatted.contains('-')) {
      if (formatted.endsWith('USDT')) {
        formatted = formatted.replaceFirst('USDT', '-USDT');
      }
    }
    return formatted;
  }

  Future<List<Map<String, dynamic>>> fetchCandles(String symbol, String interval) async {
    final formattedSymbol = _formatSymbol(symbol);
    final kucoinInterval = _mapInterval(interval);
    final url = Uri.parse('https://api.kucoin.com/api/v1/market/candles?symbol=$formattedSymbol&type=$kucoinInterval');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final Map<String, dynamic> root = json.decode(response.body);
        if (root['code'] == '200000') {
          final List<dynamic> data = root['data'];
          final List<Map<String, dynamic>> candles = [];
          for (var item in data) {
            candles.add({
              'time': int.parse(item[0].toString()),
              'open': double.parse(item[1].toString()),
              'high': double.parse(item[3].toString()),
              'low': double.parse(item[4].toString()),
              'close': double.parse(item[2].toString()),
            });
          }
          return candles.reversed.toList();
        }
      }
      throw Exception('Failed to load KuCoin candles: ${response.statusCode}');
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, double>> fetchPrices(List<String> symbols) async {
    final Map<String, double> priceMap = {for (var s in symbols) s: 0.0};
    try {
      final url = Uri.parse('https://api.kucoin.com/api/v1/market/allTickers');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final Map<String, dynamic> root = json.decode(response.body);
        if (root['code'] == '200000') {
          final List<dynamic> tickers = root['data']['ticker'];
          for (var item in tickers) {
            final sym = item['symbol'].toString();
            for (var target in symbols) {
              final formattedTarget = target.replaceAll('/', '-').toUpperCase();
              if (sym == formattedTarget) {
                priceMap[target] = double.parse(item['last'].toString());
              }
            }
          }
        }
      }
    } catch (e) {
      // Ignored
    }
    return priceMap;
  }

  String _generateSignature(String secret, String timestamp, String method, String requestPath, String body) {
    final prehash = timestamp + method + requestPath + body;
    final key = utf8.encode(secret);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(utf8.encode(prehash));
    return base64.encode(digest.bytes);
  }

  String _generatePassphrase(String secret, String passphrase) {
    final key = utf8.encode(secret);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(utf8.encode(passphrase));
    return base64.encode(digest.bytes);
  }

  /// Fetch private balances from KuCoin
  Future<Map<String, double>> fetchBalances({
    required String apiKey,
    required String apiSecret,
    required String apiPassphrase,
  }) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    const requestPath = '/api/v1/accounts';
    final url = Uri.parse('https://api.kucoin.com$requestPath');

    try {
      final signature = _generateSignature(apiSecret, timestamp, 'GET', requestPath, '');
      final encryptedPassphrase = _generatePassphrase(apiSecret, apiPassphrase);

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
          final List<dynamic> items = root['data'];
          final Map<String, double> balances = {};
          for (var item in items) {
            final currency = item['currency'].toString().toUpperCase();
            final available = double.tryParse(item['available'].toString()) ?? 0.0;
            balances[currency] = (balances[currency] ?? 0.0) + available;
          }
          return balances;
        }
      }
    } catch (e) {
      // Ignored
    }
    return {};
  }

  Future<List<Map<String, dynamic>>> fetchFills({
    required String symbol,
    required String apiKey,
    required String apiSecret,
    required String apiPassphrase,
    required DateTime startAt,
    void Function(double progress, String statusMessage, int foundCount)? onProgress,
  }) async {
    final formattedSymbol = _formatSymbol(symbol);
    final now = DateTime.now();
    final List<Map<String, dynamic>> allFills = [];
    DateTime currentEnd = now;

    final totalSpanDays = now.difference(startAt).inDays;
    final totalChunks = (totalSpanDays / 7.0).ceil().clamp(1, 200);
    int completedChunks = 0;

    while (currentEnd.isAfter(startAt)) {
      DateTime currentStart = currentEnd.subtract(const Duration(days: 7));
      if (currentStart.isBefore(startAt)) {
        currentStart = startAt;
      }

      completedChunks++;
      final progress = (completedChunks / totalChunks).clamp(0.0, 1.0);
      final startLabel = '${currentStart.day}/${currentStart.month}/${currentStart.year}';
      final endLabel = '${currentEnd.day}/${currentEnd.month}/${currentEnd.year}';
      if (onProgress != null) {
        onProgress(progress, 'KuCoin: Consultando $startLabel al $endLabel ($completedChunks/$totalChunks)', allFills.length);
      }

      final startMs = currentStart.millisecondsSinceEpoch;
      final endMs = currentEnd.millisecondsSinceEpoch;
      const endpoint = '/api/v1/fills';
      final queryParams = 'endAt=$endMs&pageSize=500&startAt=$startMs&symbol=$formattedSymbol';
      final requestPath = '$endpoint?$queryParams';
      final url = Uri.parse('https://api.kucoin.com$requestPath');
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

      try {
        final signature = _generateSignature(apiSecret, timestamp, 'GET', requestPath, '');
        final encryptedPassphrase = _generatePassphrase(apiSecret, apiPassphrase);

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
                allFills.add({
                  'tradeId': item['tradeId'],
                  'orderId': item['orderId'] ?? item['tradeId'],
                  'symbol': symbol,
                  'side': item['side'],
                  'price': double.parse(item['price'].toString()),
                  'amount': double.parse(item['size'].toString()),
                  'fee': double.parse(item['fee'].toString()),
                  'createdAt': int.parse(item['createdAt'].toString()),
                });
              }
            }
          }
        }
      } catch (e) {
        // Continue to earlier chunks
      }

      currentEnd = currentStart;
      await Future.delayed(const Duration(milliseconds: 100));
    }

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
          'tradeId': orderId,
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

  /// Fetch level 2 order book (depth) from KuCoin
  Future<Map<String, dynamic>> fetchOrderBook(String symbol, {int limit = 20}) async {
    final formattedSymbol = _formatSymbol(symbol);
    final url = Uri.parse('https://api.kucoin.com/api/v1/market/orderbook/level2_20?symbol=$formattedSymbol');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final Map<String, dynamic> root = json.decode(response.body);
        if (root['code'] == '200000') {
          final data = root['data'];
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
      }
    } catch (_) {}
    return {'bids': <List<double>>[], 'asks': <List<double>>[]};
  }

  /// Fetch public recent trades from KuCoin
  Future<List<Map<String, dynamic>>> fetchRecentTrades(String symbol, {int limit = 50}) async {
    final formattedSymbol = _formatSymbol(symbol);
    final url = Uri.parse('https://api.kucoin.com/api/v1/market/histories?symbol=$formattedSymbol');
    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final Map<String, dynamic> root = json.decode(response.body);
        if (root['code'] == '200000') {
          final List<dynamic> data = root['data'] ?? [];
          return data.take(limit).map<Map<String, dynamic>>((t) => {
            'price': double.parse(t['price'].toString()),
            'size': double.parse(t['size'].toString()),
            'side': t['side'].toString().toLowerCase(),
            'time': ((t['time'] as num).toInt() ~/ 1000000), // ms
          }).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// Fetch open active orders from KuCoin
  Future<List<Map<String, dynamic>>> fetchOpenOrders({
    required String apiKey,
    required String apiSecret,
    required String apiPassphrase,
    String? symbol,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    String requestPath = '/api/v1/orders?status=active';
    if (symbol != null && symbol.isNotEmpty) {
      requestPath += '&symbol=${_formatSymbol(symbol)}';
    }
    final signature = _generateSignature(apiSecret, now, 'GET', requestPath, '');
    final passphraseSigned = _generatePassphrase(apiSecret, apiPassphrase);

    final url = Uri.parse('https://api.kucoin.com$requestPath');
    try {
      final response = await http.get(url, headers: {
        'KC-API-KEY': apiKey,
        'KC-API-SIGN': signature,
        'KC-API-TIMESTAMP': now,
        'KC-API-PASSPHRASE': passphraseSigned,
        'KC-API-KEY-VERSION': '2',
      });
      if (response.statusCode == 200) {
        final Map<String, dynamic> root = json.decode(response.body);
        if (root['code'] == '200000') {
          final List<dynamic> items = root['data']['items'] ?? [];
          return items.map<Map<String, dynamic>>((o) => {
            'id': o['id'].toString(),
            'symbol': o['symbol'].toString().replaceAll('-', '/'),
            'side': o['side'].toString().toLowerCase(),
            'type': o['type'].toString().toLowerCase(),
            'price': double.tryParse(o['price'].toString()) ?? 0.0,
            'size': double.tryParse(o['size'].toString()) ?? 0.0,
            'dealSize': double.tryParse(o['dealSize'].toString()) ?? 0.0,
            'funds': double.tryParse(o['funds']?.toString() ?? '0') ?? 0.0,
            'createdAt': (o['createdAt'] as num).toInt(),
          }).toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// Place a limit or market order on KuCoin
  Future<Map<String, dynamic>> placeOrder({
    required String apiKey,
    required String apiSecret,
    required String apiPassphrase,
    required String symbol,
    required String side, // 'buy' or 'sell'
    required String type, // 'limit' or 'market'
    double? price,
    double? size,
    double? funds,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    const requestPath = '/api/v1/orders';
    final clientOid = '${DateTime.now().millisecondsSinceEpoch}-${DateTime.now().microsecond}';

    final Map<String, dynamic> payload = {
      'clientOid': clientOid,
      'side': side.toLowerCase(),
      'symbol': _formatSymbol(symbol),
      'type': type.toLowerCase(),
    };

    if (type.toLowerCase() == 'limit') {
      if (price == null || price <= 0 || size == null || size <= 0) {
        throw Exception('Precio y cantidad son requeridos para órdenes límite.');
      }
      payload['price'] = price.toString();
      payload['size'] = size.toString();
    } else {
      // market
      if (side.toLowerCase() == 'buy') {
        if (funds != null && funds > 0) {
          payload['funds'] = funds.toString();
        } else if (size != null && size > 0) {
          payload['size'] = size.toString();
        }
      } else {
        if (size != null && size > 0) {
          payload['size'] = size.toString();
        }
      }
    }

    final bodyStr = json.encode(payload);
    final signature = _generateSignature(apiSecret, now, 'POST', requestPath, bodyStr);
    final passphraseSigned = _generatePassphrase(apiSecret, apiPassphrase);

    final url = Uri.parse('https://api.kucoin.com$requestPath');
    final response = await http.post(
      url,
      headers: {
        'KC-API-KEY': apiKey,
        'KC-API-SIGN': signature,
        'KC-API-TIMESTAMP': now,
        'KC-API-PASSPHRASE': passphraseSigned,
        'KC-API-KEY-VERSION': '2',
        'Content-Type': 'application/json',
      },
      body: bodyStr,
    );

    final Map<String, dynamic> root = json.decode(response.body);
    if (root['code'] == '200000') {
      return root['data'] ?? {};
    } else {
      throw Exception(root['msg'] ?? 'Error al colocar orden en KuCoin (${root['code']})');
    }
  }

  /// Cancel an active order on KuCoin
  Future<bool> cancelOrder({
    required String apiKey,
    required String apiSecret,
    required String apiPassphrase,
    required String orderId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    final requestPath = '/api/v1/orders/$orderId';
    final signature = _generateSignature(apiSecret, now, 'DELETE', requestPath, '');
    final passphraseSigned = _generatePassphrase(apiSecret, apiPassphrase);

    final url = Uri.parse('https://api.kucoin.com$requestPath');
    final response = await http.delete(
      url,
      headers: {
        'KC-API-KEY': apiKey,
        'KC-API-SIGN': signature,
        'KC-API-TIMESTAMP': now,
        'KC-API-PASSPHRASE': passphraseSigned,
        'KC-API-KEY-VERSION': '2',
      },
    );

    final Map<String, dynamic> root = json.decode(response.body);
    if (root['code'] == '200000') {
      return true;
    } else {
      throw Exception(root['msg'] ?? 'Error al cancelar orden en KuCoin (${root['code']})');
    }
  }
}
