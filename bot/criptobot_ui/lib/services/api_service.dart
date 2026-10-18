import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bot_models.dart';

class ApiService {
  static const String _keyBaseUrl = 'criptobot_base_url';

  // Adaptive host configuration: Android emulator uses 10.0.2.2, Desktop uses 127.0.0.1
  static String baseUrl = (!kIsWeb && Platform.isAndroid)
      ? 'http://10.0.2.2:8000'
      : 'http://127.0.0.1:8000';

  static Future<void> inicializarHost() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUrl = prefs.getString(_keyBaseUrl);
      if (savedUrl != null && savedUrl.isNotEmpty) {
        baseUrl = savedUrl;
      }
    } catch (_) {}
  }

  static Future<void> configurarHost(String nuevoHost) async {
    baseUrl = nuevoHost;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyBaseUrl, nuevoHost);
    } catch (_) {}
  }

  static Future<MetricasGlobales?> obtenerMetricasGlobales() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/v1/metrics/overview'));
      if (res.statusCode == 200) {
        return MetricasGlobales.fromJson(jsonDecode(res.body));
      }
    } catch (e) {
      // Error de red / Tailscale
    }
    return null;
  }

  static Future<List<ResumenBot>> listarBots() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/v1/bots'));
      if (res.statusCode == 200) {
        final List<dynamic> lista = jsonDecode(res.body);
        return lista.map((item) => ResumenBot.fromJson(item)).toList();
      }
    } catch (e) {
      // Error de red / Tailscale
    }
    return [];
  }

  static Future<List<TramoModel>> obtenerTramos(String idBot) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/v1/bots/$idBot/tranches'));
      if (res.statusCode == 200) {
        final List<dynamic> lista = jsonDecode(res.body);
        return lista.map((item) => TramoModel.fromJson(item)).toList();
      }
    } catch (e) {
      // Error de red
    }
    return [];
  }

  static Future<bool> iniciarBot(String idBot) async {
    try {
      final res = await http.post(Uri.parse('$baseUrl/api/v1/bots/$idBot/start'));
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> detenerBot(String idBot) async {
    try {
      final res = await http.post(Uri.parse('$baseUrl/api/v1/bots/$idBot/stop'));
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> pausarBot(String idBot) async {
    try {
      final res = await http.post(Uri.parse('$baseUrl/api/v1/bots/$idBot/pause'));
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> reanudarBot(String idBot) async {
    try {
      final res = await http.post(Uri.parse('$baseUrl/api/v1/bots/$idBot/resume'));
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> depositarCapital(String idBot, double monto, {String motivo = 'Depósito manual'}) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/bots/$idBot/deposit'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'amount': monto, 'reason': motivo}),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> retirarCapital(String idBot, double monto, {String motivo = 'Retiro manual'}) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/bots/$idBot/withdraw'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'amount': monto, 'reason': motivo}),
      );
      return res.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> crearBot({
    required String botId,
    required String symbol,
    required String strategyName,
    required double budget,
    bool dryRun = true,
    double takeProfitPct = 4.5,
    double trailingStopPct = 1.4,
    int maxTranches = 8,
    String? subaccountName,
    String? apiKey,
    String? apiSecret,
    String? apiPassphrase,
  }) async {
    try {
      final Map<String, dynamic> body = {
        'bot_id': botId,
        'symbol': symbol,
        'strategy_name': strategyName,
        'budget': budget,
        'dry_run': dryRun,
        'take_profit_pct': takeProfitPct,
        'trailing_stop_pct': trailingStopPct,
        'max_tranches': maxTranches,
      };
      if (subaccountName != null && subaccountName.isNotEmpty) body['subaccount_name'] = subaccountName;
      if (apiKey != null && apiKey.isNotEmpty) body['api_key'] = apiKey;
      if (apiSecret != null && apiSecret.isNotEmpty) body['api_secret'] = apiSecret;
      if (apiPassphrase != null && apiPassphrase.isNotEmpty) body['api_passphrase'] = apiPassphrase;

      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/bots'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      return res.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> generarBotDePrueba({bool dryRun = true, double budget = 100.0}) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/bots/test?dry_run=$dryRun&budget=$budget'),
      );
      return res.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  static Future<AjustesSistema?> obtenerAjustesSistema() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/v1/system/settings'));
      if (res.statusCode == 200) {
        return AjustesSistema.fromJson(jsonDecode(res.body));
      }
    } catch (_) {}
    return null;
  }

  static Future<bool> actualizarAjustesSistema({
    String? discordWebhookUrl,
    bool? discordEnabled,
    String? telegramBotToken,
    String? telegramChatId,
    bool? telegramEnabled,
  }) async {
    try {
      final Map<String, dynamic> body = {};
      if (discordWebhookUrl != null) body['discord_webhook_url'] = discordWebhookUrl;
      if (discordEnabled != null) body['discord_enabled'] = discordEnabled;
      if (telegramBotToken != null) body['telegram_bot_token'] = telegramBotToken;
      if (telegramChatId != null) body['telegram_chat_id'] = telegramChatId;
      if (telegramEnabled != null) body['telegram_enabled'] = telegramEnabled;

      final res = await http.patch(
        Uri.parse('$baseUrl/api/v1/system/settings'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> probarNotificacion({String channel = 'discord'}) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/v1/system/notifications/test'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'channel': channel}),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

