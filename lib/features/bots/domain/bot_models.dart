class ResumenBot {
  final String idBot;
  final String simbolo;
  final String nombreEstrategia;
  final String estado;
  final bool simulacionDryRun;
  final double presupuestoAsignado;
  final double usdtDisponible;
  final int tramosActivos;
  final int maxTramos;
  final int maxTramosBase;
  final int tramosSueloExtra;
  final double takeProfitPct;
  final double trailingStopPct;
  final double pesoTendencia;
  final double umbralRsiT0;
  final double umbralRsiPanico;
  final List<double> pesosTramosBase;
  final List<double> pesosTramosSuelo;
  final double montoInvertidoUsdt;
  final double beneficioRealizadoUsdt;
  final double beneficioNoRealizadoUsdt;
  final double equidadActualUsdt;
  final String regimenMercado;
  final double? rsiActual;
  final bool recomendadaInyeccion;
  final String consejoInyeccion;
  final String? nombreSubcuenta;

  const ResumenBot({
    required this.idBot,
    required this.simbolo,
    required this.nombreEstrategia,
    required this.estado,
    required this.simulacionDryRun,
    required this.presupuestoAsignado,
    required this.usdtDisponible,
    required this.tramosActivos,
    this.maxTramos = 8,
    this.maxTramosBase = 5,
    this.tramosSueloExtra = 3,
    this.takeProfitPct = 4.5,
    this.trailingStopPct = 1.4,
    this.pesoTendencia = 0.70,
    this.umbralRsiT0 = 48.0,
    this.umbralRsiPanico = 28.0,
    this.pesosTramosBase = const [0.30, 0.25, 0.20, 0.15, 0.10],
    this.pesosTramosSuelo = const [0.40, 0.35, 0.25],
    required this.montoInvertidoUsdt,
    required this.beneficioRealizadoUsdt,
    this.beneficioNoRealizadoUsdt = 0.0,
    required this.equidadActualUsdt,
    this.regimenMercado = 'RANGE',
    this.rsiActual,
    this.recomendadaInyeccion = false,
    this.consejoInyeccion = '',
    this.nombreSubcuenta,
  });

  bool get estaActivo => estado.toUpperCase() == 'RUNNING';
  bool get estaPausado => estado.toUpperCase() == 'PAUSED';
  bool get estaDetenido =>
      estado.toUpperCase() == 'STOPPED' || (!estaActivo && !estaPausado);

  factory ResumenBot.fromJson(Map<String, dynamic> json) {
    final estrategia = (json['strategy_name'] ?? '').toString();
    final defaultMax =
        estrategia == 'BtcQuantumEvolutionRegimeStrategy' ? 8 : 5;
    final budget =
        ((json['allocated_budget'] ?? json['budget'] ?? 0.0) as num).toDouble();
    final avail =
        ((json['available_usdt'] ?? json['available_capital'] ?? 0.0) as num)
            .toDouble();
    final invested = ((json['invested_usdt'] ??
                json['invested_amount_usdt'] ??
                0.0) as num)
        .toDouble();

    List<double> parseWeights(dynamic raw, List<double> fallback) {
      if (raw is List && raw.isNotEmpty) {
        return raw.map((e) => (e as num).toDouble()).toList();
      }
      return fallback;
    }

    return ResumenBot(
      idBot: (json['bot_id'] ?? '').toString(),
      simbolo: (json['symbol'] ?? '').toString(),
      nombreEstrategia: estrategia,
      estado: (json['status'] ?? 'STOPPED').toString(),
      simulacionDryRun: json['dry_run'] ?? true,
      presupuestoAsignado: budget,
      usdtDisponible: avail,
      tramosActivos: ((json['active_tranches'] ??
              json['active_tranches_count'] ??
              0) as num)
          .toInt(),
      maxTramos: ((json['max_tranches'] ?? defaultMax) as num).toInt(),
      maxTramosBase: ((json['base_max_tranches'] ?? 5) as num).toInt(),
      tramosSueloExtra: ((json['extra_floor_tranches'] ?? 3) as num).toInt(),
      takeProfitPct: ((json['take_profit_pct'] ?? 4.5) as num).toDouble(),
      trailingStopPct: ((json['trailing_stop_pct'] ?? 1.4) as num).toDouble(),
      pesoTendencia: ((json['trend_weight'] ?? 0.70) as num).toDouble(),
      umbralRsiT0: ((json['t0_rsi_threshold'] ?? 48.0) as num).toDouble(),
      umbralRsiPanico:
          ((json['panic_rsi_threshold'] ?? 28.0) as num).toDouble(),
      pesosTramosBase: parseWeights(
        json['base_tranche_weights'],
        const [0.30, 0.25, 0.20, 0.15, 0.10],
      ),
      pesosTramosSuelo: parseWeights(
        json['floor_tranche_weights'],
        const [0.40, 0.35, 0.25],
      ),
      montoInvertidoUsdt: invested,
      beneficioRealizadoUsdt: ((json['realized_pnl_usdt'] ??
                  json['total_realized_profit_usdt'] ??
                  0.0) as num)
          .toDouble(),
      beneficioNoRealizadoUsdt:
          ((json['unrealized_pnl_usdt'] ?? 0.0) as num).toDouble(),
      equidadActualUsdt:
          ((json['current_equity_usdt'] ?? (avail + invested)) as num)
              .toDouble(),
      regimenMercado: (json['current_market_regime'] ?? 'RANGE').toString(),
      rsiActual: json['current_rsi'] != null
          ? ((json['current_rsi'] as num).toDouble())
          : null,
      recomendadaInyeccion: (json['injection_recommended'] ??
          json['capital_injection_recommended'] ??
          false) as bool,
      consejoInyeccion: (json['injection_advice'] ??
              json['capital_injection_advice'] ??
              '')
          .toString(),
      nombreSubcuenta: json['subaccount_name'] as String?,
    );
  }
}

