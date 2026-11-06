import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Cliente centralizado para comunicarse con el CryptoView Data Engine (Oracle Cloud + TimescaleDB)
class CloudApiService {
  static final CloudApiService instance = CloudApiService._init();
  CloudApiService._init();

  String _baseUrl = const String.fromEnvironment(
    'CLOUD_API_URL',
    defaultValue: 'https://129-146-110-196.sslip.io',
  );
  String _apiSecretToken = const String.fromEnvironment(
    'API_SECRET_TOKEN',
    defaultValue: 'aa0d07ca7079caf19492d0fc4a762c593b3e02e205c669ae60de5cbbd66979c2',
  );

  String get baseUrl => _baseUrl;
  String get apiSecretToken => _apiSecretToken;

  /// Actualiza dinámicamente la URL base y el token secreto de la API Cloud
  void updateCredentials({required String baseUrl, required String apiSecretToken}) {
    if (baseUrl.trim().isNotEmpty) {
      _baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    }
    if (apiSecretToken.trim().isNotEmpty) {
      _apiSecretToken = apiSecretToken.trim();
    }
  }

  Map<String, String> get _authHeaders => {
        'Content-Type': 'application/json',
        'X-API-Key': _apiSecretToken,
      };

  /// Realiza un chequeo de salud contra /api/v1/health usando las credenciales configuradas o de prueba
  Future<Map<String, dynamic>> checkHealth({String? testUrl, String? testToken}) async {
    try {
      final targetUrl = (testUrl != null && testUrl.trim().isNotEmpty)
          ? testUrl.trim().replaceAll(RegExp(r'/+$'), '')
          : _baseUrl;
      final targetToken = (testToken != null && testToken.trim().isNotEmpty)
          ? testToken.trim()
          : _apiSecretToken;

      final uri = Uri.parse('$targetUrl/api/v1/health');
      final response = await http.get(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': targetToken,
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        data['http_code'] = 200;
        return data;
      } else {
        return {
          'status': 'error',
          'http_code': response.statusCode,
          'message': response.body,
        };
      }
    } catch (e) {
      return {
        'status': 'error',
        'http_code': 0,
        'message': e.toString(),
      };
    }
  }

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

  // ===========================================================================
  // ENDPOINTS CENTRALIZADOS DE LA FLOTA DE BOTS (/api/v1/bots)
  // ===========================================================================

