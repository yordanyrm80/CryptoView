import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

void main() async {
  print('=== PRUEBA DE PARSEO DE HISTORIAL ===\n');

  final apiKey = '6a5d641a0ff4980001cd950d';
  final apiSecret = '32ba1ef4-352c-417f-80df-593ec5faa4b8';
  final apiPassphrase = 'Ea9wOg5R9HG1JYaeaXANSr1qTOx6EIBN';

  final now = DateTime.now();
  final ninetyDaysAgo = now.subtract(const Duration(days: 90));

  await queryAndParseFills(
    apiKey: apiKey,
    apiSecret: apiSecret,
    apiPassphrase: apiPassphrase,
    symbol: 'ETH-USDT',
    startAt: ninetyDaysAgo,
    endAt: now,
  );
}

Future<void> queryAndParseFills({
  required String apiKey,
  required String apiSecret,
  required String apiPassphrase,
  required String symbol,
  required DateTime startAt,
  required DateTime endAt,
}) async {
  DateTime currentEnd = endAt;
  int blockCount = 1;

  while (currentEnd.isAfter(startAt)) {
    DateTime currentStart = currentEnd.subtract(const Duration(days: 7));
    if (currentStart.isBefore(startAt)) {
      currentStart = startAt;
    }

    final startMs = currentStart.millisecondsSinceEpoch;
    final endMs = currentEnd.millisecondsSinceEpoch;

    print('\n[Bloque $blockCount] Del $currentStart al $currentEnd...');
    
    final endpoint = '/api/v1/fills';
    final queryParams = 'endAt=$endMs&limit=100&startAt=$startMs&symbol=$symbol';
    final requestPath = '$endpoint?$queryParams';
    final url = Uri.parse('https://api.kucoin.com$requestPath');
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();

    final prehash = timestamp + 'GET' + requestPath + '';
    final key = utf8.encode(apiSecret);
    final hmac = Hmac(sha256, key);
    final signDigest = hmac.convert(utf8.encode(prehash));
    final signature = base64.encode(signDigest.bytes);

    final passphraseDigest = hmac.convert(utf8.encode(apiPassphrase));
    final encryptedPassphrase = base64.encode(passphraseDigest.bytes);

    try {
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
          final count = items?.length ?? 0;
          print(' -> Se encontraron $count operaciones.');
          
          if (count > 0) {
            for (var item in items!) {
              try {
                // Simulación exacta del mapeo de la aplicación
                final mapped = {
                  'tradeId': item['tradeId'],
                  'symbol': symbol,
                  'side': item['side'],
                  'price': double.parse(item['price'].toString()),
                  'amount': double.parse(item['size'].toString()),
                  'fee': double.parse(item['fee'].toString()),
                  'createdAt': int.parse(item['createdAt'].toString()),
                };
                print('    - PARSEO EXITOSO: ${mapped['tradeId']} | Price: ${mapped['price']} | Date: ${DateTime.fromMillisecondsSinceEpoch(mapped['createdAt'] as int)}');
              } catch (e, stack) {
                print('    - ERROR AL PARSEAR ITEM: $e');
                print('      JSON del item fallido: $item');
                print(stack);
              }
            }
          }
        } else {
          print(' -> Error KuCoin: ${root['msg']}');
        }
      } else {
        print(' -> Error HTTP: ${response.statusCode}');
      }
    } catch (e) {
      print(' -> Error: $e');
    }

    currentEnd = currentStart;
    blockCount++;
    await Future.delayed(const Duration(milliseconds: 200));
  }
}
