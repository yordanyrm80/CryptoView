import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Cliente centralizado para comunicarse con el CryptoView Data Engine (Oracle Cloud + TimescaleDB)
class CloudApiService {
  static final CloudApiService instance = CloudApiService._init();
  CloudApiService._init();

  static const String baseUrl = 'https://129-146-110-196.sslip.io';
  static const String apiSecretToken = 'aa0d07ca7079caf19492d0fc4a762c593b3e02e205c669ae60de5cbbd66979c2';

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        'X-API-Key': apiSecretToken,
      };

  /// Obtiene velas históricas o agregadas desde TimescaleDB (`/api/v1/candles`).
  /// Si la moneda no tiene datos o el servidor no responde, devuelve `[]` para permitir fallback.
  Future<List<Map<String, dynamic>>> fetchCandles(
    String exchange,
    String symbol,
    String interval, {
    int limit = 1500,
    bool autoTrack = false,
    int? endTimeSec,
  }) async {
    try {
      final ex = exchange.trim().toLowerCase();
      final sym = Uri.encodeComponent(symbol.trim().toUpperCase());
      final tf = interval.trim().toLowerCase();
      final safeLimit = limit.clamp(1, 2000);

      String url = '$baseUrl/api/v1/candles?exchange=$ex&symbol=$sym&interval=$tf&limit=$safeLimit&auto_track=$autoTrack';
      if (endTimeSec != null) {
        final endIso = DateTime.fromMillisecondsSinceEpoch(endTimeSec * 1000, isUtc: true).toIso8601String();
        url += '&end_time=${Uri.encodeComponent(endIso)}';
      }
      final uri = Uri.parse(url);

      final response = await http.get(uri, headers: _authHeaders).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        if (data.isEmpty) return [];

        return data.map<Map<String, dynamic>>((item) {
          return {
            'time': (item['time'] as num).toInt(),
            'open': (item['open'] as num).toDouble(),
            'high': (item['high'] as num).toDouble(),
            'low': (item['low'] as num).toDouble(),
            'close': (item['close'] as num).toDouble(),
          };
        }).toList();
      }
    } catch (e) {
      debugPrint('[CloudApiService] Fallback a exchange directo para $symbol ($interval): $e');
    }
    return [];
  }

  /// Sincroniza y cifra las API Keys del usuario en la base de datos central (`POST /api/v1/keys`)
  Future<bool> saveExchangeApiKey({
    required String exchange,
    required String apiKey,
    required String apiSecret,
    String? apiPassphrase,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/keys');
      final response = await http
          .post(
            uri,
            headers: _authHeaders,
            body: json.encode({
              'exchange': exchange.trim().toLowerCase(),
              'api_key': apiKey.trim(),
              'api_secret': apiSecret.trim(),
              'api_passphrase': (apiPassphrase ?? '').trim(),
              'is_active': true,
            }),
          )
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('[CloudApiService] Error guardando API Key en servidor cloud: $e');
      return false;
    }
  }

  /// Desactiva las credenciales de un exchange en el servidor central (`DELETE /api/v1/keys/{exchange}`)
  Future<bool> deleteExchangeApiKey(String exchange) async {
    try {
      final ex = exchange.trim().toLowerCase();
      final uri = Uri.parse('$baseUrl/api/v1/keys/$ex');
      final response = await http
          .delete(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 10));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[CloudApiService] Error eliminando API Key en servidor cloud: $e');
      return false;
    }
  }

  /// Registra una moneda en `tracked_symbols` del servidor para ingestión 24/7 + backfill (`POST /api/v1/symbols`)
  Future<bool> addTrackedSymbol(String exchange, String symbol) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/symbols');
      final response = await http
          .post(
            uri,
            headers: _authHeaders,
            body: json.encode({
              'exchange': exchange.trim().toLowerCase(),
              'symbol': symbol.trim().toUpperCase(),
            }),
          )
          .timeout(const Duration(seconds: 8));

      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('[CloudApiService] Error activando seguimiento cloud para $symbol: $e');
      return false;
    }
  }

  /// Desactiva una moneda en `tracked_symbols` del servidor (`DELETE /api/v1/symbols`)
  Future<bool> removeTrackedSymbol(String exchange, String symbol) async {
    try {
      final ex = Uri.encodeComponent(exchange.trim().toLowerCase());
      final sym = Uri.encodeComponent(symbol.trim().toUpperCase());
      final uri = Uri.parse('$baseUrl/api/v1/symbols?exchange=$ex&symbol=$sym');
      final response = await http
          .delete(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 8));

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[CloudApiService] Error desactivando seguimiento cloud para $symbol: $e');
      return false;
    }
  }

  /// Sincroniza órdenes directamente desde el servidor Cloud conectándose al exchange (`POST /api/v1/trades/sync`)
  Future<Map<String, dynamic>> syncTrades(
    String exchange, {
    String? symbol,
    int days = 1,
  }) async {
    try {
      final ex = exchange.trim().toLowerCase();
      String url = '$baseUrl/api/v1/trades/sync?exchange=$ex&days=$days';
      if (symbol != null && symbol.trim().isNotEmpty) {
        url += '&symbol=${Uri.encodeComponent(symbol.trim().toUpperCase())}';
      }
      final uri = Uri.parse(url);
      final response = await http.post(uri, headers: _authHeaders).timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[CloudApiService] Error en syncTrades ($exchange, $symbol, days=$days): $e');
    }
    return {'status': 'error', 'new_trades_count': 0, 'new_trades': []};
  }

  /// Obtiene trades almacenados en la base de datos central (`GET /api/v1/trades`)
  Future<List<Map<String, dynamic>>> fetchTrades({
    String? exchange,
    String? symbol,
    bool onlyOpen = false,
    int limit = 100,
  }) async {
    try {
      String url = '$baseUrl/api/v1/trades?limit=$limit&only_open=$onlyOpen';
      if (exchange != null && exchange.isNotEmpty) {
        url += '&exchange=${exchange.trim().toLowerCase()}';
      }
      if (symbol != null && symbol.isNotEmpty) {
        url += '&symbol=${Uri.encodeComponent(symbol.trim().toUpperCase())}';
      }
      final uri = Uri.parse(url);
      final response = await http.get(uri, headers: _authHeaders).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('[CloudApiService] Error en fetchTrades: $e');
    }
    return [];
  }

  /// Obtiene los últimos precios en vivo de todas las monedas activas (`GET /api/v1/candles/tickers`)
  Future<List<Map<String, dynamic>>> fetchTickers() async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/candles/tickers');
      final response = await http.get(uri, headers: _authHeaders).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('[CloudApiService] Error en fetchTickers: $e');
    }
    return [];
  }

  /// Sincroniza retiros y gastos desde el exchange en el servidor Cloud (`POST /api/v1/withdrawals/sync`)
  Future<Map<String, dynamic>> syncWithdrawals(
    String exchange, {
    String? currency,
    int days = 30,
  }) async {
    try {
      final ex = exchange.trim().toLowerCase();
      String url = '$baseUrl/api/v1/withdrawals/sync?exchange=$ex&days=$days';
      if (currency != null && currency.isNotEmpty) {
        url += '&currency=${currency.trim().toUpperCase()}';
      }
      final uri = Uri.parse(url);
      final response = await http.post(uri, headers: _authHeaders).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[CloudApiService] Error en syncWithdrawals: $e');
    }
    return {'status': 'error', 'new_withdrawals_count': 0};
  }
}
