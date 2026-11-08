import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/bot_models.dart';
import '../../providers/bots_provider.dart';

class MarketRadarCard extends StatelessWidget {
  final BotsProvider botsProvider;

  const MarketRadarCard({super.key, required this.botsProvider});

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

  void _mostrarDetallesDialog(BuildContext context, MarketRadarData radar) {
    showDialog(
      context: context,
      builder: (ctx) {
        final entry = radar.entryRadar;
        final exit = radar.exitRadar;
        final pi = radar.piCycleMetrics;

        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
          title: Row(
            children: [
              const Icon(Icons.radar, color: AppColors.primary, size: 24),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Diagnóstico Macro de Ciclo (${radar.symbol})',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 580,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.card.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _getColorForTrafficLight(entry.trafficLight)
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _getIconForTrafficLight(entry.trafficLight),
                              color: _getColorForTrafficLight(entry.trafficLight),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'SEMÁFORO DE ENTRADA: ${entry.title}',
                              style: TextStyle(
                                color:
                                    _getColorForTrafficLight(entry.trafficLight),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          entry.recommendation,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              'Win Rate Histórico 1A: ${entry.historicalWinRate1yPct.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Text(
                              'Retorno Medio 1A: ${entry.historicalAvgReturn1yPct >= 0 ? '+' : ''}${entry.historicalAvgReturn1yPct.toStringAsFixed(1)}%',
                              style: TextStyle(
                                color: entry.historicalAvgReturn1yPct >= 0
                                    ? AppColors.bull
                                    : AppColors.bear,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.card.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _getColorForTrafficLight(exit.trafficLight)
                            .withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _getIconForTrafficLight(exit.trafficLight),
                              color: _getColorForTrafficLight(exit.trafficLight),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'SEMÁFORO DE SALIDA: ${exit.title}',
                              style: TextStyle(
                                color:
                                    _getColorForTrafficLight(exit.trafficLight),
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          exit.recommendation,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                        if (exit.suggestedAction != 'NONE') ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.bear.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Acción Sugerida: ${exit.suggestedAction == "PAUSE_NEW_ENTRIES" ? "Pausar Nuevas Recompras (Graceful Harvest)" : exit.suggestedAction}',
                              style: const TextStyle(
                                color: AppColors.bear,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Métricas Cuantitativas de Fondo:',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      _metricBadge('Precio BTC',
                          '\$${radar.currentPrice.toStringAsFixed(0)}'),
                      _metricBadge('Daily EMA 200',
                          '\$${radar.dailyEma200.toStringAsFixed(0)}'),
                      _metricBadge('Distancia EMA 200',
                          '${radar.distDailyEma200Pct >= 0 ? '+' : ''}${radar.distDailyEma200Pct.toStringAsFixed(1)}%'),
                      _metricBadge('RSI Diario (14)',
                          radar.dailyRsi.toStringAsFixed(1)),
                      _metricBadge('ATH Registrado',
                          '\$${radar.athPrice.toStringAsFixed(0)}'),
                      _metricBadge('Drawdown desde ATH',
                          '${radar.drawdownFromAthPct.toStringAsFixed(1)}%'),
                      _metricBadge('Pi Cycle Ratio',
                          '${pi.piRatio.toStringAsFixed(3)} (Alerta si >= 1.0)'),
                      _metricBadge('Días sobre EMA 200',
                          '${radar.daysAboveDailyEma200.toStringAsFixed(0)} d'),
                      _metricBadge('Días post-halving',
                          '${radar.daysSinceLastHalving} d'),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Nota: Este radar es 100% consultivo. Provee lectura matemática del ciclo sin limitar ni bloquear ninguna acción en tus bots.',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cerrar',
                  style: TextStyle(color: AppColors.primary)),
            ),
          ],
        );
      },
    );
  }

  Widget _metricBadge(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white38, fontSize: 10)),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final radar = botsProvider.marketRadar;
    if (radar == null) return const SizedBox.shrink();

    final entry = radar.entryRadar;
    final exit = radar.exitRadar;

    final entryColor = _getColorForTrafficLight(entry.trafficLight);
    final exitColor = _getColorForTrafficLight(exit.trafficLight);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.radar, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Radar de Ciclo Macro (${radar.symbol})',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.4)),
                ),
                child: const Text(
                  '100% CONSULTIVO',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => _mostrarDetallesDialog(context, radar),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        'Ver Diagnóstico',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios,
                          size: 10, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxWidth < 650;
              final entryBadge = _buildSignalPill(
                label: 'ENTRADA (BOTS)',
                title: entry.title,
                color: entryColor,
                icon: _getIconForTrafficLight(entry.trafficLight),
                subtitle: entry.isIdealEntry
                    ? 'Momento óptimo para lanzar bots'
                    : 'Condiciones estándar de mercado',
              );

              final exitBadge = _buildSignalPill(
                label: 'SALIDA (COSECHA)',
                title: exit.title,
                color: exitColor,
                icon: _getIconForTrafficLight(exit.trafficLight),
                subtitle: exit.isExitWarning
                    ? 'Alerta de agotamiento detectada'
                    : 'Sin señales de techo macro',
              );

              if (isCompact) {
                return Column(
                  children: [
                    entryBadge,
                    const SizedBox(height: 8),
                    exitBadge,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: entryBadge),
                  const SizedBox(width: 12),
                  Expanded(child: exitBadge),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSignalPill({
    required String label,
    required String title,
    required Color color,
    required IconData icon,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 10,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
