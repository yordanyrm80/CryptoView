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
      print('Error fetching Binance klines: $e');
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
      print('Error fetching Binance prices: $e');
    }
    return priceMap;
  }

  /// Fetch private transaction history (myTrades) from Binance
  Future<List<Map<String, dynamic>>> fetchFills({
    required String symbol,
    required String apiKey,
    required String apiSecret,
    required DateTime startAt,
  }) async {
    final formattedSymbol = symbol.replaceAll('/', '').replaceAll('-', '').toUpperCase();
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
}