class ConfiguracionEstrategiaBot {
  final String id;
  final String nombreEstrategia;
  final String nombre;
  final String descripcion;
  final bool esRecomendada;
  final bool esSistema;
  final double takeProfitPct;
  final double trailingStopPct;
  final double pesoTendencia;
  final int maxTramosBase;
  final int tramosSueloExtra;
  final List<double> pesosTramosBase;
  final List<double> pesosTramosSuelo;
  final double umbralRsiT0;
  final double umbralRsiPanico;
  final double atrMultiplier;
  final bool interesCompuesto;

  const ConfiguracionEstrategiaBot({
    required this.id,
    required this.nombreEstrategia,
    required this.nombre,
    this.descripcion = '',
    this.esRecomendada = false,
    this.esSistema = false,
    required this.takeProfitPct,
    required this.trailingStopPct,
    required this.pesoTendencia,
    this.maxTramosBase = 5,
    this.tramosSueloExtra = 3,
    this.pesosTramosBase = const [0.30, 0.25, 0.20, 0.15, 0.10],
    this.pesosTramosSuelo = const [0.40, 0.35, 0.25],
    this.umbralRsiT0 = 48.0,
    this.umbralRsiPanico = 28.0,
    this.atrMultiplier = 1.5,
    this.interesCompuesto = true,
  });

  int get maxTramosTotal => maxTramosBase + tramosSueloExtra;

  List<double> get todosLosPesos => [
        ...pesosTramosBase.take(maxTramosBase),
        ...pesosTramosSuelo.take(tramosSueloExtra),
      ];

  /// Configuración Recomendada oficial e inviolable validada en 9 años (2017-2026)
  static const ConfiguracionEstrategiaBot recomendadaQuantumEvolution =
      ConfiguracionEstrategiaBot(
    id: 'recommended_btc_quantum_evolution',
    nombreEstrategia: 'BtcQuantumEvolutionRegimeStrategy',
    nombre: 'Configuración Recomendada',
    descripcion:
        'Calibración ganadora oficial (+4,387% en 9 años): TP 4.5%, Trailing Stop 1.4%, Tendencia 70%, 5 Tramos Base [30/25/20/15/10%] + 3 Suelo [40/35/25%], RSI T0 48.0, RSI Pánico 28.0.',
    esRecomendada: true,
    esSistema: true,
    takeProfitPct: 4.5,
    trailingStopPct: 1.4,
    pesoTendencia: 0.70,
    maxTramosBase: 5,
    tramosSueloExtra: 3,
    pesosTramosBase: [0.30, 0.25, 0.20, 0.15, 0.10],
    pesosTramosSuelo: [0.40, 0.35, 0.25],
    umbralRsiT0: 48.0,
    umbralRsiPanico: 28.0,
    atrMultiplier: 1.5,
    interesCompuesto: true,
  );

