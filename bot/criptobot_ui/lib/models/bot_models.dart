class ResumenBot {
  final String idBot;
  final String simbolo;
  final String nombreEstrategia;
  final double presupuesto;
  final String estado;
  final bool simulacionDryRun;
  final int tramosActivos;
  final double montoInvertidoUsdt;
  final double beneficioRealizadoUsdt;
  final double equidadActualUsdt;
  final double tasaAciertoPct;
  final int operacionesTotales;
  final double usdtDisponible;
  final bool esFaseMeseta;
  final bool recomendadaInyeccion;
  final String consejoInyeccion;
  final String? nombreSubcuenta;
  final bool tieneCredencialesPersonalizadas;

  ResumenBot({
    required this.idBot,
    required this.simbolo,
    required this.nombreEstrategia,
    required this.presupuesto,
    required this.estado,
    required this.simulacionDryRun,
    required this.tramosActivos,
    required this.montoInvertidoUsdt,
    required this.beneficioRealizadoUsdt,
    required this.equidadActualUsdt,
    required this.tasaAciertoPct,
    required this.operacionesTotales,
    this.usdtDisponible = 0.0,
    this.esFaseMeseta = false,
    this.recomendadaInyeccion = false,
    this.consejoInyeccion = '',
    this.nombreSubcuenta,
    this.tieneCredencialesPersonalizadas = false,
  });

  factory ResumenBot.fromJson(Map<String, dynamic> json) {
    return ResumenBot(
      idBot: json['bot_id'] ?? json['id_bot'] ?? '',
      simbolo: json['symbol'] ?? json['simbolo'] ?? '',
      nombreEstrategia: json['strategy_name'] ?? json['nombre_estrategia'] ?? '',
      presupuesto: (json['budget'] ?? json['presupuesto'] ?? 0.0).toDouble(),
      estado: json['status'] ?? json['estado'] ?? 'STOPPED',
      simulacionDryRun: json['dry_run'] ?? json['simulacion_dry_run'] ?? true,
      tramosActivos: json['active_tranches_count'] ?? json['conteo_tramos_activos'] ?? 0,
      montoInvertidoUsdt: (json['invested_amount_usdt'] ?? json['monto_invertido_usdt'] ?? 0.0).toDouble(),
      beneficioRealizadoUsdt: (json['total_realized_profit_usdt'] ?? json['beneficio_realizado_total_usdt'] ?? 0.0).toDouble(),
      equidadActualUsdt: (json['current_equity_usdt'] ?? json['equidad_actual_usdt'] ?? 0.0).toDouble(),
      tasaAciertoPct: (json['win_rate_pct'] ?? json['tasa_acierto_pct'] ?? 0.0).toDouble(),
      operacionesTotales: json['total_trades'] ?? json['operaciones_totales'] ?? 0,
      usdtDisponible: (json['available_usdt'] ?? json['usdt_disponible'] ?? 0.0).toDouble(),
      esFaseMeseta: json['is_plateau_phase'] ?? json['es_fase_meseta'] ?? false,
      recomendadaInyeccion: json['capital_injection_recommended'] ?? json['inyeccion_recomendada'] ?? false,
      consejoInyeccion: json['capital_injection_advice'] ?? json['consejo_inyeccion'] ?? '',
      nombreSubcuenta: json['subaccount_name'] ?? json['nombre_subcuenta'],
      tieneCredencialesPersonalizadas: json['has_custom_credentials'] ?? json['tiene_credenciales_personalizadas'] ?? false,
    );
  }
}

class TramoModel {
  final int indiceTramo;
  final double presupuestoAsignado;
  final double precioCompra;
  final double cantidad;
  final double precioObjetivoVenta;
  final String estado;
  final double beneficioUsdt;
  final int? marcaTiempoCompra;
  final int? marcaTiempoVenta;

  TramoModel({
    required this.indiceTramo,
    required this.presupuestoAsignado,
    required this.precioCompra,
    required this.cantidad,
    required this.precioObjetivoVenta,
    required this.estado,
    required this.beneficioUsdt,
    this.marcaTiempoCompra,
    this.marcaTiempoVenta,
  });

  factory TramoModel.fromJson(Map<String, dynamic> json) {
    return TramoModel(
      indiceTramo: json['tranche_index'] ?? json['indice_tramo'] ?? 0,
      presupuestoAsignado: (json['allocated_budget'] ?? json['presupuesto_asignado'] ?? 0.0).toDouble(),
      precioCompra: (json['buy_price'] ?? json['precio_compra'] ?? 0.0).toDouble(),
      cantidad: (json['amount'] ?? json['cantidad'] ?? 0.0).toDouble(),
      precioObjetivoVenta: (json['target_sell_price'] ?? json['precio_objetivo_venta'] ?? 0.0).toDouble(),
      estado: json['status'] ?? json['estado'] ?? 'PENDIENTE_COMPRA',
      beneficioUsdt: (json['profit_usdt'] ?? json['beneficio_usdt'] ?? 0.0).toDouble(),
      marcaTiempoCompra: json['buy_timestamp'] ?? json['marca_tiempo_compra'],
      marcaTiempoVenta: json['sell_timestamp'] ?? json['marca_tiempo_venta'],
    );
  }
}

class MetricasGlobales {
  final double equidadTotalUsdt;
  final double flujoCajaTotalUsdt;
  final int operacionesCerradas;
  final double tasaAciertoPct;
  final int botsActivos;

  MetricasGlobales({
    required this.equidadTotalUsdt,
    required this.flujoCajaTotalUsdt,
    required this.operacionesCerradas,
    required this.tasaAciertoPct,
    required this.botsActivos,
  });

  factory MetricasGlobales.fromJson(Map<String, dynamic> json) {
    return MetricasGlobales(
      equidadTotalUsdt: (json['total_portfolio_equity_usdt'] ?? json['equidad_total_portafolio_usdt'] ?? 0.0).toDouble(),
      flujoCajaTotalUsdt: (json['total_cash_flow_extracted_usdt'] ?? json['flujo_caja_total_extraido_usdt'] ?? 0.0).toDouble(),
      operacionesCerradas: json['total_trades_closed'] ?? json['operaciones_totales_cerradas'] ?? 0,
      tasaAciertoPct: (json['portfolio_win_rate_pct'] ?? json['tasa_acierto_portafolio_pct'] ?? 0.0).toDouble(),
      botsActivos: json['active_bots_count'] ?? json['conteo_bots_activos'] ?? 0,
    );
  }
}

class AjustesSistema {
  final bool discordHabilitado;
  final String discordWebhookEnmascarado;
  final bool discordConfigurado;
  final bool telegramHabilitado;
  final String telegramTokenEnmascarado;
  final bool telegramConfigurado;

  AjustesSistema({
    required this.discordHabilitado,
    required this.discordWebhookEnmascarado,
    required this.discordConfigurado,
    required this.telegramHabilitado,
    required this.telegramTokenEnmascarado,
    required this.telegramConfigurado,
  });

  factory AjustesSistema.fromJson(Map<String, dynamic> json) {
    final discord = json['discord'] as Map<String, dynamic>? ?? {};
    final telegram = json['telegram'] as Map<String, dynamic>? ?? {};
    return AjustesSistema(
      discordHabilitado: discord['enabled'] ?? false,
      discordWebhookEnmascarado: discord['webhook_url_masked'] ?? '',
      discordConfigurado: discord['is_configured'] ?? false,
      telegramHabilitado: telegram['enabled'] ?? false,
      telegramTokenEnmascarado: telegram['bot_token_masked'] ?? '',
      telegramConfigurado: telegram['is_configured'] ?? false,
    );
  }
}
