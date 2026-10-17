import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class BitrefillService {
  static const String baseUrl = 'https://api.bitrefill.com/v2';

  /// Fetches all completed orders and invoice payment details from Bitrefill API
  Future<List<Map<String, dynamic>>> fetchOrders({
    required String apiKey,
    void Function(double progress, String statusMessage, int foundCount)? onProgress,
  }) async {
    final List<Map<String, dynamic>> results = [];
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'User-Agent': 'CryptoView/1.0',
      'Accept': 'application/json',
    };

    try {
      onProgress?.call(0.1, 'Consultando órdenes en Bitrefill API...', 0);
      final url = Uri.parse('$baseUrl/orders?limit=100');
      final resp = await http.get(url, headers: headers);

      if (resp.statusCode != 200) {
        debugPrint('Bitrefill API error ${resp.statusCode}: ${resp.body}');
        return results;
      }

      final Map<String, dynamic> body = json.decode(resp.body);
      final List<dynamic> orders = body['data'] ?? [];
      final total = orders.length;

      for (int i = 0; i < total; i++) {
        final o = orders[i] as Map<String, dynamic>;
        final status = o['status']?.toString().toLowerCase();
        if (status != 'delivered' && status != 'complete') continue;

        final oid = o['id']?.toString() ?? '';
        final product = o['product'] as Map<String, dynamic>? ?? {};
        final pname = product['name']?.toString() ?? product['id']?.toString() ?? 'Producto';
        final pval = product['value']?.toString() ?? '';
        final pcurr = product['currency']?.toString() ?? '';
        String dateStr = o['created_time']?.toString() ?? DateTime.now().toUtc().toIso8601String();

        final invoice = o['invoice'] as Map<String, dynamic>? ?? {};
        final invoiceId = invoice['id']?.toString();

        String? payCurr;
        double? payPriceRaw;

        if (invoiceId != null && invoiceId.isNotEmpty) {
          try {
            final invUrl = Uri.parse('$baseUrl/invoices/$invoiceId');
            final invResp = await http.get(invUrl, headers: headers);
            if (invResp.statusCode == 200) {
              final invBody = json.decode(invResp.body);
              final invData = invBody['data'] as Map<String, dynamic>? ?? {};
              final payment = invData['payment'] as Map<String, dynamic>? ?? {};
              payCurr = payment['currency']?.toString().toUpperCase();
              final rawP = payment['price'];
              if (rawP != null) {
                payPriceRaw = double.tryParse(rawP.toString());
              }
              final invDate = invData['created_time']?.toString();
              if (invDate != null && invDate.isNotEmpty) {
                dateStr = invDate;
              }
            }
          } catch (_) {}
        }

        if (payCurr == null || payPriceRaw == null || payPriceRaw <= 0) {
          continue;
        }

        // Unit conversion for satoshis / litoshis
        double cryptoAmount = payPriceRaw;
        if ((payCurr == 'BTC' || payCurr == 'LTC') && payPriceRaw > 1000) {
          cryptoAmount = payPriceRaw / 100000000.0;
        }

        // Determine category
        String category = 'Gasto';
        final lowerName = pname.toLowerCase();
        if (lowerName.contains('amazon')) {
          category = 'Compra Amazon';
        } else if (lowerName.contains('walmart') || lowerName.contains('cashi')) {
          category = 'Walmart / Cashi';
        } else if (lowerName.contains('movistar') || lowerName.contains('telcel')) {
          category = 'Recarga Móvil';
        } else if (lowerName.contains('credit')) {
          category = 'Store Credit';
        } else if (lowerName.contains('minecraft')) {
          category = 'Entretenimiento';
        }

        final description = '$pname ($pval $pcurr)';
        final parsedDate = DateTime.tryParse(dateStr)?.toUtc() ?? DateTime.now().toUtc();

        results.add({
          'exchange': 'Bitrefill',
          'currency': payCurr,
          'amount': cryptoAmount,
          'fee': 0.0,
          'date': parsedDate.toIso8601String(),
          'createdAt': parsedDate.millisecondsSinceEpoch,
          'txId': oid,
          'address': '',
          'description': description,
          'category': category,
        });

        final progressVal = 0.1 + ((i + 1) / total) * 0.9;
        onProgress?.call(progressVal, 'Procesando $pname...', results.length);
      }
    } catch (e) {
      debugPrint('Error fetching Bitrefill orders: $e');
    }

    return results;
  }
}