  factory ConfiguracionEstrategiaBot.fromJson(Map<String, dynamic> json) {
    final params =
        (json['params'] as Map<String, dynamic>?) ?? <String, dynamic>{};

    List<double> parseWeights(dynamic raw, List<double> fallback) {
      if (raw is List && raw.isNotEmpty) {
        return raw.map((e) => (e as num).toDouble()).toList();
      }
      return fallback;
    }

    return ConfiguracionEstrategiaBot(
      id: (json['id'] ?? '').toString(),
      nombreEstrategia:
          (json['strategy_name'] ?? 'BtcQuantumEvolutionRegimeStrategy')
              .toString(),
      nombre: (json['name'] ?? 'Configuración').toString(),
      descripcion: (json['description'] ?? '').toString(),
      esRecomendada: json['is_recommended'] == true,
      esSistema: json['is_system'] == true,
      takeProfitPct: ((params['take_profit_pct'] ?? 4.5) as num).toDouble(),
      trailingStopPct: ((params['trailing_stop_pct'] ?? 1.4) as num).toDouble(),
      pesoTendencia: ((params['trend_weight'] ?? 0.70) as num).toDouble(),
      maxTramosBase: ((params['base_max_tranches'] ?? 5) as num).toInt(),
      tramosSueloExtra: ((params['extra_floor_tranches'] ?? 3) as num).toInt(),
      pesosTramosBase: parseWeights(
        params['base_tranche_weights'],
        const [0.30, 0.25, 0.20, 0.15, 0.10],
      ),
      pesosTramosSuelo: parseWeights(
        params['floor_tranche_weights'],
        const [0.40, 0.35, 0.25],
      ),
      umbralRsiT0: ((params['t0_rsi_threshold'] ?? 48.0) as num).toDouble(),
      umbralRsiPanico:
          ((params['panic_rsi_threshold'] ?? 28.0) as num).toDouble(),
      atrMultiplier: ((params['atr_multiplier'] ?? 1.5) as num).toDouble(),
      interesCompuesto: params['enable_compounding'] ?? true,
    );
  }
}

class TramoBot {
  final int id;
  final String idBot;
  final int indiceTramo;
  final double presupuestoAsignado;
  final double precioCompra;
  final double cantidadMoneda;
  final double precioMaximoAlcanzado;
  final double precioObjetivoVenta;
  final String estado;
  final DateTime? fechaApertura;

  const TramoBot({
    required this.id,
    required this.idBot,
    required this.indiceTramo,
    required this.presupuestoAsignado,
    required this.precioCompra,
    required this.cantidadMoneda,
    required this.precioMaximoAlcanzado,
    required this.precioObjetivoVenta,
    required this.estado,
    this.fechaApertura,
  });

  bool get esActivo =>
      estado.toUpperCase() == 'ACTIVO' || estado.toUpperCase() == 'ACTIVE';

  factory TramoBot.fromJson(Map<String, dynamic> json) {
    final buyPrice = ((json['buy_price'] ?? 0.0) as num).toDouble();
    final coinAmount =
        ((json['coin_amount'] ?? json['amount'] ?? 0.0) as num).toDouble();
    DateTime? openedAt;
    if (json['opened_at'] != null) {
      openedAt = DateTime.tryParse(json['opened_at'].toString());
    } else if (json['buy_timestamp'] != null && json['buy_timestamp'] is num) {
      openedAt = DateTime.fromMillisecondsSinceEpoch(
        (json['buy_timestamp'] as num).toInt(),
      );
    }
    return TramoBot(
      id: ((json['id'] ?? 0) as num).toInt(),
      idBot: (json['bot_id'] ?? '').toString(),
      indiceTramo: ((json['tranche_index'] ?? 1) as num).toInt(),
      presupuestoAsignado: ((json['allocated_budget'] ??
                  (buyPrice * coinAmount)) as num)
          .toDouble(),
      precioCompra: buyPrice,
      cantidadMoneda: coinAmount,
      precioMaximoAlcanzado:
          ((json['highest_price'] ?? buyPrice) as num).toDouble(),
      precioObjetivoVenta: ((json['target_sell_price'] ??
                  json['sell_price'] ??
                  (buyPrice * 1.025)) as num)
          .toDouble(),
      estado: (json['status'] ?? '').toString(),
      fechaApertura: openedAt,
    );
  }
}

