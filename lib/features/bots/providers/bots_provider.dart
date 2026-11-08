import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/services/cloud_api_service.dart';
import '../domain/bot_models.dart';

/// Proveedor de estado reactivo de la interfaz del módulo de Bots.
/// Delega el 100% de la comunicación de red al cliente único [CloudApiService.instance].
class BotsProvider extends ChangeNotifier {
  bool _isLoading = false;
  bool _isConnected = false;
  String? _lastError;
  DateTime? _lastSyncTime;

  MetricasFlotaBots? _metricas;
  MarketRadarData? _marketRadar;
  List<ResumenBot> _bots = [];
  final Map<String, List<TramoBot>> _tramosPorBot = {};
  AjustesMotorBots? _ajustes;
  List<ConfiguracionEstrategiaBot> _configuracionesEstrategia = [
    ConfiguracionEstrategiaBot.recomendadaQuantumEvolution,
  ];

  String _filtroEstado = 'TODOS'; // TODOS, RUNNING, PAUSED, STOPPED
  String _busqueda = '';
  Timer? _pollingTimer;

  String get baseUrl => CloudApiService.instance.baseUrl;
  bool get isLoading => _isLoading;
  bool get isConnected => _isConnected;
  String? get lastError => _lastError;
  DateTime? get lastSyncTime => _lastSyncTime;
  MetricasFlotaBots? get metricas => _metricas;
  MarketRadarData? get marketRadar => _marketRadar;
  List<ResumenBot> get todosLosBots => _bots;
  AjustesMotorBots? get ajustes => _ajustes;
  List<ConfiguracionEstrategiaBot> get configuracionesEstrategia =>
      _configuracionesEstrategia;
  String get filtroEstado => _filtroEstado;
  String get busqueda => _busqueda;

  List<ConfiguracionEstrategiaBot> configuracionesParaEstrategia(
    String nombreEstrategia,
  ) {
    final lista = _configuracionesEstrategia
        .where((c) => c.nombreEstrategia == nombreEstrategia)
        .toList();
    if (!lista.any((c) => c.esRecomendada)) {
      lista.insert(0, ConfiguracionEstrategiaBot.recomendadaQuantumEvolution);
    }
    return lista;
  }

  ConfiguracionEstrategiaBot obtenerConfiguracionRecomendada(
    String nombreEstrategia,
  ) {
    return configuracionesParaEstrategia(nombreEstrategia).firstWhere(
      (c) => c.esRecomendada,
      orElse: () => ConfiguracionEstrategiaBot.recomendadaQuantumEvolution,
    );
  }

  int get totalBotsCount => _bots.length;
  int get botsActivosCount => _bots.where((b) => b.estaActivo).length;
  int get botsPausadosCount => _bots.where((b) => b.estaPausado).length;
  int get botsDetenidosCount => _bots.where((b) => b.estaDetenido).length;

  List<ResumenBot> get botsFiltrados {
    return _bots.where((bot) {
      if (_filtroEstado == 'RUNNING' && !bot.estaActivo) return false;
      if (_filtroEstado == 'PAUSED' && !bot.estaPausado) return false;
      if (_filtroEstado == 'STOPPED' && !bot.estaDetenido) return false;

      if (_busqueda.trim().isNotEmpty) {
        final q = _busqueda.trim().toLowerCase();
        final matchId = bot.idBot.toLowerCase().contains(q);
        final matchSymbol = bot.simbolo.toLowerCase().contains(q);
        final matchStrat = bot.nombreEstrategia.toLowerCase().contains(q);
        final matchSub = (bot.nombreSubcuenta ?? '').toLowerCase().contains(q);
        if (!matchId && !matchSymbol && !matchStrat && !matchSub) return false;
      }
      return true;
    }).toList();
  }

  List<TramoBot> obtenerTramosDeBot(String idBot) {
    return _tramosPorBot[idBot] ?? const [];
  }

  BotsProvider() {
    _inicializar();
  }

  Future<void> _inicializar() async {
    // Carga inicial pasiva
    await cargarDatos(silencioso: true);
  }

