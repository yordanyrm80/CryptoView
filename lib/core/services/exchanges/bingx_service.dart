import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class BingxService {
  static final BingxService instance = BingxService._init();
  BingxService._init();

  String _formatSymbol(String symbol) {
    String formatted = symbol.replaceAll('/', '-').toUpperCase();
    if (!formatted.contains('-')) {
      if (formatted.endsWith('USDT')) {
        formatted = formatted.replaceFirst('USDT', '-USDT');
      }
    }
    return formatted;
  }

  Future<List<Map<String, dynamic>>> fetchKlines(String symbol, String interval, {int limit = 150}) async {
    final formattedSymbol = _formatSymbol(symbol);
    final url = Uri.parse('https://open-api.bingx.com/openApi/spot/v2/market/kline?symbol=$formattedSymbol&interval=$interval&limit=$limit');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final Map<String, dynamic> root = json.decode(response.body);
        if (root['code'] == 0) {
          final List<dynamic> data = root['data'];
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
      return [];
    }
  }

  Future<Map<String, double>> fetchPrices(List<String> symbols) async {
    final Map<String, double> priceMap = {for (var s in symbols) s: 0.0};
    try {
      final url = Uri.parse('https://open-api.bingx.com/openApi/spot/v1/ticker/price');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final Map<String, dynamic> root = json.decode(response.body);
        if (root['code'] == 0) {
          final List<dynamic> data = root['data'];
          for (var item in data) {
            final sym = item['symbol'].toString();
            for (var target in symbols) {
              final formattedTarget = target.replaceAll('/', '-').toUpperCase();
              if (sym == formattedTarget) {
                priceMap[target] = double.parse(item['price'].toString());
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

  /// Fetch private balances from BingX
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
    final url = Uri.parse('https://open-api.bingx.com/openApi/spot/v1/account/balance?$queryParams&signature=$signature');

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
          final List<dynamic>? balancesList = root['data']?['balances'];
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
    required DateTime startAt,
  }) async {
    final formattedSymbol = symbol.replaceAll('/', '-').toUpperCase();
    final now = DateTime.now();
    final List<Map<String, dynamic>> allFills = [];
    DateTime currentEnd = now;

    while (currentEnd.isAfter(startAt)) {
      DateTime currentStart = currentEnd.subtract(const Duration(days: 30));
      if (currentStart.isBefore(startAt)) {
        currentStart = startAt;
      }

      final startMs = currentStart.millisecondsSinceEpoch;
      final endMs = currentEnd.millisecondsSinceEpoch;
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final queryParams = 'endTime=$endMs&recvWindow=5000&startTime=$startMs&symbol=$formattedSymbol&timestamp=$timestamp';

      final key = utf8.encode(apiSecret);
      final hmac = Hmac(sha256, key);
      final digest = hmac.convert(utf8.encode(queryParams));
      final signature = digest.toString();

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
            break;
          }
        } else {
          break;
        }
      } catch (e) {
        break;
      }

      currentEnd = currentStart;
      await Future.delayed(const Duration(milliseconds: 200));
    }

    return allFills;
  }
}