class MetricasFlotaBots {
  final int totalBots;
  final int botsActivos;
  final double presupuestoTotalUsdt;
  final double disponibleTotalUsdt;
  final double invertidoTotalUsdt;
  final double beneficioRealizadoTotalUsdt;
  final double equidadTotalUsdt;
  final double flujoCajaTotalUsdt;
  final int operacionesCerradas;
  final int operacionesGanadoras;
  final double tasaAciertoPct;

  const MetricasFlotaBots({
    required this.totalBots,
    required this.botsActivos,
    required this.presupuestoTotalUsdt,
    required this.disponibleTotalUsdt,
    required this.invertidoTotalUsdt,
    required this.beneficioRealizadoTotalUsdt,
    required this.equidadTotalUsdt,
    required this.flujoCajaTotalUsdt,
    required this.operacionesCerradas,
    required this.operacionesGanadoras,
    required this.tasaAciertoPct,
  });

  factory MetricasFlotaBots.fromJson(Map<String, dynamic> json) {
    return MetricasFlotaBots(
      totalBots: ((json['total_bots'] ?? 0) as num).toInt(),
      botsActivos: ((json['running_bots'] ?? json['active_bots_count'] ?? 0)
              as num)
          .toInt(),
      presupuestoTotalUsdt:
          ((json['total_allocated_usdt'] ?? 0.0) as num).toDouble(),
      disponibleTotalUsdt:
          ((json['total_available_usdt'] ?? 0.0) as num).toDouble(),
      invertidoTotalUsdt: ((json['total_invested_usdt'] ??
                  json['total_open_positions_usdt'] ??
                  0.0) as num)
          .toDouble(),
      beneficioRealizadoTotalUsdt: ((json['total_realized_pnl_usdt'] ??
                  json['total_realized_profit_usdt'] ??
                  0.0) as num)
          .toDouble(),
      equidadTotalUsdt: ((json['total_equity_usdt'] ??
                  json['total_portfolio_equity_usdt'] ??
                  0.0) as num)
          .toDouble(),
      flujoCajaTotalUsdt: ((json['total_cashflow_usdt'] ??
                  json['total_cash_flow_extracted_usdt'] ??
                  0.0) as num)
          .toDouble(),
      operacionesCerradas: ((json['closed_trades'] ??
              json['total_closed_trades'] ??
              0) as num)
          .toInt(),
      operacionesGanadoras: ((json['winning_trades'] ?? 0) as num).toInt(),
      tasaAciertoPct: ((json['win_rate_pct'] ??
                  json['system_win_rate_pct'] ??
                  0.0) as num)
          .toDouble(),
    );
  }
}

class AjustesMotorBots {
  final String discordWebhookUrl;
  final bool notificarCompras;
  final bool notificarVentas;
  final bool notificarAlertasMeseta;

  const AjustesMotorBots({
    required this.discordWebhookUrl,
    required this.notificarCompras,
    required this.notificarVentas,
    required this.notificarAlertasMeseta,
  });

  factory AjustesMotorBots.fromJson(Map<String, dynamic> json) {
    return AjustesMotorBots(
      discordWebhookUrl: (json['discord_webhook_url'] ?? '').toString(),
      notificarCompras: json['notify_buys'] ?? true,
      notificarVentas: json['notify_sells'] ?? true,
      notificarAlertasMeseta: json['notify_plateau'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'discord_webhook_url': discordWebhookUrl,
      'notify_buys': notificarCompras,
      'notify_sells': notificarVentas,
      'notify_plateau': notificarAlertasMeseta,
    };
  }
}

class OrdenEjecutadaBot {
  final String id;
  final String botId;
  final String simbolo;
  final String side;
  final String tipoOrden;
  final double precio;
  final double cantidad;
  final double comision;
  final String estado;
  final DateTime fechaCreacion;

