import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';

import '../providers/chart_provider.dart';
import '../../watchlist/providers/watchlist_provider.dart';
import '../../tracker/providers/tracker_provider.dart';
import '../../tracker/domain/transaction_model.dart';

class ChartScreen extends StatefulWidget {
  const ChartScreen({Key? key}) : super(key: key);

  @override
  _ChartScreenState createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> {
  ChartSeriesController? _chartSeriesController;
  String? _lastLoadedSymbol;
  String? _lastLoadedExchange;
  String? _lastLoadedInterval;
  String? _draggingLine; // 'start', 'end', or null
  int? _draggingDrawingIndex;
  int? _draggingDrawingId;
  double? _visibleMinY;
  double? _visibleMaxY;
  DateTime? _visibleMinX;
  DateTime? _visibleMaxX;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final watchlistProvider = Provider.of<WatchlistProvider>(context);
    final chartProvider = Provider.of<ChartProvider>(context, listen: false);
    
    // Only load if the exchange, symbol, or interval has actually changed
    if (_lastLoadedSymbol != watchlistProvider.selectedSymbol ||
        _lastLoadedExchange != watchlistProvider.currentExchange ||
        _lastLoadedInterval != chartProvider.activeInterval) {
      
      _lastLoadedSymbol = watchlistProvider.selectedSymbol;
      _lastLoadedExchange = watchlistProvider.currentExchange;
      _lastLoadedInterval = chartProvider.activeInterval;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        chartProvider.loadChartData(
          watchlistProvider.currentExchange,
          watchlistProvider.selectedSymbol,
        );
      });
    }
  }

  // Dialog to save new line drawing
  Future<void> _showAddLineDialog(double price) async {
    final chartProvider = Provider.of<ChartProvider>(context, listen: false);
    final watchlistProvider = Provider.of<WatchlistProvider>(context, listen: false);
    final labelController = TextEditingController(text: 'Línea de Soporte/Resistencia');
    String selectedColor = '#F0B90B'; // default gold

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF171A22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF263238)),
              ),
              title: const Text(
                'Añadir Línea Horizontal',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Precio: \$${price.toStringAsFixed(2)}',
                    style: const TextStyle(color: Color(0xFF00E6B8), fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: labelController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Etiqueta',
                      labelStyle: TextStyle(color: Color(0xFF90A4AE)),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF263238))),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF00E6B8))),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Color:', style: TextStyle(color: Color(0xFF90A4AE))),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _colorOption('#F0B90B', selectedColor, () => setState(() => selectedColor = '#F0B90B')), // Gold
                      _colorOption('#F6465D', selectedColor, () => setState(() => selectedColor = '#F6465D')), // Red
                      _colorOption('#0ECB81', selectedColor, () => setState(() => selectedColor = '#0ECB81')), // Green
                      _colorOption('#00E6B8', selectedColor, () => setState(() => selectedColor = '#00E6B8')), // Cyan
                      _colorOption('#29B6F6', selectedColor, () => setState(() => selectedColor = '#29B6F6')), // Blue
                    ],
                  )
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar', style: TextStyle(color: Color(0xFF546E7A))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E6B8),
                    foregroundColor: const Color(0xFF0C0F14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    // Add drawing to DB
                    await chartProvider.addDrawing(
                      exchange: watchlistProvider.currentExchange,
                      symbol: watchlistProvider.selectedSymbol,
                      price: price,
                      color: selectedColor,
                      label: labelController.text,
                    );
                    // Turn off drawing mode automatically
                    chartProvider.setActiveTool('none');
                  },
                  child: const Text('Guardar'),
                )
              ],
            );
          },
        );
      },
    );
  }

  Widget _colorOption(String hexColor, String currentSelected, VoidCallback onTap) {
    final bool isSelected = hexColor == currentSelected;
    final int colorVal = int.parse(hexColor.replaceFirst('#', '0xFF'));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Color(colorVal),
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: Colors.white, width: 2)
              : Border.all(color: Colors.transparent),
        ),
      ),
    );
  }

  Widget _timeframeButton(
    BuildContext context,
    ChartProvider chartProvider,
    WatchlistProvider watchlistProvider,
    String interval,
    String label,
  ) {
    final bool isActive = chartProvider.activeInterval == interval;
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: isActive ? const Color(0xFF00E6B8) : const Color(0xFF90A4AE),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        minimumSize: const Size(40, 32),
      ),
      onPressed: () {
        chartProvider.changeInterval(
          interval,
          watchlistProvider.currentExchange,
          watchlistProvider.selectedSymbol,
        );
      },
      child: Text(
        label,
        style: TextStyle(
          fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _toolButton({
    required BuildContext context,
    required ChartProvider chartProvider,
    required String tool,
    required IconData icon,
    required String tooltip,
  }) {
    final bool isActive = chartProvider.activeTool == tool;
    return IconButton(
      icon: Icon(icon, size: 20),
      color: isActive ? const Color(0xFF00E6B8) : const Color(0xFF90A4AE),
      tooltip: tooltip,
      onPressed: () {
        chartProvider.setActiveTool(tool);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xFF171A22),
            content: Text(
              tool == 'none'
                  ? 'Modo Navegación Activo: Desplaza y haz zoom sobre el gráfico.'
                  : tool == 'horizontal_line'
                      ? 'Línea Horizontal Activa: Toca el gráfico para colocar soporte/resistencia.'
                      : 'Regla de Medida Activa: Toca el precio de inicio y luego el final para medir %.',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      },
    );
  }

  void _showClearAllConfirmDialog(
    BuildContext context,
    ChartProvider chartProvider,
    String exchange,
    String symbol,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF171A22),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF263238)),
          ),
          title: const Text(
            '¿Limpiar todos los dibujos?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'Se eliminarán de forma permanente todas las líneas guardadas y mediciones en $symbol.',
            style: const TextStyle(color: Color(0xFF90A4AE)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: Color(0xFF546E7A))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF6465D),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.pop(context);
                chartProvider.clearAllDrawings(exchange, symbol);
              },
              child: const Text('Limpiar Todo'),
            )
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final chartProvider = Provider.of<ChartProvider>(context);
    final watchlistProvider = Provider.of<WatchlistProvider>(context);
    final trackerProvider = Provider.of<TrackerProvider>(context);

    final String currentSymbol = watchlistProvider.selectedSymbol;
    final String currentExchange = watchlistProvider.currentExchange;

    // Map raw Map candles to ChartData models
    final List<ChartData> chartData = chartProvider.candles.map<ChartData>((c) {
      final date = DateTime.fromMillisecondsSinceEpoch((c['time'] as int) * 1000);
      return ChartData(
        date: date,
        open: (c['open'] as num).toDouble(),
        high: (c['high'] as num).toDouble(),
        low: (c['low'] as num).toDouble(),
        close: (c['close'] as num).toDouble(),
      );
    }).toList();

    // Map SQLite drawings to PlotBands
    final List<PlotBand> plotBands = chartProvider.drawings.map<PlotBand>((d) {
      final double price = d['price'];
      final String colorHex = d['color'];
      final String label = d['label'];
      final int colorVal = int.parse(colorHex.replaceFirst('#', '0xFF'));

      return PlotBand(
        isVisible: true,
        start: price,
        end: price,
        borderColor: Color(colorVal),
        borderWidth: 1.5,
        dashArray: const <double>[6, 4], // Dashed line
        text: '  $label: \$${price.toStringAsFixed(2)}',
        textStyle: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
        horizontalTextAlignment: TextAnchor.start,
        verticalTextAlignment: TextAnchor.middle,
      );
    }).toList();

    // --- Automatic Purchase Lines Integration ---
    // Fetch unmatched buys from tracker that match current pair + exchange
    final List<TransactionModel> activeBuys = trackerProvider.openBuys
        .where((tx) => tx.symbol.toLowerCase() == currentSymbol.toLowerCase() &&
                       tx.exchange.toLowerCase() == currentExchange.toLowerCase())
        .toList();

    for (var buy in activeBuys) {
      plotBands.add(
        PlotBand(
          isVisible: true,
          start: buy.price,
          end: buy.price,
          borderColor: const Color(0xFF29B6F6), // Light blue for purchase lines
          borderWidth: 1.5,
          dashArray: const <double>[3, 3], // dotted line
          text: '  COMPRA: \$${buy.price.toStringAsFixed(2)} (${buy.amount.toStringAsFixed(4)} tokens)',
          textStyle: const TextStyle(color: Color(0xFF29B6F6), fontSize: 10, fontWeight: FontWeight.bold),
          horizontalTextAlignment: TextAnchor.start,
          verticalTextAlignment: TextAnchor.end,
        ),
      );
    }

    // --- Ruler/Percentage Measurement Bands ---
    // If ruler is started but not finished, show starting horizontal line
    if (chartProvider.rulerStartPrice != null && chartProvider.rulerEndPrice == null) {
      plotBands.add(
        PlotBand(
          isVisible: true,
          start: chartProvider.rulerStartPrice!,
          end: chartProvider.rulerStartPrice!,
          borderColor: const Color(0xFF00E6B8),
          borderWidth: 1.5,
          dashArray: const <double>[4, 4],
          text: '  Inicio de Medida: \$${chartProvider.rulerStartPrice!.toStringAsFixed(2)}',
          textStyle: const TextStyle(color: Color(0xFF00E6B8), fontSize: 10),
          horizontalTextAlignment: TextAnchor.start,
        ),
      );
    }



    return Scaffold(
      backgroundColor: const Color(0xFF0C0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12161F),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currentSymbol,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              currentExchange,
              style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              chartProvider.loadChartData(currentExchange, currentSymbol);
              trackerProvider.loadData(); // Sync purchase ledger too
            },
          )
        ],
      ),
      body: Column(
        children: [
          // Timeframe Selector Bar
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF12161F),
              border: Border(
                bottom: BorderSide(color: Color(0xFF161A1E), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _timeframeButton(context, chartProvider, watchlistProvider, '1m', '1m'),
                _timeframeButton(context, chartProvider, watchlistProvider, '5m', '5m'),
                _timeframeButton(context, chartProvider, watchlistProvider, '15m', '15m'),
                _timeframeButton(context, chartProvider, watchlistProvider, '1h', '1h'),
                _timeframeButton(context, chartProvider, watchlistProvider, '4h', '4h'),
                _timeframeButton(context, chartProvider, watchlistProvider, '1d', '1d'),
              ],
            ),
          ),

          // The Native Chart Container
          Expanded(
            flex: 3,
            child: Container(
              color: const Color(0xFF0B0E11),
              padding: const EdgeInsets.only(top: 8, right: 8),
              child: Stack(
                children: [
                  if (chartData.isEmpty && !chartProvider.isLoading)
                    const Center(
                      child: Text(
                        'No hay datos de velas para este par.',
                        style: TextStyle(color: Color(0xFF546E7A)),
                      ),
                    )
                  else
                    SfCartesianChart(
                      backgroundColor: const Color(0xFF0B0E11),
                      plotAreaBorderWidth: 0,
                      onChartTouchInteractionDown: (ChartTouchInteractionArgs args) {
                        if (_chartSeriesController == null) return;
                        
                        final CartesianChartPoint<dynamic>? tappedPoint =
                            _chartSeriesController!.pixelToPoint(args.position);
                        if (tappedPoint == null || tappedPoint.y == null || tappedPoint.x == null) return;

                        final chartProvider = Provider.of<ChartProvider>(context, listen: false);

                        DateTime tappedTime;
                        if (tappedPoint.x is DateTime) {
                          tappedTime = tappedPoint.x as DateTime;
                        } else {
                          tappedTime = DateTime.fromMillisecondsSinceEpoch((tappedPoint.x as num).toInt());
                        }

                        final double touchY = args.position.dy;
                        final double touchX = args.position.dx;
                        final double tappedPrice = (tappedPoint.y as num).toDouble();

                        // 1. Check if user tapped close to ruler lines (only if ruler has been started)
                        if (chartProvider.rulerStartPrice != null) {
                          // Y-coordinates of start/end horizontal boundaries
                          final Offset startPixel = _chartSeriesController!.pointToPixel(
                            CartesianChartPoint<DateTime>(x: tappedTime, y: chartProvider.rulerStartPrice!),
                          );
                          final double startPixelY = startPixel.dy;
                          
                          double? endPixelY;
                          if (chartProvider.rulerEndPrice != null) {
                            final Offset endPixel = _chartSeriesController!.pointToPixel(
                              CartesianChartPoint<DateTime>(x: tappedTime, y: chartProvider.rulerEndPrice!),
                            );
                            endPixelY = endPixel.dy;
                          }

                          // X-coordinates of start/end vertical boundaries
                          double? startTimePixelX;
                          double? endTimePixelX;
                          if (chartProvider.rulerStartTime != null) {
                            final Offset startXPixel = _chartSeriesController!.pointToPixel(
                              CartesianChartPoint<DateTime>(x: chartProvider.rulerStartTime!, y: tappedPrice),
                            );
                            startTimePixelX = startXPixel.dx;
                          }
                          if (chartProvider.rulerEndTime != null) {
                            final Offset endXPixel = _chartSeriesController!.pointToPixel(
                              CartesianChartPoint<DateTime>(x: chartProvider.rulerEndTime!, y: tappedPrice),
                            );
                            endTimePixelX = endXPixel.dx;
                          }

                          final double distStart = (touchY - startPixelY).abs();
                          final double distEnd = endPixelY != null ? (touchY - endPixelY).abs() : double.infinity;
                          final double distStartTime = startTimePixelX != null ? (touchX - startTimePixelX).abs() : double.infinity;
                          final double distEndTime = endTimePixelX != null ? (touchX - endTimePixelX).abs() : double.infinity;

                          // Find closest line out of the 4 boundaries
                          final double minDist = [distStart, distEnd, distStartTime, distEndTime]
                              .reduce((a, b) => a < b ? a : b);

                          if (minDist < 28.0) {
                            if (minDist == distEnd) {
                              setState(() {
                                _draggingLine = 'end';
                              });
                            } else if (minDist == distStart) {
                              setState(() {
                                _draggingLine = 'start';
                              });
                            } else if (minDist == distEndTime) {
                              setState(() {
                                _draggingLine = 'endTime';
                              });
                            } else if (minDist == distStartTime) {
                              setState(() {
                                _draggingLine = 'startTime';
                              });
                            }
                            return; // Target found, stop looking
                          }
                        }

                        // 2. Check if user tapped close to any horizontal drawing line (Support/Resistance)
                        for (int i = 0; i < chartProvider.drawings.length; i++) {
                          final drawing = chartProvider.drawings[i];
                          final double price = drawing['price'];
                          final int id = drawing['id'];

                          final Offset linePixel = _chartSeriesController!.pointToPixel(
                            CartesianChartPoint<DateTime>(x: tappedTime, y: price),
                          );
                          final double linePixelY = linePixel.dy;
                          final double dist = (touchY - linePixelY).abs();

                          // Standard touch target threshold of 28 logical pixels
                          if (dist < 28.0) {
                            setState(() {
                              _draggingLine = 'drawing';
                              _draggingDrawingIndex = i;
                              _draggingDrawingId = id;
                            });
                            return; // Target found, stop looking
                          }
                        }

                        // No dragging target found
                        setState(() {
                          _draggingLine = null;
                          _draggingDrawingIndex = null;
                          _draggingDrawingId = null;
                        });
                      },
                      onChartTouchInteractionMove: (ChartTouchInteractionArgs args) {
                        if (_draggingLine == null || _chartSeriesController == null) return;

                        final CartesianChartPoint<dynamic>? tappedPoint =
                            _chartSeriesController!.pixelToPoint(args.position);
                        if (tappedPoint == null || tappedPoint.y == null || tappedPoint.x == null) return;

                        final double newPrice = (tappedPoint.y as num).toDouble();
                        
                        DateTime newTime;
                        if (tappedPoint.x is DateTime) {
                          newTime = tappedPoint.x as DateTime;
                        } else {
                          newTime = DateTime.fromMillisecondsSinceEpoch((tappedPoint.x as num).toInt());
                        }

                        final chartProvider = Provider.of<ChartProvider>(context, listen: false);

                        if (_draggingLine == 'start') {
                          chartProvider.updateRulerStartPrice(newPrice);
                        } else if (_draggingLine == 'end') {
                          chartProvider.updateRulerEndPrice(newPrice);
                        } else if (_draggingLine == 'startTime') {
                          chartProvider.updateRulerStartTime(newTime);
                        } else if (_draggingLine == 'endTime') {
                          chartProvider.updateRulerEndTime(newTime);
                        } else if (_draggingLine == 'drawing' && _draggingDrawingIndex != null) {
                          chartProvider.updateDrawingPriceInMemory(_draggingDrawingIndex!, newPrice);
                        }
                      },
                      onChartTouchInteractionUp: (ChartTouchInteractionArgs args) {
                        if (_draggingLine != null) {
                          final chartProvider = Provider.of<ChartProvider>(context, listen: false);
                          
                          // Save drawing changes to SQLite DB on drag release
                          if (_draggingLine == 'drawing' &&
                              _draggingDrawingId != null &&
                              _draggingDrawingIndex != null) {
                            final double finalPrice =
                                chartProvider.drawings[_draggingDrawingIndex!]['price'];
                            chartProvider.saveDrawingPrice(
                              _draggingDrawingId!,
                              finalPrice,
                              currentExchange,
                              currentSymbol,
                            );
                          }

                          setState(() {
                            _draggingLine = null;
                            _draggingDrawingIndex = null;
                            _draggingDrawingId = null;
                          });
                          return; // Consume drag end to avoid drawing a new point
                        }

                        if (_chartSeriesController == null) return;
                        
                        final CartesianChartPoint<dynamic>? tappedPoint =
                            _chartSeriesController!.pixelToPoint(args.position);
                        if (tappedPoint == null || tappedPoint.y == null || tappedPoint.x == null) return;

                        final double tappedPrice = (tappedPoint.y as num).toDouble();
                        
                        DateTime tappedTime;
                        if (tappedPoint.x is DateTime) {
                          tappedTime = tappedPoint.x as DateTime;
                        } else {
                          tappedTime = DateTime.fromMillisecondsSinceEpoch((tappedPoint.x as num).toInt());
                        }

                        if (chartProvider.activeTool == 'horizontal_line') {
                          _showAddLineDialog(tappedPrice);
                        } else if (chartProvider.activeTool == 'ruler') {
                          chartProvider.handleRulerTap(tappedPrice, tappedTime);
                        }
                      },
                      zoomPanBehavior: ZoomPanBehavior(
                        enablePinching: true,
                        enablePanning: chartProvider.activeTool == 'none' && _draggingLine == null, // disable pan when drawing or dragging
                        enableMouseWheelZooming: true,
                        zoomMode: ZoomMode.x,
                      ),
                      crosshairBehavior: CrosshairBehavior(
                        enable: true,
                        lineType: CrosshairLineType.horizontal,
                        activationMode: ActivationMode.singleTap,
                        lineColor: const Color(0xFF00E6B8),
                        lineWidth: 1,
                        lineDashArray: const <double>[4, 3],
                      ),
                      onActualRangeChanged: (ActualRangeChangedArgs args) {
                        if (args.axisName == 'primaryYAxis') {
                          _visibleMinY = args.visibleMin.toDouble();
                          _visibleMaxY = args.visibleMax.toDouble();
                        } else if (args.axisName == 'primaryXAxis') {
                          _visibleMinX = DateTime.fromMillisecondsSinceEpoch(args.visibleMin.toInt());
                          _visibleMaxX = DateTime.fromMillisecondsSinceEpoch(args.visibleMax.toInt());
                        }
                      },
                      primaryXAxis: DateTimeAxis(
                        dateFormat: DateFormat.MMMd(),
                        majorGridLines: const MajorGridLines(color: Color(0xFF161A1E), width: 0.5),
                        borderColor: Colors.transparent,
                        axisLine: const AxisLine(color: Color(0xFF161A1E)),
                        minimum: _draggingLine != null ? _visibleMinX : null,
                        maximum: _draggingLine != null ? _visibleMaxX : null,
                      ),
                      primaryYAxis: NumericAxis(
                        opposedPosition: true,
                        numberFormat: NumberFormat.simpleCurrency(decimalDigits: 2),
                        majorGridLines: const MajorGridLines(color: Color(0xFF161A1E), width: 0.5),
                        borderColor: Colors.transparent,
                        axisLine: const AxisLine(color: Color(0xFF161A1E)),
                        plotBands: plotBands,
                        minimum: _draggingLine != null ? _visibleMinY : null,
                        maximum: _draggingLine != null ? _visibleMaxY : null,
                      ),
                      // --- Ruler Percentage Overlay Box Annotation ---
                      annotations: <CartesianChartAnnotation>[
                        if (chartProvider.rulerStartPrice != null &&
                            chartProvider.rulerEndPrice != null &&
                            chartProvider.rulerStartTime != null &&
                            chartProvider.rulerEndTime != null)
                          CartesianChartAnnotation(
                            widget: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: (chartProvider.rulerEndPrice! >= chartProvider.rulerStartPrice!
                                    ? const Color(0xFF0ECB81)
                                    : const Color(0xFFF6465D)),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white, width: 0.5),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${chartProvider.rulerPercent! >= 0 ? '+' : ''}${chartProvider.rulerPercent!.toStringAsFixed(2)}%',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                                  ),
                                  Text(
                                    '\$${(chartProvider.rulerEndPrice! - chartProvider.rulerStartPrice!).toStringAsFixed(2)}',
                                    style: const TextStyle(color: Colors.white70, fontSize: 9),
                                  ),
                                ],
                              ),
                            ),
                            coordinateUnit: CoordinateUnit.point,
                            x: DateTime.fromMillisecondsSinceEpoch(
                              (chartProvider.rulerStartTime!.millisecondsSinceEpoch +
                                      chartProvider.rulerEndTime!.millisecondsSinceEpoch) ~/
                                  2,
                            ),
                            y: (chartProvider.rulerStartPrice! + chartProvider.rulerEndPrice!) / 2,
                            horizontalAlignment: ChartAlignment.center,
                            verticalAlignment: ChartAlignment.center,
                          ),
                      ],
                      series: <CartesianSeries>[
                        CandleSeries<ChartData, DateTime>(
                          animationDuration: 0,
                          onRendererCreated: (ChartSeriesController controller) {
                            _chartSeriesController = controller;
                          },
                          dataSource: chartData,
                          name: currentSymbol,
                          xValueMapper: (ChartData data, _) => data.date,
                          lowValueMapper: (ChartData data, _) => data.low,
                          highValueMapper: (ChartData data, _) => data.high,
                          openValueMapper: (ChartData data, _) => data.open,
                          closeValueMapper: (ChartData data, _) => data.close,
                          enableSolidCandles: true,
                          bearColor: const Color(0xFFF6465D),
                          bullColor: const Color(0xFF0ECB81),
                        ),
                        if (chartProvider.rulerStartPrice != null &&
                            chartProvider.rulerEndPrice != null &&
                            chartProvider.rulerStartTime != null &&
                            chartProvider.rulerEndTime != null)
                          RangeAreaSeries<RulerData, DateTime>(
                            animationDuration: 0,
                            dataSource: [
                              RulerData(
                                chartProvider.rulerStartTime!,
                                chartProvider.rulerStartPrice! < chartProvider.rulerEndPrice!
                                    ? chartProvider.rulerStartPrice!
                                    : chartProvider.rulerEndPrice!,
                                chartProvider.rulerStartPrice! > chartProvider.rulerEndPrice!
                                    ? chartProvider.rulerStartPrice!
                                    : chartProvider.rulerEndPrice!,
                              ),
                              RulerData(
                                chartProvider.rulerEndTime!,
                                chartProvider.rulerStartPrice! < chartProvider.rulerEndPrice!
                                    ? chartProvider.rulerStartPrice!
                                    : chartProvider.rulerEndPrice!,
                                chartProvider.rulerStartPrice! > chartProvider.rulerEndPrice!
                                    ? chartProvider.rulerStartPrice!
                                    : chartProvider.rulerEndPrice!,
                              ),
                            ],
                            xValueMapper: (RulerData data, _) => data.time,
                            lowValueMapper: (RulerData data, _) => data.low,
                            highValueMapper: (RulerData data, _) => data.high,
                            color: (chartProvider.rulerEndPrice! >= chartProvider.rulerStartPrice!
                                    ? const Color(0xFF0ECB81)
                                    : const Color(0xFFF6465D))
                                .withValues(alpha: 0.15),
                            borderColor: chartProvider.rulerEndPrice! >= chartProvider.rulerStartPrice!
                                ? const Color(0xFF0ECB81)
                                : const Color(0xFFF6465D),
                            borderWidth: 1.5,
                          ),
                      ],
                    ),
                  if (chartProvider.isLoading)
                    const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00E6B8)),
                      ),
                    ),
                  if (chartProvider.activeTool != 'none')
                    Positioned(
                      top: 10,
                      left: 10,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E6B8).withOpacity(0.9),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 4),
                          ],
                        ),
                        child: Row(
                          children: [
                            Icon(
                              chartProvider.activeTool == 'horizontal_line'
                                  ? Icons.border_horizontal
                                  : Icons.square_foot,
                              color: const Color(0xFF0C0F14),
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              chartProvider.activeTool == 'horizontal_line'
                                  ? 'DIBUJO: LÍNEA HORIZONTAL'
                                  : chartProvider.rulerStartPrice == null
                                      ? 'REGLA: MARCA INICIO'
                                      : 'REGLA: MARCA FIN',
                              style: const TextStyle(
                                color: Color(0xFF0C0F14),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                ],
              ),
            ),
          ),

          // Drawing Toolbar (TabTrader Style)
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: Color(0xFF171A22),
              border: Border(
                top: BorderSide(color: Color(0xFF263238), width: 1),
                bottom: BorderSide(color: Color(0xFF263238), width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _toolButton(
                  context: context,
                  chartProvider: chartProvider,
                  tool: 'none',
                  icon: Icons.navigation_outlined,
                  tooltip: 'Desactivar Dibujo (Navegar)',
                ),
                _toolButton(
                  context: context,
                  chartProvider: chartProvider,
                  tool: 'horizontal_line',
                  icon: Icons.border_horizontal,
                  tooltip: 'Línea Horizontal (Soporte/Resistencia)',
                ),
                _toolButton(
                  context: context,
                  chartProvider: chartProvider,
                  tool: 'ruler',
                  icon: Icons.square_foot_outlined,
                  tooltip: 'Regla de Medida (% de Ganancia)',
                ),
                // Clear active ruler
                IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  color: chartProvider.rulerStartPrice != null ? const Color(0xFFF6465D) : const Color(0xFF546E7A),
                  tooltip: 'Limpiar Medición',
                  onPressed: chartProvider.rulerStartPrice != null
                      ? () => chartProvider.clearRuler()
                      : null,
                ),
                // Clear all drawings confirmation
                IconButton(
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  color: const Color(0xFF90A4AE),
                  tooltip: 'Borrar Todo',
                  onPressed: () {
                    _showClearAllConfirmDialog(
                      context,
                      chartProvider,
                      currentExchange,
                      currentSymbol,
                    );
                  },
                ),
              ],
            ),
          ),

          // Drawings List Panel
          Expanded(
            flex: 1,
            child: Container(
              color: const Color(0xFF12161F),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: const Color(0xFF171A22),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'SOPORTES Y RESISTENCIAS DIBUJADOS',
                          style: TextStyle(color: Color(0xFF90A4AE), fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                        Text(
                          '${chartProvider.drawings.length} líneas',
                          style: const TextStyle(color: Color(0xFF00E6B8), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: chartProvider.drawings.isEmpty
                        ? const Center(
                            child: Text(
                              'No hay líneas guardadas en este par.',
                              style: TextStyle(color: Color(0xFF546E7A), fontSize: 13),
                            ),
                          )
                        : ListView.builder(
                            physics: const BouncingScrollPhysics(),
                            itemCount: chartProvider.drawings.length,
                            itemBuilder: (context, index) {
                              final drawing = chartProvider.drawings[index];
                              final int id = drawing['id'];
                              final double price = drawing['price'];
                              final String colorHex = drawing['color'];
                              final String label = drawing['label'];
                              
                              final int colorVal = int.parse(colorHex.replaceFirst('#', '0xFF'));

                              return ListTile(
                                leading: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: Color(colorVal),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                title: Text(
                                  label,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                subtitle: Text(
                                  'Precio: \$${price.toStringAsFixed(2)}',
                                  style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 12),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Color(0xFFF6465D), size: 20),
                                  onPressed: () {
                                    chartProvider.deleteDrawing(
                                      id,
                                      currentExchange,
                                      currentSymbol,
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}

class ChartData {
  final DateTime date;
  final double open;
  final double high;
  final double low;
  final double close;

  ChartData({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });
}

class RulerData {
  RulerData(this.time, this.low, this.high);
  final DateTime time;
  final double low;
  final double high;
}