  /// Obtiene las métricas globales consolidadas de la flota de bots (`GET /api/v1/bots/metrics/overview`)
  Future<Map<String, dynamic>?> fetchBotsOverview() async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/bots/metrics/overview');
      final response = await http
          .get(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[CloudApiService] Error en fetchBotsOverview: $e');
    }
    return null;
  }

  /// Obtiene el listado completo de bots registrados en PostgreSQL (`GET /api/v1/bots`)
  Future<List<Map<String, dynamic>>?> fetchBots() async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/bots');
      final response = await http
          .get(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('[CloudApiService] Error en fetchBots: $e');
    }
    return null;
  }

  /// Obtiene los tramos (posiciones escalonadas) de un bot específico (`GET /api/v1/bots/{bot_id}/tranches`)
  Future<List<Map<String, dynamic>>> fetchBotTranches(String botId) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/bots/$botId/tranches');
      final response = await http
          .get(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('[CloudApiService] Error en fetchBotTranches ($botId): $e');
    }
    return [];
  }

  /// Obtiene las preferencias de notificaciones de la flota (`GET /api/v1/bots/settings/notifications`)
  Future<Map<String, dynamic>?> fetchBotNotificationSettings() async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/bots/settings/notifications');
      final response = await http
          .get(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[CloudApiService] Error en fetchBotNotificationSettings: $e');
    }
    return null;
  }

  /// Actualiza las preferencias de notificaciones de la flota (`PUT /api/v1/bots/settings/notifications`)
  Future<bool> updateBotNotificationSettings(
    Map<String, dynamic> payload,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/bots/settings/notifications');
      final response = await http
          .put(
            uri,
            headers: _authHeaders,
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 6));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[CloudApiService] Error en updateBotNotificationSettings: $e');
      return false;
    }
  }

  /// Envía un mensaje de prueba al Webhook de Discord (`POST /api/v1/bots/settings/notifications/test`)
  Future<bool> testBotNotificationSettings() async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/bots/settings/notifications/test');
      final response = await http
          .post(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[CloudApiService] Error en testBotNotificationSettings: $e');
      return false;
    }
  }

  /// Ejecuta una transición de estado sobre un bot (`start`, `pause`, `resume`, `stop`)
  Future<bool> postBotAction(String botId, String action) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/bots/$botId/$action');
      final response = await http
          .post(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 6));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[CloudApiService] Error en postBotAction ($botId/$action): $e');
      return false;
    }
  }

  /// Obtiene la lista de órdenes ejecutadas por el bot (`GET /api/v1/bots/$botId/orders`)
  Future<List<Map<String, dynamic>>> fetchBotOrders(String botId) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/bots/$botId/orders');
      final response = await http
          .get(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('[CloudApiService] Error en fetchBotOrders ($botId): $e');
    }
    return [];
  }

  /// Obtiene la bitácora de eventos y auditoría del bot (`GET /api/v1/bots/$botId/events`)
  Future<List<Map<String, dynamic>>> fetchBotEvents(String botId) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/bots/$botId/events');
      final response = await http
          .get(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('[CloudApiService] Error en fetchBotEvents ($botId): $e');
    }
    return [];
  }

  /// Reinicia desde cero un bot de simulación (`POST /api/v1/bots/$botId/reset-simulation`)
  Future<bool> resetBotSimulation(String botId) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/bots/$botId/reset-simulation');
      final response = await http
          .post(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[CloudApiService] Error en resetBotSimulation ($botId): $e');
      return false;
    }
  }

  /// Elimina un bot detenido y sus registros asociados (`DELETE /api/v1/bots/$botId`)
  Future<bool> deleteBot(String botId) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/bots/$botId');
      final response = await http
          .delete(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[CloudApiService] Error en deleteBot ($botId): $e');
      return false;
    }
  }

  /// Registra una inyección (`deposit`) o retiro (`withdraw`) de capital en un bot
  Future<bool> postBotCapitalTransaction(
    String botId,
    String transactionType, {
    required double amountUsdt,
    required String reason,
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/bots/$botId/$transactionType');
      final response = await http
          .post(
            uri,
            headers: _authHeaders,
            body: json.encode({
              'amount_usdt': amountUsdt,
              'reason': reason,
              'notes': reason,
            }),
          )
          .timeout(const Duration(seconds: 8));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint(
          '[CloudApiService] Error en postBotCapitalTransaction ($botId/$transactionType): $e');
      return false;
    }
  }

  /// Registra una nueva instancia de bot en la flota (`POST /api/v1/bots`)
  Future<Map<String, dynamic>> createBot(Map<String, dynamic> payload) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/bots');
      final response = await http
          .post(
            uri,
            headers: _authHeaders,
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 200 || response.statusCode == 201) {
        return {
          'ok': true,
          'message': 'Instancia creada y registrada correctamente.',
        };
      }
      try {
        final err = json.decode(response.body) as Map<String, dynamic>;
        return {
          'ok': false,
          'message':
              (err['detail'] ?? 'Error al registrar el bot (${response.statusCode}).')
                  .toString(),
        };
      } catch (_) {
        return {
          'ok': false,
          'message': 'El servidor rechazó la solicitud (${response.statusCode}).',
        };
      }
    } catch (e) {
      debugPrint('[CloudApiService] Error en createBot: $e');
      return {
        'ok': false,
        'message': 'Sin respuesta del servidor central ($baseUrl).',
      };
    }
  }

  /// Obtiene las configuraciones guardadas de estrategias (`GET /api/v1/bots/strategies/configs`)
  Future<List<Map<String, dynamic>>> fetchStrategyConfigs({
    String? strategyName,
  }) async {
    try {
      final query = (strategyName != null && strategyName.trim().isNotEmpty)
          ? '?strategy_name=${Uri.encodeComponent(strategyName.trim())}'
          : '';
      final uri = Uri.parse('$baseUrl/api/v1/bots/strategies/configs$query');
      final response = await http
          .get(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      }
    } catch (e) {
      debugPrint('[CloudApiService] Error en fetchStrategyConfigs: $e');
    }
    return [];
  }

  /// Guarda una configuración personalizada de estrategia (`POST /api/v1/bots/strategies/configs`)
  Future<Map<String, dynamic>> saveStrategyConfig(
    Map<String, dynamic> payload,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/bots/strategies/configs');
      final response = await http
          .post(
            uri,
            headers: _authHeaders,
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return {
          'ok': true,
          'data': data,
          'message': 'Configuración guardada correctamente.',
        };
      }
      try {
        final err = json.decode(response.body) as Map<String, dynamic>;
        return {
          'ok': false,
          'message': (err['detail'] ?? 'No se pudo guardar la configuración.')
              .toString(),
        };
      } catch (_) {
        return {
          'ok': false,
          'message': 'Error del servidor (${response.statusCode}).',
        };
      }
    } catch (e) {
      debugPrint('[CloudApiService] Error en saveStrategyConfig: $e');
      return {
        'ok': false,
        'message': 'Sin respuesta del servidor central ($baseUrl).',
      };
    }
  }

  /// Elimina una configuración personalizada de estrategia (`DELETE /api/v1/bots/strategies/configs/{id}`)
  Future<bool> deleteStrategyConfig(String configId) async {
    try {
      final uri =
          Uri.parse('$baseUrl/api/v1/bots/strategies/configs/$configId');
      final response = await http
          .delete(uri, headers: _authHeaders)
          .timeout(const Duration(seconds: 6));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[CloudApiService] Error en deleteStrategyConfig: $e');
      return false;
    }
  }

  /// Actualiza los parámetros de estrategia de un bot existente (`PUT /api/v1/bots/{bot_id}/config`)
  Future<Map<String, dynamic>> updateBotStrategyConfig(
    String botId,
    Map<String, dynamic> payload,
  ) async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/bots/$botId/config');
      final response = await http
          .put(
            uri,
            headers: _authHeaders,
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        return {
          'ok': true,
          'message': 'Parámetros del bot actualizados correctamente.',
        };
      }
      try {
        final err = json.decode(response.body) as Map<String, dynamic>;
        return {
          'ok': false,
          'message':
              (err['detail'] ?? 'Error al actualizar configuración.').toString(),
        };
      } catch (_) {
        return {
          'ok': false,
          'message': 'Error del servidor (${response.statusCode}).',
        };
      }
    } catch (e) {
      debugPrint('[CloudApiService] Error en updateBotStrategyConfig: $e');
      return {
        'ok': false,
        'message': 'Sin respuesta del servidor central ($baseUrl).',
      };
    }
  }
}
