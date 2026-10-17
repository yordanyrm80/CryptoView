import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Cliente centralizado para comunicarse con el CryptoView Data Engine (Oracle Cloud + TimescaleDB)
class CloudApiService {
  static final CloudApiService instance = CloudApiService._init();
  CloudApiService._init();

  static const String baseUrl = 'http://129.146.110.196:8000';
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
}