  const OrdenEjecutadaBot({
    required this.id,
    required this.botId,
    required this.simbolo,
    required this.side,
    required this.tipoOrden,
    required this.precio,
    required this.cantidad,
    required this.comision,
    required this.estado,
    required this.fechaCreacion,
  });

  factory OrdenEjecutadaBot.fromJson(Map<String, dynamic> json) {
    final rawTs = json['created_at'];
    DateTime dt;
    if (rawTs is num) {
      dt = DateTime.fromMillisecondsSinceEpoch(rawTs.toInt());
    } else {
      dt = DateTime.tryParse(rawTs?.toString() ?? '') ?? DateTime.now();
    }
    return OrdenEjecutadaBot(
      id: (json['id'] ?? '').toString(),
      botId: (json['bot_id'] ?? '').toString(),
      simbolo: (json['symbol'] ?? '').toString(),
      side: (json['side'] ?? 'BUY').toString().toUpperCase(),
      tipoOrden: (json['order_type'] ?? 'LIMIT').toString(),
      precio: ((json['price'] ?? 0.0) as num).toDouble(),
      cantidad: ((json['amount'] ?? 0.0) as num).toDouble(),
      comision: ((json['fee'] ?? 0.0) as num).toDouble(),
      estado: (json['status'] ?? 'CLOSED').toString(),
      fechaCreacion: dt,
    );
  }
}

class EventoAuditoriaBot {
  final int id;
  final String botId;
  final String tipoEvento;
  final String detalles;
  final DateTime fecha;

  const EventoAuditoriaBot({
    required this.id,
    required this.botId,
    required this.tipoEvento,
    required this.detalles,
    required this.fecha,
  });

  factory EventoAuditoriaBot.fromJson(Map<String, dynamic> json) {
    final rawTs = json['timestamp'];
    DateTime dt;
    if (rawTs is num) {
      dt = DateTime.fromMillisecondsSinceEpoch(rawTs.toInt());
    } else {
      dt = DateTime.tryParse(rawTs?.toString() ?? '') ?? DateTime.now();
    }
    return EventoAuditoriaBot(
      id: ((json['id'] ?? 0) as num).toInt(),
      botId: (json['bot_id'] ?? '').toString(),
      tipoEvento: (json['event_type'] ?? '').toString(),
      detalles: (json['details'] ?? '').toString(),
      fecha: dt,
    );
  }
}


class RadarEntrySignal {
  final String status;
  final String trafficLight;
  final String title;
  final String recommendation;
  final bool isIdealEntry;
  final double historicalWinRate1yPct;
  final double historicalAvgReturn1yPct;

  const RadarEntrySignal({
    required this.status,
    required this.trafficLight,
    required this.title,
    required this.recommendation,
    required this.isIdealEntry,
    required this.historicalWinRate1yPct,
    required this.historicalAvgReturn1yPct,
  });

  factory RadarEntrySignal.fromJson(Map<String, dynamic> json) {
    return RadarEntrySignal(
      status: (json['status'] ?? 'NEUTRAL_RANGE').toString(),
      trafficLight: (json['traffic_light'] ?? 'YELLOW').toString(),
      title: (json['title'] ?? 'Régimen Normal').toString(),
      recommendation: (json['recommendation'] ?? '').toString(),
      isIdealEntry: json['is_ideal_entry'] == true,
      historicalWinRate1yPct:
          ((json['historical_win_rate_1y_pct'] ?? 0.0) as num).toDouble(),
      historicalAvgReturn1yPct:
          ((json['historical_avg_return_1y_pct'] ?? 0.0) as num).toDouble(),
    );
  }
}

class RadarExitSignal {
  final String status;
  final String trafficLight;
  final String title;
  final String recommendation;
  final bool isExitWarning;
  final String suggestedAction;

