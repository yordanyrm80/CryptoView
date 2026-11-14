import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../domain/bot_models.dart';
import '../providers/bots_provider.dart';
import 'widgets/bot_create_dialog.dart';

class MarketRadarWorkspaceScreen extends StatefulWidget {
  final ValueChanged<String>? onOpenSymbolInChart;

  const MarketRadarWorkspaceScreen({
    super.key,
    this.onOpenSymbolInChart,
  });

  @override
  State<MarketRadarWorkspaceScreen> createState() =>
      _MarketRadarWorkspaceScreenState();
}

class _MarketRadarWorkspaceScreenState
    extends State<MarketRadarWorkspaceScreen> {
  String _selectedFilter = 'TODOS';

  static const Map<String, Map<String, dynamic>> _coinMetadata = {
    'BTC': {
      'name': 'Bitcoin',
      'glyph': '₿',
      'color': Color(0xFFF7931A),
      'tactical':
          'Bitcoin es el líder del ciclo ETF institucional con menor volatilidad que las altcoins. La calibración campeona "Apex Titan BTC Flagship" (TP 4.5%, Tendencia 70%, 8 Tramos) aprovecha las compras por rebote y compounding sistemático.',
    },
    'ETH': {
      'name': 'Ethereum',
      'glyph': 'Ξ',
      'color': Color(0xFF627EEA),
      'tactical':
          'Ethereum presenta un 28.3% más de volatilidad que BTC y un rango diario medio del 6.48%. El Preset Campeón "Apex ETH Ultra" (TP 4.2%, Tendencia 85%, Suelo 50%) logró +5,415.6% en 9 años mitigando trampas en caídas y capturando rebotes con alta aceleración.',
    },
    'KCS': {
      'name': 'KuCoin Token',
      'glyph': 'K',
      'color': Color(0xFF0093DD),
    },
    'SOL': {
      'name': 'Solana',
      'glyph': 'S',
      'color': Color(0xFF14F195),
    },
  };

  final NumberFormat _currencyFmt =
      NumberFormat.currency(symbol: r'$', decimalDigits: 2);
  final NumberFormat _subDollarFmt =
      NumberFormat.currency(symbol: r'$', decimalDigits: 4);

  String _formatPrice(double price) {
    if (price > 0 && price < 1.0) {
      return _subDollarFmt.format(price);
    }
    return _currencyFmt.format(price);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<BotsProvider>().actualizarTodosLosRadares();
      }
    });
  }

  Color _getColorForTrafficLight(String tl) {
    switch (tl.toUpperCase()) {
      case 'GREEN':
        return AppColors.bull;
      case 'RED':
        return AppColors.bear;
      case 'YELLOW':
      default:
        return Colors.amber;
    }
  }

  IconData _getIconForTrafficLight(String tl) {
    switch (tl.toUpperCase()) {
      case 'GREEN':
        return Icons.check_circle_outline;
      case 'RED':
        return Icons.warning_amber_rounded;
      case 'YELLOW':
      default:
        return Icons.info_outline;
    }
  }

  String _baseAsset(String symbol) =>
      symbol.replaceAll('-', '/').split('/').first.trim().toUpperCase();

  Color _getCoinColor(String symbol) {
    final base = _baseAsset(symbol);
    final meta = _coinMetadata[base];
    if (meta != null) return meta['color'] as Color;
    return AppColors.primary;
  }

  String _getCoinFullName(String symbol) {
    final base = _baseAsset(symbol);
    final meta = _coinMetadata[base];
    if (meta != null) return meta['name'] as String;
    return base;
  }

  String _getCoinGlyph(String symbol) {
    final base = _baseAsset(symbol);
    final meta = _coinMetadata[base];
    if (meta != null) return meta['glyph'] as String;
    return base.isNotEmpty ? base[0] : '?';
  }

  Map<String, dynamic> _determineRegimePhase(MarketRadarData radar) {
    final dd = radar.drawdownFromAthPct;
    final distEma = radar.distDailyEma200Pct;
    final rsi = radar.dailyRsi;
    final isExitWarning = radar.exitRadar.isExitWarning;

    if (isExitWarning || (distEma > 40 && rsi > 70)) {
      return {
        'name': 'ZONA DE EUFORIA / TECHO',
        'subtitle': 'Sobrecalentamiento macro (>40% sobre EMA200)',
        'color': AppColors.bear,
        'icon': Icons.local_fire_department,
        'badge': 'ZONA DE RIESGO ELEVADO',
      };
    }

    if (dd <= -45 || rsi <= 35) {
      return {
        'name': 'POZO DE CAPITULACIÓN',
        'subtitle': 'Descuento profundo (>45% de ATH). Rebote asimétrico',
        'color': const Color(0xFFE5A93C),
        'icon': Icons.savings_outlined,
        'badge': 'DESCUENTO PROFUNDO',
      };
    }

    if (distEma > 0 && rsi >= 45 && rsi <= 68) {
      return {
        'name': 'VENTANA DORADA',
        'subtitle': 'Impulso institucional sobre EMA200. Compounding veloz',
        'color': AppColors.bull,
        'icon': Icons.bolt,
        'badge': 'VENTANA ÓPTIMA',
      };
    }

    return {
      'name': 'RANGO NEUTRAL / ACUMULACIÓN',
      'subtitle': 'Oscilación y consolidación de base de mercado',
      'color': Colors.blueGrey,
      'icon': Icons.sync_alt,
      'badge': 'CONSOLIDACIÓN',
    };
  }

  @override
  Widget build(BuildContext context) {
    final botsProvider = context.watch<BotsProvider>();
    final allSymbols = <String>{
      ...botsProvider.radarSymbols,
      ...botsProvider.radarsBySymbol.keys,
    }.toList();

    final filteredSymbols = _selectedFilter == 'TODOS'
        ? allSymbols
        : allSymbols.where((s) => s == _selectedFilter).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildHeaderBar(botsProvider),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildCycleGuideBanner(),
                  const SizedBox(height: 16),
                  _buildFilterChips(allSymbols),
                  const SizedBox(height: 16),
                  if (filteredSymbols.isEmpty)
                    _buildEmptyState()
                  else
                    ...filteredSymbols.map((symbol) {
                      final radar = botsProvider.getRadarForSymbol(symbol);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: _buildAssetRadarCard(symbol, radar, botsProvider),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBar(BotsProvider provider) {
    final lastUpdate = provider.ultimoRefrescoRadar;
    final timeStr = lastUpdate != null
        ? DateFormat('HH:mm:ss').format(lastUpdate)
        : 'Sin sincronizar';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.radar,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Radar de Ciclos & Macro Oportunidades',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Diagnóstico cuantitativo en tiempo real: Drawdown ATH, EMA 200, RSI 14 y Ciclo de Halving',
                    style: TextStyle(
                      color: AppColors.textSecondary.withValues(alpha: 0.8),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time, size: 13, color: AppColors.textMuted),
                    const SizedBox(width: 6),
                    Text(
                      'Actualizado: $timeStr',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: provider.cargandoRadares
                    ? null
                    : () => provider.actualizarTodosLosRadares(),
                icon: provider.cargandoRadares
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.sync, size: 15),
                label: Text(
                  provider.cargandoRadares ? 'Escaneando...' : 'Actualizar Radar',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCycleGuideBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_outline, size: 16, color: Colors.amber),
              const SizedBox(width: 8),
              const Text(
                'GUÍA DE RÉGIMEN PARA EL DESPLIEGUE INTELIGENTE DE BOTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 800;
              final items = [
                _buildGuidePill(
                  title: '🟢 Ventana Dorada',
                  desc: 'Precio sobre EMA 200 diaria con momentum alcista. Ideal para bots de compounding acelerado y TP rápido.',
                  color: AppColors.bull,
                ),
                _buildGuidePill(
                  title: '🟡 Pozo de Capitulación',
                  desc: 'Caída > 45-50% desde ATH con RSI en sobreventa. Descuento extremo (+136% histórico 1A, 0 días atrapado).',
                  color: const Color(0xFFE5A93C),
                ),
                _buildGuidePill(
                  title: '⚪ Consolidación',
                  desc: 'Régimen neutral. Compras escalonadas por tramos con distanciamiento seguro y capturas sistemáticas.',
                  color: Colors.blueGrey,
                ),
                _buildGuidePill(
                  title: '🔴 Zona de Euforia / Techo',
                  desc: 'Extensión parabólica (>40% sobre EMA 200 + RSI > 70). Pausar nuevas recompras y activar cosecha (Harvest).',
                  color: AppColors.bear,
                ),
              ];

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: items.map((w) => Expanded(child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: w,
                  ))).toList(),
                );
              }

              return Column(
                children: items.map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: w,
                )).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGuidePill({
    required String title,
    required String desc,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            style: const TextStyle(
              fontSize: 10,
              color: AppColors.textSecondary,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(List<String> symbols) {
    final filterOptions = ['TODOS', ...symbols];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filterOptions.map((opt) {
          final isSelected = _selectedFilter == opt;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(
                opt,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                ),
              ),
              selected: isSelected,
              selectedColor: AppColors.primary,
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(
                  color: isSelected ? AppColors.primary : AppColors.border,
                ),
              ),
              onSelected: (_) => setState(() => _selectedFilter = opt),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAssetRadarCard(
    String symbol,
    MarketRadarData? radar,
    BotsProvider provider,
  ) {
    final coinColor = _getCoinColor(symbol);
    final coinName = _getCoinFullName(symbol);
    final coinGlyph = _getCoinGlyph(symbol);

    if (radar == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: coinColor.withValues(alpha: 0.2),
              foregroundColor: coinColor,
              radius: 20,
              child: Text(coinGlyph, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$symbol - $coinName',
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Telemetría de ciclo aún no calculada o servicio en espera.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: () => provider.actualizarRadar(symbol),
              icon: const Icon(Icons.radar, size: 14),
              label: const Text('Diagnosticar Ahora', style: TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.surface,
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
              ),
            ),
          ],
        ),
      );
    }

    final regime = _determineRegimePhase(radar);
    final regimeColor = regime['color'] as Color;
    final entry = radar.entryRadar;
    final exit = radar.exitRadar;
    final pi = radar.piCycleMetrics;
    final bestPreset = provider.mejorPresetParaSimbolo(symbol);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: regimeColor.withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Encabezado del Activo & Fase de Régimen
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(
                bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.6)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: coinColor.withValues(alpha: 0.18),
                      foregroundColor: coinColor,
                      radius: 20,
                      child: Text(
                        coinGlyph,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              symbol,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              coinName,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatPrice(radar.currentPrice),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          pi.isTriggered
                              ? 'Pi Cycle: CRUCE DE TECHO (${pi.piRatio.toStringAsFixed(2)})'
                              : 'Pi Ratio: ${pi.piRatio.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: pi.isTriggered
                                ? AppColors.bear
                                : AppColors.textMuted,
                            fontSize: 10,
                            fontWeight: pi.isTriggered
                                ? FontWeight.bold
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: regimeColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: regimeColor.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    children: [
                      Icon(regime['icon'] as IconData, size: 16, color: regimeColor),
                      const SizedBox(width: 6),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            regime['name'] as String,
                            style: TextStyle(
                              color: regimeColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.4,
                            ),
                          ),
                          Text(
                            regime['subtitle'] as String,
                            style: TextStyle(
                              color: regimeColor.withValues(alpha: 0.8),
                              fontSize: 9.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 2. Panel de Métricas Cuantitativas de Fondo
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 700;
                    final metricWidgets = [
                      _buildMetricTile(
                        label: 'Descuento desde ATH',
                        value: '${radar.drawdownFromAthPct.toStringAsFixed(1)}%',
                        subvalue: 'ATH: ${_formatPrice(radar.athPrice)}',
                        valueColor: radar.drawdownFromAthPct <= -45
                            ? const Color(0xFFE5A93C)
                            : (radar.drawdownFromAthPct >= -10 ? AppColors.bull : AppColors.textPrimary),
                        icon: Icons.trending_down,
                      ),
                      _buildMetricTile(
                        label: 'Distancia a EMA 200 Diaria',
                        value: '${radar.distDailyEma200Pct >= 0 ? '+' : ''}${radar.distDailyEma200Pct.toStringAsFixed(1)}%',
                        subvalue: 'EMA 200: ${_formatPrice(radar.dailyEma200)}',
                        valueColor: radar.distDailyEma200Pct >= 0 ? AppColors.bull : Colors.amber,
                        icon: Icons.show_chart,
                      ),
                      _buildMetricTile(
                        label: 'RSI 14 Diario',
                        value: radar.dailyRsi.toStringAsFixed(1),
                        subvalue: radar.dailyRsi <= 35
                            ? 'Sobreventa Extrema'
                            : (radar.dailyRsi >= 65 ? 'Sobrecompra' : 'Zona Neutral'),
                        valueColor: radar.dailyRsi <= 35
                            ? AppColors.bull
                            : (radar.dailyRsi >= 70 ? AppColors.bear : AppColors.textPrimary),
                        icon: Icons.speed,
                      ),
                      _buildMetricTile(
                        label: 'Días desde Halving',
                        value: '+${radar.daysSinceLastHalving}d',
                        subvalue: 'Fase de Maduración de Ciclo',
                        valueColor: AppColors.textPrimary,
                        icon: Icons.calendar_month_outlined,
                      ),
                    ];

                    if (isWide) {
                      return Row(
                        children: metricWidgets
                            .map((w) => Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: w,
                                  ),
                                ))
                            .toList(),
                      );
                    }

                    return GridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 2.2,
                      children: metricWidgets,
                    );
                  },
                ),
                const SizedBox(height: 16),

                // 3. Semáforos de Entrada & Salida Macro
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _getColorForTrafficLight(entry.trafficLight).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _getColorForTrafficLight(entry.trafficLight).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _getIconForTrafficLight(entry.trafficLight),
                                  size: 16,
                                  color: _getColorForTrafficLight(entry.trafficLight),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'ENTRADA BOT: ${entry.title}',
                                    style: TextStyle(
                                      color: _getColorForTrafficLight(entry.trafficLight),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              entry.recommendation,
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Validación Histórica 1A: Win Rate ${entry.historicalWinRate1yPct.toStringAsFixed(0)}% · Retorno Medio +${entry.historicalAvgReturn1yPct.toStringAsFixed(1)}%',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _getColorForTrafficLight(exit.trafficLight).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _getColorForTrafficLight(exit.trafficLight).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  _getIconForTrafficLight(exit.trafficLight),
                                  size: 16,
                                  color: _getColorForTrafficLight(exit.trafficLight),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'SALIDA / TECHO: ${exit.title}',
                                    style: TextStyle(
                                      color: _getColorForTrafficLight(exit.trafficLight),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              exit.recommendation,
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              exit.suggestedAction == 'NONE'
                                  ? 'Sin alertas de salida macro activa.'
                                  : 'Acción sugerida: ${exit.suggestedAction}',
                              style: TextStyle(
                                color: exit.isExitWarning ? AppColors.bear : AppColors.textMuted,
                                fontSize: 10,
                                fontWeight: exit.isExitWarning ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 4. Diagnóstico Táctico Específico para Bots Cuantitativos
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.psychology_outlined, size: 20, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'DIAGNÓSTICO TÁCTICO CUANTITATIVO Y PRESET RECOMENDADO',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              (_coinMetadata[_baseAsset(symbol)]?['tactical']
                                      as String?) ??
                                  (bestPreset.descripcion.isNotEmpty
                                      ? '${bestPreset.nombre}: ${bestPreset.descripcion}'
                                      : 'Activo bajo monitorización cuantitativa con ${bestPreset.nombre} (TP ${bestPreset.takeProfitPct}%, Tendencia ${(bestPreset.pesoTendencia * 100).toStringAsFixed(0)}%, ${bestPreset.maxTramosBase}+${bestPreset.tramosSueloExtra} tramos).'),
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 11.5,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 5. Botones de Acción Directa
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => widget.onOpenSymbolInChart?.call(symbol),
                      icon: const Icon(Icons.candlestick_chart_outlined, size: 15),
                      label: const Text('Ver en Gráfico', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: () {
                        showBotCreateDialog(
                          context,
                          provider,
                          initialSymbol: symbol,
                          initialConfigId: bestPreset.id,
                        );
                      },
                      icon: const Icon(Icons.rocket_launch_outlined, size: 15),
                      label: Text(
                        'Lanzar Bot (${bestPreset.nombre})',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required String subvalue,
    required Color valueColor,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Icon(icon, size: 14, color: AppColors.textMuted),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subvalue,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      alignment: Alignment.center,
      child: const Column(
        children: [
          Icon(Icons.radar, size: 48, color: AppColors.textMuted),
          SizedBox(height: 12),
          Text(
            'No se encontraron activos para el filtro seleccionado',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
