import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class KucoinService {
  static final KucoinService instance = KucoinService._init();
  KucoinService._init();

  /// Map common interval strings to KuCoin API interval format
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

  /// Format symbol to KuCoin DASH format (e.g. BTC-USDT)
  String _formatSymbol(String symbol) {
    String formatted = symbol.replaceAll('/', '-').toUpperCase();
    if (!formatted.contains('-')) {
      if (formatted.endsWith('USDT')) {
        formatted = formatted.replaceFirst('USDT', '-USDT');
      }
    }
    return formatted;
  }

  /// Fetch K-line (candlestick) history from KuCoin
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
      print('Error fetching KuCoin candles: $e');
      return [];
    }
  }

  /// Fetch ticker prices for given symbols from KuCoin
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
      print('Error fetching KuCoin prices: $e');
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

  /// Fetch private transaction history (fills) from KuCoin (7-day chunks + grouped by orderId)
  Future<List<Map<String, dynamic>>> fetchFills({
    required String symbol,
    required String apiKey,
    required String apiSecret,
    required String apiPassphrase,
    required DateTime startAt,
  }) async {
    final formattedSymbol = _formatSymbol(symbol);
    final now = DateTime.now();
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
          } else {
            print('KuCoin API warning: ${root['msg']}');
            break;
          }
        } else {
          print('KuCoin API HTTP error: ${response.statusCode} | ${response.body}');
          break;
        }
      } catch (e) {
        print('Error fetching KuCoin fills block: $e');
        break;
      }

      currentEnd = currentStart;
      await Future.delayed(const Duration(milliseconds: 200));
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
}