  /// Inicia el temporizador de sondeo cada 15s cuando la vista de bots está activa
  void startPolling() {
    if (_pollingTimer != null && _pollingTimer!.isActive) return;
    cargarDatos(silencioso: true);
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      cargarDatos(silencioso: true);
    });
  }

  /// Pausa el sondeo para no consumir recursos ni red cuando el usuario navega a otra pantalla
  void stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }

  void setFiltroEstado(String nuevoFiltro) {
    if (_filtroEstado == nuevoFiltro) return;
    _filtroEstado = nuevoFiltro;
    notifyListeners();
  }

  void setBusqueda(String query) {
    if (_busqueda == query) return;
    _busqueda = query;
    notifyListeners();
  }

  Future<void> cargarDatos({bool silencioso = false}) async {
    if (!silencioso) {
      _isLoading = true;
      _lastError = null;
      notifyListeners();
    }

    try {
      final api = CloudApiService.instance;
      final results = await Future.wait([
        api.fetchBotsOverview(),
        api.fetchBots(),
        api.fetchStrategyConfigs(),
      ]);

      final rawMetricas = results[0] as Map<String, dynamic>?;
      final rawBots = results[1] as List<Map<String, dynamic>>?;
      final rawConfigs = results[2] as List<Map<String, dynamic>>;

      if (rawConfigs.isNotEmpty) {
        final parsed = rawConfigs
            .map((e) => ConfiguracionEstrategiaBot.fromJson(e))
            .toList();
        if (!parsed.any((c) => c.esRecomendada)) {
          parsed.insert(
              0, ConfiguracionEstrategiaBot.recomendadaQuantumEvolution);
        }
        _configuracionesEstrategia = parsed;
      }

      if (rawMetricas != null && rawBots != null) {
        _metricas = MetricasFlotaBots.fromJson(rawMetricas);
        final nuevosBots =
            rawBots.map((e) => ResumenBot.fromJson(e)).toList();

        for (final bot in nuevosBots) {
          final rawTramos = await api.fetchBotTranches(bot.idBot);
          _tramosPorBot[bot.idBot] =
              rawTramos.map((e) => TramoBot.fromJson(e)).toList();
        }

        _bots = nuevosBots;
        _isConnected = true;
        _lastError = null;
        _lastSyncTime = DateTime.now();
        try {
          final radarJson = await api.fetchMarketRadar(symbol: 'BTC/USDT');
          if (radarJson != null) {
            _marketRadar = MarketRadarData.fromJson(radarJson);
          }
        } catch (_) {}
      } else {
        _isConnected = false;
        _lastError =
            'El endpoint /api/v1/bots aún no está disponible en la API central ($baseUrl).';
      }
    } catch (e) {
      _isConnected = false;
      _lastError =
          'Sin respuesta de los endpoints de bots en la API central ($baseUrl).';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<AjustesMotorBots?> obtenerAjustesSistema() async {
    final json = await CloudApiService.instance.fetchBotNotificationSettings();
    if (json != null) {
      _ajustes = AjustesMotorBots.fromJson(json);
      notifyListeners();
      return _ajustes;
    }
    return null;
  }

  Future<bool> guardarAjustesSistema(AjustesMotorBots nuevosAjustes) async {
    final ok = await CloudApiService.instance
        .updateBotNotificationSettings(nuevosAjustes.toJson());
    if (ok) {
      _ajustes = nuevosAjustes;
      notifyListeners();
    }
    return ok;
  }

  Future<bool> probarWebhookDiscord() async {
    return await CloudApiService.instance.testBotNotificationSettings();
  }

  Future<bool> iniciarBot(String idBot) async {
    final ok = await CloudApiService.instance.postBotAction(idBot, 'start');
    if (ok) await cargarDatos(silencioso: true);
    return ok;
  }

  Future<bool> detenerBot(String idBot) async {
    final ok = await CloudApiService.instance.postBotAction(idBot, 'stop');
    if (ok) await cargarDatos(silencioso: true);
    return ok;
  }

  Future<bool> pausarBot(String idBot) async {
    final ok = await CloudApiService.instance.postBotAction(idBot, 'pause');
    if (ok) await cargarDatos(silencioso: true);
    return ok;
  }

  Future<bool> reanudarBot(String idBot) async {
    final ok = await CloudApiService.instance.postBotAction(idBot, 'resume');
    if (ok) await cargarDatos(silencioso: true);
    return ok;
  }

  Future<bool> depositarCapital(
    String idBot,
    double montoUsdt, {
    String motivo = 'Inyección operativa de capital',
  }) async {
    final ok = await CloudApiService.instance.postBotCapitalTransaction(
      idBot,
      'deposit',
      amountUsdt: montoUsdt,
      reason: motivo,
    );
    if (ok) await cargarDatos(silencioso: true);
    return ok;
  }

  Future<bool> retirarCapital(
    String idBot,
    double montoUsdt, {
    String motivo = 'Retiro de utilidades a tesorería',
  }) async {
    final ok = await CloudApiService.instance.postBotCapitalTransaction(
      idBot,
      'withdraw',
      amountUsdt: montoUsdt,
      reason: motivo,
    );
    if (ok) await cargarDatos(silencioso: true);
    return ok;
  }

  Future<List<OrdenEjecutadaBot>> obtenerOrdenesBot(String idBot) async {
    final raw = await CloudApiService.instance.fetchBotOrders(idBot);
    return raw.map((e) => OrdenEjecutadaBot.fromJson(e)).toList();
  }

  Future<List<EventoAuditoriaBot>> obtenerEventosBot(String idBot) async {
    final raw = await CloudApiService.instance.fetchBotEvents(idBot);
    return raw.map((e) => EventoAuditoriaBot.fromJson(e)).toList();
  }

  Future<bool> reiniciarSimulacion(String idBot) async {
    final ok = await CloudApiService.instance.resetBotSimulation(idBot);
    if (ok) await cargarDatos(silencioso: true);
    return ok;
  }

  Future<bool> eliminarBot(String idBot) async {
    final ok = await CloudApiService.instance.deleteBot(idBot);
    if (ok) await cargarDatos(silencioso: true);
    return ok;
  }

  Future<Map<String, dynamic>> crearBot({
    required String botId,
    required String symbol,
    required String strategyName,
    required double budget,
    required bool dryRun,
    required double takeProfitPct,
    required double trailingStopPct,
    double trendWeight = 0.70,
    int baseMaxTranches = 5,
    int extraFloorTranches = 3,
    List<double>? baseTrancheWeights,
    List<double>? floorTrancheWeights,
    double t0RsiThreshold = 48.0,
    double panicRsiThreshold = 28.0,
    String? subaccountName,
    String? apiKey,
    String? apiSecret,
    String? apiPassphrase,
  }) async {
    final bw = baseTrancheWeights ?? const [0.30, 0.25, 0.20, 0.15, 0.10];
    final fw = floorTrancheWeights ?? const [0.40, 0.35, 0.25];
    final res = await CloudApiService.instance.createBot({
      'bot_id': botId,
      'symbol': symbol,
      'strategy_name': strategyName,
      'budget': budget,
      'dry_run': dryRun,
      'take_profit_pct': takeProfitPct,
      'trailing_stop_pct': trailingStopPct,
      'trend_weight': trendWeight,
      'base_max_tranches': baseMaxTranches,
      'extra_floor_tranches': extraFloorTranches,
      'max_tranches': baseMaxTranches + extraFloorTranches,
      'base_tranche_weights': bw,
      'floor_tranche_weights': fw,
      'tranche_weights': [...bw.take(baseMaxTranches), ...fw.take(extraFloorTranches)],
      't0_rsi_threshold': t0RsiThreshold,
      'panic_rsi_threshold': panicRsiThreshold,
      'subaccount_name': subaccountName,
      'api_key': apiKey,
      'api_secret': apiSecret,
      'api_passphrase': apiPassphrase,
    });
    if (res['ok'] == true) {
      await cargarDatos(silencioso: true);
    }
    return res;
  }

  Future<Map<String, dynamic>> guardarConfiguracionEstrategia({
    required String strategyName,
    required String name,
    String description = '',
    required double takeProfitPct,
    required double trailingStopPct,
    required double trendWeight,
    required int baseMaxTranches,
    required int extraFloorTranches,
    required List<double> baseTrancheWeights,
    required List<double> floorTrancheWeights,
    required double t0RsiThreshold,
    required double panicRsiThreshold,
  }) async {
    final res = await CloudApiService.instance.saveStrategyConfig({
      'strategy_name': strategyName,
      'name': name,
      'description': description,
      'take_profit_pct': takeProfitPct,
      'trailing_stop_pct': trailingStopPct,
      'trend_weight': trendWeight,
      'base_max_tranches': baseMaxTranches,
      'extra_floor_tranches': extraFloorTranches,
      'base_tranche_weights': baseTrancheWeights,
      'floor_tranche_weights': floorTrancheWeights,
      't0_rsi_threshold': t0RsiThreshold,
      'panic_rsi_threshold': panicRsiThreshold,
    });
    if (res['ok'] == true) {
      await cargarDatos(silencioso: true);
    }
    return res;
  }

  Future<bool> eliminarConfiguracionEstrategia(String configId) async {
    final ok = await CloudApiService.instance.deleteStrategyConfig(configId);
    if (ok) {
      await cargarDatos(silencioso: true);
    }
    return ok;
  }

  Future<Map<String, dynamic>> actualizarConfiguracionBot({
    required String botId,
    required double takeProfitPct,
    required double trailingStopPct,
    required double trendWeight,
    required int baseMaxTranches,
    required int extraFloorTranches,
    required List<double> baseTrancheWeights,
    required List<double> floorTrancheWeights,
    required double t0RsiThreshold,
    required double panicRsiThreshold,
  }) async {
    final res = await CloudApiService.instance.updateBotStrategyConfig(botId, {
      'take_profit_pct': takeProfitPct,
      'trailing_stop_pct': trailingStopPct,
      'trend_weight': trendWeight,
      'base_max_tranches': baseMaxTranches,
      'extra_floor_tranches': extraFloorTranches,
      'max_tranches': baseMaxTranches + extraFloorTranches,
      'base_tranche_weights': baseTrancheWeights,
      'floor_tranche_weights': floorTrancheWeights,
      'tranche_weights': [
        ...baseTrancheWeights.take(baseMaxTranches),
        ...floorTrancheWeights.take(extraFloorTranches),
      ],
      't0_rsi_threshold': t0RsiThreshold,
      'panic_rsi_threshold': panicRsiThreshold,
    });
    if (res['ok'] == true) {
      await cargarDatos(silencioso: true);
    }
    return res;
  }

  Future<void> actualizarRadarMercado({String symbol = 'BTC/USDT'}) async {
    try {
      final radarJson = await CloudApiService.instance.fetchMarketRadar(symbol: symbol);
      if (radarJson != null) {
        _marketRadar = MarketRadarData.fromJson(radarJson);
        notifyListeners();
      }
    } catch (_) {}
  }
}
