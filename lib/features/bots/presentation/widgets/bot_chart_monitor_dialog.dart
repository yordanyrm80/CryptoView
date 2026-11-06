import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';

import '../../../../core/services/cloud_api_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../chart/domain/models/chart_candle_model.dart';
import '../../domain/bot_models.dart';
import '../../providers/bots_provider.dart';

class BotChartMonitorDialog extends StatefulWidget {
  final ResumenBot bot;
  final BotsProvider provider;

  const BotChartMonitorDialog({
    Key? key,
    required this.bot,
    required this.provider,
  }) : super(key: key);

  @override
  State<BotChartMonitorDialog> createState() => _BotChartMonitorDialogState();
}

class _BotChartMonitorDialogState extends State<BotChartMonitorDialog> {
  final _currencyFmt = NumberFormat.currency(locale: 'en_US', symbol: '\$');
  bool _loading = true;
  List<ChartData> _candles = [];
  String _timeframe = '1h';

  @override
  void initState() {
    super.initState();
    _cargarVelas();
  }

  Future<void> _cargarVelas() async {
    setState(() => _loading = true);
    try {
      final rawCandles = await CloudApiService.instance.fetchCandles(
        'kucoin',
        widget.bot.simbolo,
        _timeframe,
        limit: 120,
      );

      final List<ChartData> parsed = [];
      for (final c in rawCandles) {
        final ts = (c['time'] as num).toInt();
        parsed.add(
          ChartData(
            date: DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true),
            open: ((c['open'] ?? 0.0) as num).toDouble(),
            high: ((c['high'] ?? 0.0) as num).toDouble(),
            low: ((c['low'] ?? 0.0) as num).toDouble(),
            close: ((c['close'] ?? 0.0) as num).toDouble(),
          ),
        );
      }
      parsed.sort((a, b) => a.date.compareTo(b.date));

      if (mounted) {
        setState(() {
          _candles = parsed;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tramos = widget.provider.obtenerTramosDeBot(widget.bot.idBot);
    final tramosActivos = tramos.where((t) => t.esActivo).toList();

    // Generar PlotBands para los tramos del bot
    final List<PlotBand> plotBands = [];
    for (final tr in tramosActivos) {
      final esSuelo = tr.indiceTramo >= 5;
      final entryColor = esSuelo ? Colors.purpleAccent : AppColors.primary;

      // Línea de entrada
      plotBands.add(
        PlotBand(
          start: tr.precioCompra,
          end: tr.precioCompra,
          borderWidth: 1.5,
          borderColor: entryColor,
          dashArray: const <double>[6, 3],
          text: 'T${tr.indiceTramo} Entrada (${_currencyFmt.format(tr.precioCompra)})',
          textStyle: TextStyle(
            color: entryColor,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
          horizontalTextAlignment: TextAnchor.end,
          verticalTextAlignment: TextAnchor.start,
        ),
      );

      // Línea de Take Profit
      plotBands.add(
        PlotBand(
          start: tr.precioObjetivoVenta,
          end: tr.precioObjetivoVenta,
          borderWidth: 1.5,
          borderColor: AppColors.bull,
          dashArray: const <double>[4, 4],
          text: 'T${tr.indiceTramo} TP (${_currencyFmt.format(tr.precioObjetivoVenta)})',
          textStyle: const TextStyle(
            color: AppColors.bull,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
          horizontalTextAlignment: TextAnchor.end,
          verticalTextAlignment: TextAnchor.start,
        ),
      );
    }

    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      titlePadding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_graph, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Monitor Gráfico · ${widget.bot.idBot}',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          widget.bot.simbolo,
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${widget.bot.regimenMercado} · RSI ${widget.bot.rsiActual?.toStringAsFixed(1) ?? "--"}',
                          style: const TextStyle(
                            color: Colors.amber,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Visualización exclusiva de tramos activos (${tramosActivos.length} activos)',
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
            children: [
              _buildTfButton('15m'),
              const SizedBox(width: 4),
              _buildTfButton('1h'),
              const SizedBox(width: 4),
              _buildTfButton('1d'),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18, color: AppColors.textSecondary),
                tooltip: 'Actualizar',
                onPressed: _cargarVelas,
              ),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 860,
        height: 500,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _candles.isEmpty
                ? const Center(
                    child: Text(
                      'No hay velas disponibles en el servidor para este par.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : SfCartesianChart(
                    plotAreaBorderWidth: 0,
                    zoomPanBehavior: ZoomPanBehavior(
                      enablePinching: true,
                      enablePanning: true,
                      enableDoubleTapZooming: true,
                    ),
                    primaryXAxis: DateTimeAxis(
                      majorGridLines: const MajorGridLines(width: 0.3, color: AppColors.border),
                      axisLine: const AxisLine(color: AppColors.border),
                      labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                      dateFormat: DateFormat('MM/dd HH:mm'),
                    ),
                    primaryYAxis: NumericAxis(
                      opposedPosition: true,
                      majorGridLines: const MajorGridLines(width: 0.3, color: AppColors.border),
                      axisLine: const AxisLine(color: AppColors.border),
                      labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                      numberFormat: NumberFormat.compactSimpleCurrency(locale: 'en_US'),
                      plotBands: plotBands,
                    ),
                    trackballBehavior: TrackballBehavior(
                      enable: true,
                      activationMode: ActivationMode.singleTap,
                      tooltipDisplayMode: TrackballDisplayMode.floatAllPoints,
                    ),
                    series: <CandleSeries<ChartData, DateTime>>[
                      CandleSeries<ChartData, DateTime>(
                        dataSource: _candles,
                        xValueMapper: (ChartData d, _) => d.date,
                        lowValueMapper: (ChartData d, _) => d.low,
                        highValueMapper: (ChartData d, _) => d.high,
                        openValueMapper: (ChartData d, _) => d.open,
                        closeValueMapper: (ChartData d, _) => d.close,
                        bearColor: AppColors.bear,
                        bullColor: AppColors.bull,
                        enableSolidCandles: true,
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar', style: TextStyle(color: AppColors.textSecondary)),
        ),
      ],
    );
  }

  Widget _buildTfButton(String tf) {
    final selected = _timeframe == tf;
    return InkWell(
      onTap: () {
        if (_timeframe != tf) {
          setState(() => _timeframe = tf);
          _cargarVelas();
        }
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: 0.8,
          ),
        ),
        child: Text(
          tf,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
