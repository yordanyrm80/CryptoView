import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../domain/bot_models.dart';
import '../providers/bots_provider.dart';
import 'widgets/bot_orders_events_dialog.dart';
import 'widgets/bot_chart_monitor_dialog.dart';
import 'widgets/bot_dialog_helpers.dart';
import 'widgets/bot_preset_dialog.dart';
import 'widgets/bot_config_dialog.dart';
import 'widgets/bot_capital_dialog.dart';
import 'widgets/bot_create_dialog.dart';
import 'widgets/bot_strategy_params_dialog.dart';

class BotsWorkspaceScreen extends StatefulWidget {
  final ValueChanged<String>? onOpenSymbolInChart;

  const BotsWorkspaceScreen({
    super.key,
    this.onOpenSymbolInChart,
  });

  @override
  State<BotsWorkspaceScreen> createState() => _BotsWorkspaceScreenState();
}

class _BotsWorkspaceScreenState extends State<BotsWorkspaceScreen> {
  final Set<String> _expandedBotIds = {};
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _currencyFmt =
      NumberFormat.currency(symbol: r'$', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<BotsProvider>().startPolling();
      }
    });
  }

  @override
  void dispose() {
    try {
      context.read<BotsProvider>().stopPolling();
    } catch (_) {}
    _searchController.dispose();
    super.dispose();
  }

  String _formatStrategyName(String raw) {
    switch (raw) {
      case 'BtcQuantumEvolutionRegimeStrategy':
        return 'Quantum Evolution Regime';
      default:
        return raw;
    }
  }

  List<double> _parsePercentWeightsInput(String text, List<double> fallback) {
    final parts = text
        .split(',')
        .map((s) => double.tryParse(s.trim()))
        .whereType<double>()
        .where((n) => n > 0)
        .toList();
    if (parts.isEmpty) return fallback;
    final sum = parts.fold<double>(0.0, (a, b) => a + b);
    // Si el usuario escribe porcentajes (ej. 30, 25, 20, 15, 10 -> suma > 2), convertir a fracción 0..1
    if (sum > 2.0) {
      return parts
          .map((n) => double.parse((n / 100.0).toStringAsFixed(4)))
          .toList();
    }
    return parts;
  }

  String _formatPercentWeights(List<double> weights) {
    return weights
        .map((w) => (w <= 1.0 ? w * 100.0 : w)
            .toStringAsFixed(1)
            .replaceAll(RegExp(r'\.0$'), ''))
        .join(', ');
  }

  Future<void> _mostrarDialogoGuardarPreset(
    BuildContext context,
    BotsProvider provider, {
    required String strategyName,
    required double takeProfitPct,
    required double trailingStopPct,
    required double trendWeight,
    required List<double> baseWeights,
    required List<double> floorWeights,
    required double t0Rsi,
    required double panicRsi,
    required ValueChanged<String> onSavedName,
  }) =>
      showBotPresetDialog(
        context,
        provider,
        strategyName: strategyName,
        takeProfitPct: takeProfitPct,
        trailingStopPct: trailingStopPct,
        trendWeight: trendWeight,
        baseWeights: baseWeights,
        floorWeights: floorWeights,
        t0Rsi: t0Rsi,
        panicRsi: panicRsi,
        onSavedName: onSavedName,
      );

  Future<void> _mostrarDialogoConfiguracion(
          BuildContext context, BotsProvider provider) =>
      showBotConfigDialog(context, provider);

  Future<void> _mostrarDialogoCapital(
    BuildContext context,
    BotsProvider provider,
    ResumenBot bot,
    bool esDeposito,
  ) =>
      showBotCapitalDialog(context, provider, bot, esDeposito);

  Future<void> _mostrarDialogoCrearBot(
          BuildContext context, BotsProvider provider) =>
      showBotCreateDialog(context, provider);

  Future<void> _mostrarDialogoParametrosBot(
    BuildContext context,
    BotsProvider provider,
    ResumenBot bot,
  ) =>
      showBotStrategyParamsDialog(context, provider, bot);

  @override
  Widget build(BuildContext context) {
    final botsProvider = context.watch<BotsProvider>();
    final bots = botsProvider.botsFiltrados;

    return Container(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTopBar(context, botsProvider),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () => botsProvider.cargarDatos(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!botsProvider.isConnected)
                    _buildOfflineBanner(context, botsProvider),
                  _buildFleetMetricsGrid(botsProvider),
                  const SizedBox(height: 20),
                  _buildFilterAndSearchBar(botsProvider),
                  const SizedBox(height: 14),
                  if (botsProvider.isLoading && bots.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child:
                            CircularProgressIndicator(color: AppColors.primary),
                      ),
                    )
                  else if (bots.isEmpty)
                    _buildEmptyState(context, botsProvider)
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isTwoColumns = constraints.maxWidth >= 1100;
                        if (!isTwoColumns) {
                          return Column(
                            children: bots
                                .map((b) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: _buildBotCard(
                                          context, botsProvider, b),
                                    ))
                                .toList(),
                          );
                        }
                        // En escritorio ancho organizamos en 2 columnas equilibradas
                        final List<Widget> rows = [];
                        for (int i = 0; i < bots.length; i += 2) {
                          final first = bots[i];
                          final second =
                              (i + 1 < bots.length) ? bots[i + 1] : null;
                          rows.add(
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _buildBotCard(
                                        context, botsProvider, first),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: second != null
                                        ? _buildBotCard(
                                            context, botsProvider, second)
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        return Column(children: rows);
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, BotsProvider provider) {
    final isConnected = provider.isConnected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.surface,
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.smart_toy_outlined,
                    color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Gestión de Flota de Bots Cuantitativos',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'Supervisión de estrategias automatizadas, escaleras de tramos y asignación de liquidez',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => _mostrarDialogoConfiguracion(context, provider),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: (isConnected
                            ? AppColors.bull
                            : Colors.amber)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: (isConnected
                              ? AppColors.bull
                              : Colors.amber)
                          .withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              isConnected ? AppColors.bull : Colors.amber,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isConnected
                            ? 'Motor Activo'
                            : 'Motor Desconectado',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color:
                              isConnected ? AppColors.bull : Colors.amber,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: provider.isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary),
                      )
                    : const Icon(Icons.sync,
                        size: 18, color: AppColors.textSecondary),
                tooltip: 'Sincronizar estado de la flota',
                onPressed: provider.isLoading
                    ? null
                    : () => provider.cargarDatos(),
              ),
              IconButton(
                icon: const Icon(Icons.tune,
                    size: 18, color: AppColors.textSecondary),
                tooltip: 'Parámetros del motor y alertas',
                onPressed: () =>
                    _mostrarDialogoConfiguracion(context, provider),
              ),
              const SizedBox(width: 4),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text(
                  'Desplegar Bot',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: () => _mostrarDialogoCrearBot(context, provider),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineBanner(BuildContext context, BotsProvider provider) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_sync_outlined, color: Colors.amber, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Endpoints de flota de bots pendientes de sincronización en la API Central',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  provider.lastError ??
                      'Conectando con ${provider.baseUrl}/api/v1/bots. Verifica que el backend central tenga desplegado el router de bots.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            icon: const Icon(Icons.refresh, size: 15),
            label:
                const Text('Reintentar', style: TextStyle(fontSize: 11)),
            onPressed: () => provider.cargarDatos(),
          ),
        ],
      ),
    );
  }

  Widget _buildFleetMetricsGrid(BotsProvider provider) {
    final m = provider.metricas;
    final equidad = m?.equidadTotalUsdt ?? 0.0;
    final invertido = m?.invertidoTotalUsdt ?? 0.0;
    final disponible = m?.disponibleTotalUsdt ?? 0.0;
    final beneficio = m?.beneficioRealizadoTotalUsdt ?? 0.0;
    final tasaAcierto = m?.tasaAciertoPct ?? 0.0;
    final cerradas = m?.operacionesCerradas ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 760;
        final cards = [
          _buildKpiCard(
            title: 'PATRIMONIO EN BOTS (EQUITY)',
            value: _currencyFmt.format(equidad),
            subtitle:
                '${provider.botsActivosCount} activos de ${provider.totalBotsCount} registrados',
            icon: Icons.account_balance_wallet_outlined,
            accentColor: AppColors.primary,
          ),
          _buildKpiCard(
            title: 'EXPOSICIÓN Y LIQUIDEZ',
            value: _currencyFmt.format(invertido),
            subtitle: 'Reserva libre: ${_currencyFmt.format(disponible)} USDT',
            icon: Icons.pie_chart_outline,
            accentColor: Colors.cyanAccent,
          ),
          _buildKpiCard(
            title: 'BENEFICIO REALIZADO NETO',
            value:
                '${beneficio >= 0 ? '+' : ''}${_currencyFmt.format(beneficio)}',
            subtitle: 'Flujo acumulado de ciclos cerrados',
            icon: Icons.trending_up,
            accentColor:
                beneficio >= 0 ? AppColors.bull : AppColors.bear,
          ),
          _buildKpiCard(
            title: 'EFECTIVIDAD OPERATIVA',
            value: '${tasaAcierto.toStringAsFixed(1)}%',
            subtitle: '$cerradas operaciones completadas',
            icon: Icons.verified_outlined,
            accentColor: AppColors.bull,
          ),
        ];

        if (isWide) {
          return Row(
            children: [
              for (int i = 0; i < cards.length; i++) ...[
                Expanded(child: cards[i]),
                if (i < cards.length - 1) const SizedBox(width: 12),
              ],
            ],
          );
        } else {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 10),
                  Expanded(child: cards[1]),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: cards[2]),
                  const SizedBox(width: 10),
                  Expanded(child: cards[3]),
                ],
              ),
            ],
          );
        }
      },
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icon, size: 16, color: accentColor),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterAndSearchBar(BotsProvider provider) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 10,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _buildFilterChip(
              label: 'Todos (${provider.totalBotsCount})',
              selected: provider.filtroEstado == 'TODOS',
              onTap: () => provider.setFiltroEstado('TODOS'),
            ),
            _buildFilterChip(
              label: 'Activos (${provider.botsActivosCount})',
              selected: provider.filtroEstado == 'RUNNING',
              color: AppColors.bull,
              onTap: () => provider.setFiltroEstado('RUNNING'),
            ),
            _buildFilterChip(
              label: 'Pausados (${provider.botsPausadosCount})',
              selected: provider.filtroEstado == 'PAUSED',
              color: Colors.amber,
              onTap: () => provider.setFiltroEstado('PAUSED'),
            ),
            _buildFilterChip(
              label: 'Detenidos (${provider.botsDetenidosCount})',
              selected: provider.filtroEstado == 'STOPPED',
              color: AppColors.bear,
              onTap: () => provider.setFiltroEstado('STOPPED'),
            ),
          ],
        ),
        SizedBox(
          width: 260,
          height: 34,
          child: TextField(
            controller: _searchController,
            onChanged: provider.setBusqueda,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Filtrar por moneda, ID o estrategia...',
              hintStyle:
                  const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              prefixIcon: const Icon(Icons.search,
                  size: 16, color: AppColors.textSecondary),
              suffixIcon: provider.busqueda.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 14),
                      onPressed: () {
                        _searchController.clear();
                        provider.setBusqueda('');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    Color? color,
    required VoidCallback onTap,
  }) {
    final activeColor = color ?? AppColors.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: 0.16)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? activeColor : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected ? activeColor : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, BotsProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.smart_toy_outlined,
            size: 42,
            color: AppColors.textSecondary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            provider.todosLosBots.isEmpty
                ? 'No hay instancias de bots registradas'
                : 'Ningún bot coincide con el filtro seleccionado',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            provider.todosLosBots.isEmpty
                ? 'Despliega tu primer bot cuantitativo para supervisar sus tramos de compra, objetivos de salida y asignación de liquidez desde este panel.'
                : 'Prueba cambiando el filtro de estado o limpiando el término de búsqueda.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 18),
          if (provider.todosLosBots.isEmpty)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Desplegar Nuevo Bot'),
              onPressed: () => _mostrarDialogoCrearBot(context, provider),
            ),
        ],
      ),
    );
  }

  Widget _buildBotCard(
    BuildContext context,
    BotsProvider provider,
    ResumenBot bot,
  ) {
    final tramos = provider.obtenerTramosDeBot(bot.idBot);
    final isExpanded = _expandedBotIds.contains(bot.idBot);

    Color statusColor = AppColors.textSecondary;
    String statusText = 'DETENIDO';
    if (bot.estaActivo) {
      statusColor = AppColors.bull;
      statusText = 'ACTIVO';
    } else if (bot.estaPausado) {
      statusColor = Colors.amber;
      statusText = 'PAUSADO';
    } else {
      statusColor = AppColors.bear;
    }

    final totalSlots =
        bot.maxTramos > bot.tramosActivos ? bot.maxTramos : bot.tramosActivos;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: bot.estaActivo
              ? AppColors.bull.withValues(alpha: 0.45)
              : AppColors.border,
          width: bot.estaActivo ? 1.2 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Cabecera de la tarjeta
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        bot.simbolo,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              bot.idBot,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildBadge(
                              text: statusText,
                              color: statusColor,
                            ),
                            const SizedBox(width: 6),
                            _buildBadge(
                              text: bot.simulacionDryRun ? 'SIMULACIÓN' : 'EN VIVO',
                              color: bot.simulacionDryRun
                                  ? Colors.cyanAccent
                                  : AppColors.bull,
                            ),
                            const SizedBox(width: 6),
                            _buildBadge(
                              text: bot.regimenMercado == 'BULL_TREND'
                                  ? 'TENDENCIA ALCISTA'
                                  : (bot.regimenMercado == 'PANIC_CAPITULATION'
                                      ? 'CAPITULACIÓN'
                                      : 'RANGO'),
                              color: bot.regimenMercado == 'BULL_TREND'
                                  ? AppColors.bull
                                  : (bot.regimenMercado == 'PANIC_CAPITULATION'
                                      ? AppColors.bear
                                      : Colors.amber),
                            ),
                            if (bot.rsiActual != null) ...[
                              const SizedBox(width: 6),
                              _buildBadge(
                                text: 'RSI ${bot.rsiActual!.toStringAsFixed(1)}',
                                color: bot.rsiActual! <= bot.umbralRsiPanico
                                    ? AppColors.bear
                                    : (bot.rsiActual! <= bot.umbralRsiT0
                                        ? Colors.cyanAccent
                                        : AppColors.textSecondary),
                              ),
                            ],
                            if (bot.nombreSubcuenta != null &&
                                bot.nombreSubcuenta!.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              _buildBadge(
                                text: bot.nombreSubcuenta!,
                                color: Colors.purpleAccent,
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_formatStrategyName(bot.nombreEstrategia)} · TP ${bot.takeProfitPct}% · TS ${bot.trailingStopPct}% · Tendencia ${(bot.pesoTendencia * 100).toStringAsFixed(0)}% · ${bot.maxTramos} Tramos',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.auto_graph_outlined,
                          size: 17, color: Colors.cyanAccent),
                      tooltip: 'Monitor Gráfico Exclusivo del Bot',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => BotChartMonitorDialog(
                              bot: bot, provider: provider),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.history_outlined,
                          size: 17, color: AppColors.primary),
                      tooltip: 'Historial de Órdenes y Eventos',
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) => BotOrdersEventsDialog(
                              bot: bot, provider: provider),
                        );
                      },
                    ),
                    if (widget.onOpenSymbolInChart != null)
                      IconButton(
                        icon: const Icon(Icons.candlestick_chart_outlined,
                            size: 17, color: AppColors.textSecondary),
                        tooltip: 'Abrir ${bot.simbolo} en el área general de Gráfico',
                        visualDensity: VisualDensity.compact,
                        onPressed: () =>
                            widget.onOpenSymbolInChart!(bot.simbolo),
                      ),
                    IconButton(
                      icon: const Icon(Icons.tune,
                          size: 17, color: AppColors.primary),
                      tooltip:
                          'Parámetros de estrategia y Configuración Recomendada',
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          _mostrarDialogoParametrosBot(context, provider, bot),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_card_outlined,
                          size: 17, color: AppColors.bull),
                      tooltip: 'Asignar capital',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _mostrarDialogoCapital(
                          context, provider, bot, true),
                    ),
                    IconButton(
                      icon: const Icon(Icons.output_outlined,
                          size: 17, color: Colors.amber),
                      tooltip: 'Retirar liquidez',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _mostrarDialogoCapital(
                          context, provider, bot, false),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert,
                          size: 17, color: AppColors.textSecondary),
                      tooltip: 'Más opciones',
                      color: AppColors.surface,
                      onSelected: (val) async {
                        if (val == 'reset') {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: AppColors.surface,
                              title: const Text('¿Reiniciar Simulación?',
                                  style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold)),
                              content: Text(
                                'Se eliminarán todos los tramos, órdenes simuladas y transacciones del bot "${bot.idBot}", restaurando el presupuesto inicial de ${bot.presupuestoAsignado} USDT.',
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancelar',
                                      style: TextStyle(
                                          color: AppColors.textSecondary)),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.amber,
                                      foregroundColor: Colors.black),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Reiniciar',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            final ok =
                                await provider.reiniciarSimulacion(bot.idBot);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(ok
                                      ? 'Simulación reiniciada correctamente.'
                                      : 'No se pudo reiniciar la simulación.'),
                                  backgroundColor:
                                      ok ? AppColors.bull : AppColors.bear,
                                ),
                              );
                            }
                          }
                        } else if (val == 'delete') {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: AppColors.surface,
                              title: const Text('¿Eliminar Bot?',
                                  style: TextStyle(
                                      color: AppColors.bear,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold)),
                              content: Text(
                                '¿Estás seguro de que deseas eliminar permanentemente el bot "${bot.idBot}" y su historial?',
                                style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 12),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancelar',
                                      style: TextStyle(
                                          color: AppColors.textSecondary)),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.bear,
                                      foregroundColor: Colors.white),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Eliminar',
                                      style: TextStyle(
                                          fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            final ok = await provider.eliminarBot(bot.idBot);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(ok
                                      ? 'Bot eliminado correctamente.'
                                      : 'No se pudo eliminar el bot.'),
                                  backgroundColor:
                                      ok ? AppColors.bull : AppColors.bear,
                                ),
                              );
                            }
                          }
                        }
                      },
                      itemBuilder: (ctx) => [
                        if (bot.simulacionDryRun && !bot.estaActivo)
                          const PopupMenuItem(
                            value: 'reset',
                            child: Row(
                              children: [
                                Icon(Icons.restart_alt,
                                    size: 16, color: Colors.amber),
                                SizedBox(width: 8),
                                Text('Reiniciar Simulación',
                                    style: TextStyle(
                                        color: AppColors.textPrimary,
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                        if (!bot.estaActivo)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline,
                                    size: 16, color: AppColors.bear),
                                SizedBox(width: 8),
                                Text('Eliminar Bot',
                                    style: TextStyle(
                                        color: AppColors.bear, fontSize: 12)),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    _buildStateControlButtons(provider, bot),
                  ],
                ),
              ],
            ),
          ),

          if (bot.recomendadaInyeccion)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      color: Colors.amber, size: 15),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      bot.consejoInyeccion.isNotEmpty
                          ? bot.consejoInyeccion
                          : 'Capacidad de tramos base completada. Revisa disponibilidad para tramos adicionales.',
                      style:
                          const TextStyle(color: Colors.amber, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),

          const Divider(height: 1, color: AppColors.border),

          // Métricas financieras del bot + Barra visual de tramos
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildBotMetricColumn(
                      'Patrimonio',
                      _currencyFmt.format(bot.equidadActualUsdt),
                      AppColors.primary,
                    ),
                    _buildBotMetricColumn(
                      'Invertido',
                      _currencyFmt.format(bot.montoInvertidoUsdt),
                      AppColors.textPrimary,
                    ),
                    _buildBotMetricColumn(
                      'Reserva USDT',
                      _currencyFmt.format(bot.usdtDisponible),
                      AppColors.bull,
                    ),
                    _buildBotMetricColumn(
                      'PnL Flotante',
                      '${bot.beneficioNoRealizadoUsdt >= 0 ? '+' : ''}${_currencyFmt.format(bot.beneficioNoRealizadoUsdt)}',
                      bot.beneficioNoRealizadoUsdt >= 0
                          ? AppColors.bull
                          : AppColors.bear,
                    ),
                    _buildBotMetricColumn(
                      'PnL Realizado',
                      '${bot.beneficioRealizadoUsdt >= 0 ? '+' : ''}${_currencyFmt.format(bot.beneficioRealizadoUsdt)}',
                      bot.beneficioRealizadoUsdt >= 0
                          ? AppColors.bull
                          : AppColors.bear,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Barra de ocupación de tramos
                Row(
                  children: [
                    Text(
                      'Escalera de Tramos: ${bot.tramosActivos} / $totalSlots ocupados',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: List.generate(totalSlots, (index) {
                          final active = index < bot.tramosActivos;
                          return Expanded(
                            child: Container(
                              height: 6,
                              margin: const EdgeInsets.only(right: 3),
                              decoration: BoxDecoration(
                                color: active
                                    ? AppColors.primary
                                    : AppColors.background,
                                borderRadius: BorderRadius.circular(2),
                                border: Border.all(
                                  color: active
                                      ? AppColors.primary
                                      : AppColors.border,
                                  width: 0.6,
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        setState(() {
                          if (isExpanded) {
                            _expandedBotIds.remove(bot.idBot);
                          } else {
                            _expandedBotIds.add(bot.idBot);
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isExpanded ? 'Ocultar tramos' : 'Ver tramos',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Icon(
                              isExpanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              size: 16,
                              color: AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (isExpanded) ...[
                  const SizedBox(height: 10),
                  _buildTranchesList(tramos),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge({required String text, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  Widget _buildStateControlButtons(BotsProvider provider, ResumenBot bot) {
    if (bot.estaDetenido) {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.bull,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          visualDensity: VisualDensity.compact,
        ),
        icon: const Icon(Icons.play_arrow, size: 15),
        label: const Text('Iniciar',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
        onPressed: () => provider.iniciarBot(bot.idBot),
      );
    } else if (bot.estaActivo) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.amber,
              side: const BorderSide(color: Colors.amber),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.pause, size: 14),
            label: const Text('Pausar', style: TextStyle(fontSize: 11)),
            onPressed: () => provider.pausarBot(bot.idBot),
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.bear,
              side: const BorderSide(color: AppColors.bear),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.stop, size: 14),
            label: const Text('Detener', style: TextStyle(fontSize: 11)),
            onPressed: () => provider.detenerBot(bot.idBot),
          ),
        ],
      );
    } else {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.bull,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.play_arrow, size: 14),
            label: const Text('Reanudar',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            onPressed: () => provider.reanudarBot(bot.idBot),
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.bear,
              side: const BorderSide(color: AppColors.bear),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.stop, size: 14),
            label: const Text('Detener', style: TextStyle(fontSize: 11)),
            onPressed: () => provider.detenerBot(bot.idBot),
          ),
        ],
      );
    }
  }

  Widget _buildBotMetricColumn(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Widget _buildTranchesList(List<TramoBot> tramos) {
    if (tramos.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
        ),
        child: const Center(
          child: Text(
            'Sin tramos abiertos actualmente. El motor aguarda señal de entrada.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Column(
      children: tramos.map((t) {
        final esSuelo = t.indiceTramo >= 5;
        final color = esSuelo ? Colors.purpleAccent : AppColors.primary;
        return Container(
          margin: const EdgeInsets.only(bottom: 5),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color:
                  t.esActivo ? color.withValues(alpha: 0.45) : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      esSuelo ? 'RESERVA T${t.indiceTramo}' : 'T${t.indiceTramo}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Entrada: ${_currencyFmt.format(t.precioCompra)}',
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                      ),
                      if (t.precioMaximoAlcanzado > t.precioCompra)
                        Text(
                          'Máx: ${_currencyFmt.format(t.precioMaximoAlcanzado)}',
                          style: const TextStyle(
                              fontSize: 10, color: Colors.cyanAccent),
                        ),
                      if (t.fechaApertura != null)
                        Text(
                          DateFormat('dd/MM HH:mm').format(t.fechaApertura!.toLocal()),
                          style: const TextStyle(
                              fontSize: 9.5, color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    'Objetivo: ${_currencyFmt.format(t.precioObjetivoVenta)}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.bull,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${_currencyFmt.format(t.presupuestoAsignado)} USDT',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