  const RadarExitSignal({
    required this.status,
    required this.trafficLight,
    required this.title,
    required this.recommendation,
    required this.isExitWarning,
    required this.suggestedAction,
  });

  factory RadarExitSignal.fromJson(Map<String, dynamic> json) {
    return RadarExitSignal(
      status: (json['status'] ?? 'HEALTHY_TREND').toString(),
      trafficLight: (json['traffic_light'] ?? 'GREEN').toString(),
      title: (json['title'] ?? 'Estructura Saludable').toString(),
      recommendation: (json['recommendation'] ?? '').toString(),
      isExitWarning: json['is_exit_warning'] == true,
      suggestedAction: (json['suggested_action'] ?? 'NONE').toString(),
    );
  }
}

class PiCycleMetrics {
  final double sma111d;
  final double sma350dx2;
  final double piRatio;
  final bool isTriggered;

  const PiCycleMetrics({
    required this.sma111d,
    required this.sma350dx2,
    required this.piRatio,
    required this.isTriggered,
  });

  factory PiCycleMetrics.fromJson(Map<String, dynamic> json) {
    return PiCycleMetrics(
      sma111d: ((json['sma_111d'] ?? 0.0) as num).toDouble(),
      sma350dx2: ((json['sma_350d_x2'] ?? 0.0) as num).toDouble(),
      piRatio: ((json['pi_ratio'] ?? 0.0) as num).toDouble(),
      isTriggered: json['is_triggered'] == true,
    );
  }
}

class MarketRadarData {
  final String symbol;
  final DateTime calculatedAt;
  final double currentPrice;
  final double athPrice;
  final double dailyEma200;
  final double dailyEma50;
  final double dailyRsi;
  final double distDailyEma200Pct;
  final double drawdownFromAthPct;
  final double daysAboveDailyEma200;
  final int daysSinceLastHalving;
  final RadarEntrySignal entryRadar;
  final RadarExitSignal exitRadar;
  final PiCycleMetrics piCycleMetrics;

  const MarketRadarData({
    required this.symbol,
    required this.calculatedAt,
    required this.currentPrice,
    required this.athPrice,
    required this.dailyEma200,
    required this.dailyEma50,
    required this.dailyRsi,
    required this.distDailyEma200Pct,
    required this.drawdownFromAthPct,
    required this.daysAboveDailyEma200,
    required this.daysSinceLastHalving,
    required this.entryRadar,
    required this.exitRadar,
    required this.piCycleMetrics,
  });

  factory MarketRadarData.fromJson(Map<String, dynamic> json) {
    return MarketRadarData(
      symbol: (json['symbol'] ?? 'BTC/USDT').toString(),
      calculatedAt: DateTime.tryParse(json['calculated_at']?.toString() ?? '') ??
          DateTime.now(),
      currentPrice: ((json['current_price'] ?? 0.0) as num).toDouble(),
      athPrice: ((json['ath_price'] ?? 0.0) as num).toDouble(),
      dailyEma200: ((json['daily_ema_200'] ?? 0.0) as num).toDouble(),
      dailyEma50: ((json['daily_ema_50'] ?? 0.0) as num).toDouble(),
      dailyRsi: ((json['daily_rsi'] ?? 50.0) as num).toDouble(),
      distDailyEma200Pct:
          ((json['dist_daily_ema_200_pct'] ?? 0.0) as num).toDouble(),
      drawdownFromAthPct:
          ((json['drawdown_from_ath_pct'] ?? 0.0) as num).toDouble(),
      daysAboveDailyEma200:
          ((json['days_above_daily_ema_200'] ?? 0.0) as num).toDouble(),
      daysSinceLastHalving:
          ((json['days_since_last_halving'] ?? 0) as num).toInt(),
      entryRadar: RadarEntrySignal.fromJson(
          json['entry_radar'] is Map ? json['entry_radar'] : {}),
      exitRadar: RadarExitSignal.fromJson(
          json['exit_radar'] is Map ? json['exit_radar'] : {}),
      piCycleMetrics: PiCycleMetrics.fromJson(
          json['pi_cycle_metrics'] is Map ? json['pi_cycle_metrics'] : {}),
    );
  }
}
