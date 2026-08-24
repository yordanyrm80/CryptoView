import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../domain/models/chart_candle_model.dart';
import '../providers/chart_provider.dart';
import '../../watchlist/providers/watchlist_provider.dart';
import '../../tracker/providers/tracker_provider.dart';
import '../../tracker/domain/transaction_model.dart';
import '../../settings/providers/settings_provider.dart';
import '../../settings/presentation/settings_screen.dart';
import 'widgets/timeframe_selector_bar.dart';
import 'widgets/chart_drawing_dialog.dart';
import 'widgets/chart_active_tool_chip.dart';
import 'widgets/chart_toolbar.dart';
import 'widgets/chart_drawing_list_panel.dart';
import 'widgets/chart_layers_dialog.dart';
import '../../orderbook/presentation/orderbook_screen.dart';
import '../../orderbook/providers/orderbook_provider.dart';
import '../../trading/presentation/trading_panel_screen.dart';
import '../../trading/providers/trading_provider.dart';

class ChartScreen extends StatefulWidget {
  const ChartScreen({Key? key}) : super(key: key);

  @override
  _ChartScreenState createState() => _ChartScreenState();
}

class _ChartScreenState extends State<ChartScreen> with SingleTickerProviderStateMixin {
  late TabController _mainTabController;
  ChartSeriesController? _chartSeriesController;
  String? _lastLoadedSymbol;
  String? _lastLoadedExchange;
  String? _lastLoadedInterval;
  String? _draggingLine;
  int? _draggingDrawingIndex;
  int? _draggingDrawingId;
  double? _visibleMinY;
  double? _visibleMaxY;
  DateTime? _visibleMinX;
  DateTime? _visibleMaxX;

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 3, vsync: this);
    _mainTabController.addListener(_handleTabChange);
  }

  void _handleTabChange() {
    if (!mounted) return;
    final orderBookProvider = Provider.of<OrderBookProvider>(context, listen: false);
    if (_mainTabController.index == 1) {
      orderBookProvider.startPolling();
    } else {
      orderBookProvider.stopPolling();
    }
  }

  @override
  void dispose() {
    _mainTabController.removeListener(_handleTabChange);
    _mainTabController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final watchlistProvider = Provider.of<WatchlistProvider>(context);
    final chartProvider = Provider.of<ChartProvider>(context, listen: false);

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

  Future<void> _showAddLineDialog(double price, WatchlistProvider watchlistProvider, ChartProvider chartProvider) async {
    showDialog(
      context: context,
      builder: (_) => ChartDrawingDialog(
        price: price,
        onSave: (label, color) async {
          await chartProvider.addDrawing(
            exchange: watchlistProvider.currentExchange,
            symbol: watchlistProvider.selectedSymbol,
            price: price,
            color: color,
            label: label,
          );
          chartProvider.setActiveTool('none');
        },
      ),
    );
  }

  void _showClearAllConfirmDialog(BuildContext context, ChartProvider chartProvider, String exchange, String symbol) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text('¿Limpiar todos los dibujos?', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: Text('Se eliminarán de forma permanente todas las líneas guardadas y mediciones en $symbol.', style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.bear, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () {
              Navigator.pop(context);
              chartProvider.clearAllDrawings(exchange, symbol);
            },
            child: const Text('Limpiar Todo'),
          )
        ],
      ),
    );
  }

  void _showChartLayersDialog(BuildContext context, SettingsProvider settingsProvider) {
    showDialog(
      context: context,
      builder: (_) => ChartLayersDialog(settingsProvider: settingsProvider),
    );
  }

  void _showCoinSelectorModal(BuildContext context, WatchlistProvider watchlistProvider, ChartProvider chartProvider) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Seleccionar Moneda (${watchlistProvider.currentExchange})',
                          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 18),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(color: AppColors.border, height: 1),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: watchlistProvider.symbols.length,
                  itemBuilder: (context, index) {
                    final symbol = watchlistProvider.symbols[index];
                    final price = watchlistProvider.prices[symbol];
                    final isSelected = watchlistProvider.selectedSymbol == symbol;
                    final isFavorite = watchlistProvider.isFavorite(symbol);

                    return ListTile(
                      leading: Icon(
                        isFavorite ? Icons.star : Icons.star_border,
                        color: isFavorite ? Colors.amber : AppColors.textMuted,
                        size: 20,
                      ),
                      title: Text(
                        symbol,
                        style: TextStyle(
                          color: isSelected ? AppColors.primary : AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      trailing: Text(
                        price != null && price > 0 ? '\$${price.toStringAsFixed(price < 1 ? 4 : 2)}' : '--',
                        style: TextStyle(
                          color: isSelected ? AppColors.primary : AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      selected: isSelected,
                      selectedTileColor: AppColors.cardSelected,
                      onTap: () {
                        watchlistProvider.changeSymbol(symbol);
                        chartProvider.loadChartData(watchlistProvider.currentExchange, symbol);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final chartProvider = Provider.of<ChartProvider>(context);
    final watchlistProvider = Provider.of<WatchlistProvider>(context);
    final trackerProvider = Provider.of<TrackerProvider>(context);
    final settingsProvider = Provider.of<SettingsProvider>(context);
    // Isolate trading provider listener: only rebuild ChartScreen if openOrders changes
    final openOrders = context.select<TradingProvider, List<OpenOrderItem>>((p) => p.openOrders);

    final String currentSymbol = watchlistProvider.selectedSymbol;
    final String currentExchange = watchlistProvider.currentExchange;
    final double? currentPrice = watchlistProvider.prices[currentSymbol];

    final List<ChartData> chartData = chartProvider.candles.map<ChartData>((c) {
      return ChartData(
        date: DateTime.fromMillisecondsSinceEpoch((c['time'] as int) * 1000),
        open: (c['open'] as num).toDouble(),
        high: (c['high'] as num).toDouble(),
        low: (c['low'] as num).toDouble(),
        close: (c['close'] as num).toDouble(),
      );
    }).toList();

    final List<PlotBand> plotBands = settingsProvider.showDrawings
        ? chartProvider.drawings.map<PlotBand>((d) {
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
              dashArray: const <double>[6, 4],
              text: settingsProvider.showDrawingLabels ? '  $label: \$${price.toStringAsFixed(2)}' : null,
              textStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 10, fontWeight: FontWeight.bold),
              horizontalTextAlignment: TextAnchor.start,
              verticalTextAlignment: TextAnchor.middle,
            );
          }).toList()
        : [];

    // 1. Current Market Price Line
    if (settingsProvider.showCurrentPriceLine && currentPrice != null && currentPrice > 0) {
      plotBands.add(
        PlotBand(
          isVisible: true,
          start: currentPrice,
          end: currentPrice,
          borderColor: settingsProvider.currentPriceColor,
          borderWidth: 1.5,
          dashArray: const <double>[5, 3],
          text: settingsProvider.showCurrentPriceLabel ? '  PRECIO: \$${currentPrice.toStringAsFixed(currentPrice < 1.0 ? 4 : 2)}' : null,
          textStyle: TextStyle(
            color: settingsProvider.currentPriceColor,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
          horizontalTextAlignment: TextAnchor.start,
          verticalTextAlignment: TextAnchor.middle,
        ),
      );
    }

    // 2. Automatic Purchase Lines Integration
    if (settingsProvider.showBuyLines) {
      final List<TransactionModel> activeBuys = trackerProvider.openBuys
          .where((tx) => tx.symbol.toLowerCase() == currentSymbol.toLowerCase() && tx.exchange.toLowerCase() == currentExchange.toLowerCase())
          .toList();

      for (var buy in activeBuys) {
        String pnlStr = '';
        if (currentPrice != null && currentPrice > 0) {
          final diffPct = ((currentPrice - buy.price) / buy.price) * 100;
          final sign = diffPct >= 0 ? '+' : '';
          pnlStr = ' · $sign${diffPct.toStringAsFixed(1)}%';
        }

        plotBands.add(
          PlotBand(
            isVisible: true,
            start: buy.price,
            end: buy.price,
            borderColor: settingsProvider.buyLineColor,
            borderWidth: 1.5,
            dashArray: const <double>[3, 3],
            text: settingsProvider.showBuyLabels ? '  COMPRA: \$${buy.price.toStringAsFixed(2)} (${buy.amount.toStringAsFixed(4)} tokens$pnlStr)' : null,
            textStyle: TextStyle(color: settingsProvider.buyLineColor, fontSize: 10, fontWeight: FontWeight.bold),
            horizontalTextAlignment: TextAnchor.start,
            verticalTextAlignment: TextAnchor.end,
          ),
        );
      }
    }

    // 3. Automatic Sell Lines Integration
    if (settingsProvider.showSellLines) {
      final List<TransactionModel> activeSells = trackerProvider.openSells
          .where((tx) => tx.symbol.toLowerCase() == currentSymbol.toLowerCase() && tx.exchange.toLowerCase() == currentExchange.toLowerCase())
          .toList();

      for (var sell in activeSells) {
        plotBands.add(
          PlotBand(
            isVisible: true,
            start: sell.price,
            end: sell.price,
            borderColor: settingsProvider.sellLineColor,
            borderWidth: 1.5,
            dashArray: const <double>[3, 3],
            text: settingsProvider.showSellLabels ? '  VENTA: \$${sell.price.toStringAsFixed(2)} (${sell.amount.toStringAsFixed(4)} tokens)' : null,
            textStyle: TextStyle(color: settingsProvider.sellLineColor, fontSize: 10, fontWeight: FontWeight.bold),
            horizontalTextAlignment: TextAnchor.start,
            verticalTextAlignment: TextAnchor.start,
          ),
        );
      }
    }

    // 4. Active Open Orders in Exchange (KuCoin / Binance)
    if (settingsProvider.showOpenOrders) {
      final activeOpenOrders = openOrders.where((o) =>
          o.symbol.replaceAll('-', '').replaceAll('/', '').toUpperCase() ==
          currentSymbol.replaceAll('-', '').replaceAll('/', '').toUpperCase());

      for (var order in activeOpenOrders) {
        final isBuyOrder = order.side == 'buy';
        final orderColor = isBuyOrder ? const Color(0xFF00E676) : const Color(0xFFFF5252);

        plotBands.add(
          PlotBand(
            isVisible: true,
            start: order.price,
            end: order.price,
            borderColor: orderColor,
            borderWidth: 2.0,
            dashArray: const <double>[8, 4],
            text: settingsProvider.showOpenOrderLabels
                ? '  ⏳ LÍMITE ${isBuyOrder ? "COMPRA" : "VENTA"}: \$${order.price.toStringAsFixed(order.price < 1.0 ? 4 : 2)} (${order.size.toStringAsFixed(4)})'
                : null,
            textStyle: TextStyle(
              color: orderColor,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
            horizontalTextAlignment: TextAnchor.start,
            verticalTextAlignment: TextAnchor.middle,
          ),
        );
      }
    }

    if (chartProvider.rulerStartPrice != null && chartProvider.rulerEndPrice == null) {
      plotBands.add(
        PlotBand(
          isVisible: true,
          start: chartProvider.rulerStartPrice!,
          end: chartProvider.rulerStartPrice!,
          borderColor: AppColors.primary,
          borderWidth: 1.5,
          dashArray: const <double>[4, 4],
          text: '  Inicio de Medida: \$${chartProvider.rulerStartPrice!.toStringAsFixed(2)}',
          textStyle: const TextStyle(color: AppColors.primary, fontSize: 10),
          horizontalTextAlignment: TextAnchor.start,
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _showCoinSelectorModal(context, watchlistProvider, chartProvider),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(currentSymbol, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                        const Icon(Icons.arrow_drop_down, color: AppColors.primary, size: 20),
                      ],
                    ),
                    Text(
                      currentPrice != null && currentPrice > 0
                          ? '\$${currentPrice.toStringAsFixed(currentPrice < 1.0 ? 4 : 2)} · $currentExchange'
                          : currentExchange,
                      style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
            tooltip: 'Recargar velas y operaciones',
            onPressed: () {
              chartProvider.loadChartData(currentExchange, currentSymbol);
              trackerProvider.loadData();
              watchlistProvider.fetchCurrentPrices();
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white70, size: 20),
            tooltip: 'Configuración General y Colores',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(38),
          child: Container(
            color: AppColors.card,
            child: TabBar(
              controller: _mainTabController,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2.5,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textMuted,
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.show_chart, size: 14),
                      SizedBox(width: 6),
                      Text('Gráfico'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.menu_book_outlined, size: 14),
                      SizedBox(width: 6),
                      Text('Libro de Órdenes'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bolt, size: 14),
                      SizedBox(width: 6),
                      Text('Operar'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _mainTabController,
        children: [
          _buildChartTabContent(
            context: context,
            chartProvider: chartProvider,
            watchlistProvider: watchlistProvider,
            trackerProvider: trackerProvider,
            settingsProvider: settingsProvider,
            currentSymbol: currentSymbol,
            currentExchange: currentExchange,
            currentPrice: currentPrice,
            chartData: chartData,
            plotBands: plotBands,
          ),
          OrderBookScreen(
            onPriceSelected: (price, side) {
              context.read<TradingProvider>().preloadFromPrice(price, side: side);
              _mainTabController.animateTo(2);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  duration: const Duration(seconds: 2),
                  backgroundColor: AppColors.primary,
                  content: Text(
                    'Precio \$${price.toStringAsFixed(price < 1.0 ? 4 : 2)} precargado en Panel de Trading.',
                    style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                  ),
                ),
              );
            },
          ),
          const TradingPanelScreen(),
        ],
      ),
    );
  }

  Widget _buildChartTabContent({
    required BuildContext context,
    required ChartProvider chartProvider,
    required WatchlistProvider watchlistProvider,
    required TrackerProvider trackerProvider,
    required SettingsProvider settingsProvider,
    required String currentSymbol,
    required String currentExchange,
    required double? currentPrice,
    required List<ChartData> chartData,
    required List<PlotBand> plotBands,
  }) {
    return Column(
      children: [
        TimeframeSelectorBar(
          chartProvider: chartProvider,
          currentExchange: currentExchange,
          currentSymbol: currentSymbol,
          onOpenLayers: () => _showChartLayersDialog(context, settingsProvider),
        ),
        Expanded(
          flex: 3,
          child: Container(
            color: const Color(0xFF0B0E11),
            padding: const EdgeInsets.only(top: 8, right: 8),
            child: Stack(
              children: [
                if (chartData.isEmpty && !chartProvider.isLoading)
                  const Center(
                    child: Text('No hay datos de velas para este par.', style: TextStyle(color: AppColors.textMuted)),
                  )
                else
                  SfCartesianChart(
                    backgroundColor: const Color(0xFF0B0E11),
                    plotAreaBorderWidth: 0,
                    onChartTouchInteractionDown: (ChartTouchInteractionArgs args) {
                      if (_chartSeriesController == null) return;
                      final CartesianChartPoint<dynamic>? tappedPoint = _chartSeriesController!.pixelToPoint(args.position);
                      if (tappedPoint == null || tappedPoint.y == null || tappedPoint.x == null) return;

                      DateTime tappedTime = tappedPoint.x is DateTime
                          ? tappedPoint.x as DateTime
                          : DateTime.fromMillisecondsSinceEpoch((tappedPoint.x as num).toInt());

                      final double touchY = args.position.dy;
                      final double touchX = args.position.dx;
                      final double tappedPrice = (tappedPoint.y as num).toDouble();

                      if (chartProvider.rulerStartPrice != null) {
                        final Offset startPixel = _chartSeriesController!.pointToPixel(
                          CartesianChartPoint<DateTime>(x: tappedTime, y: chartProvider.rulerStartPrice!),
                        );
                        double? endPixelY;
                        if (chartProvider.rulerEndPrice != null) {
                          endPixelY = _chartSeriesController!.pointToPixel(
                            CartesianChartPoint<DateTime>(x: tappedTime, y: chartProvider.rulerEndPrice!),
                          ).dy;
                        }
                        double? startTimePixelX;
                        double? endTimePixelX;
                        if (chartProvider.rulerStartTime != null) {
                          startTimePixelX = _chartSeriesController!.pointToPixel(
                            CartesianChartPoint<DateTime>(x: chartProvider.rulerStartTime!, y: tappedPrice),
                          ).dx;
                        }
                        if (chartProvider.rulerEndTime != null) {
                          endTimePixelX = _chartSeriesController!.pointToPixel(
                            CartesianChartPoint<DateTime>(x: chartProvider.rulerEndTime!, y: tappedPrice),
                          ).dx;
                        }

                        final double distStart = (touchY - startPixel.dy).abs();
                        final double distEnd = endPixelY != null ? (touchY - endPixelY).abs() : double.infinity;
                        final double distStartTime = startTimePixelX != null ? (touchX - startTimePixelX).abs() : double.infinity;
                        final double distEndTime = endTimePixelX != null ? (touchX - endTimePixelX).abs() : double.infinity;

                        final double minDist = [distStart, distEnd, distStartTime, distEndTime].reduce((a, b) => a < b ? a : b);

                        if (minDist < 28.0) {
                          setState(() {
                            if (minDist == distEnd) _draggingLine = 'end';
                            else if (minDist == distStart) _draggingLine = 'start';
                            else if (minDist == distEndTime) _draggingLine = 'endTime';
                            else if (minDist == distStartTime) _draggingLine = 'startTime';
                          });
                          return;
                        }
                      }

                      for (int i = 0; i < chartProvider.drawings.length; i++) {
                        final d = chartProvider.drawings[i];
                        final double linePrice = d['price'];
                        final Offset linePixel = _chartSeriesController!.pointToPixel(
                          CartesianChartPoint<DateTime>(x: tappedTime, y: linePrice),
                        );
                        final double dist = (touchY - linePixel.dy).abs();
                        if (dist < 20.0) {
                          setState(() {
                            _draggingLine = 'drawing';
                            _draggingDrawingIndex = i;
                            _draggingDrawingId = d['id'];
                          });
                          return;
                        }
                      }
                    },
                    onChartTouchInteractionMove: (ChartTouchInteractionArgs args) {
                      if (_draggingLine == null || _chartSeriesController == null) return;
                      final CartesianChartPoint<dynamic>? tappedPoint = _chartSeriesController!.pixelToPoint(args.position);
                      if (tappedPoint == null || tappedPoint.y == null || tappedPoint.x == null) return;

                      final double newPrice = (tappedPoint.y as num).toDouble();
                      DateTime newTime = tappedPoint.x is DateTime
                          ? tappedPoint.x as DateTime
                          : DateTime.fromMillisecondsSinceEpoch((tappedPoint.x as num).toInt());

                      if (_draggingLine == 'start') chartProvider.updateRulerStartPrice(newPrice);
                      else if (_draggingLine == 'end') chartProvider.updateRulerEndPrice(newPrice);
                      else if (_draggingLine == 'startTime') chartProvider.updateRulerStartTime(newTime);
                      else if (_draggingLine == 'endTime') chartProvider.updateRulerEndTime(newTime);
                      else if (_draggingLine == 'drawing' && _draggingDrawingIndex != null) {
                        chartProvider.updateDrawingPriceInMemory(_draggingDrawingIndex!, newPrice);
                      }
                    },
                    onChartTouchInteractionUp: (ChartTouchInteractionArgs args) {
                      if (_draggingLine != null) {
                        if (_draggingLine == 'drawing' && _draggingDrawingId != null && _draggingDrawingIndex != null) {
                          final double finalPrice = chartProvider.drawings[_draggingDrawingIndex!]['price'];
                          chartProvider.saveDrawingPrice(_draggingDrawingId!, finalPrice, currentExchange, currentSymbol);
                        }
                        setState(() {
                          _draggingLine = null;
                          _draggingDrawingIndex = null;
                          _draggingDrawingId = null;
                        });
                        return;
                      }

                      if (_chartSeriesController == null) return;
                      final CartesianChartPoint<dynamic>? tappedPoint = _chartSeriesController!.pixelToPoint(args.position);
                      if (tappedPoint == null || tappedPoint.y == null || tappedPoint.x == null) return;

                      final double tappedPrice = (tappedPoint.y as num).toDouble();
                      DateTime tappedTime = tappedPoint.x is DateTime
                          ? tappedPoint.x as DateTime
                          : DateTime.fromMillisecondsSinceEpoch((tappedPoint.x as num).toInt());

                      if (chartProvider.activeTool == 'horizontal_line') {
                        _showAddLineDialog(tappedPrice, watchlistProvider, chartProvider);
                      } else if (chartProvider.activeTool == 'ruler') {
                        chartProvider.handleRulerTap(tappedPrice, tappedTime);
                      } else if (chartProvider.activeTool == 'place_order') {
                        context.read<TradingProvider>().preloadFromPrice(tappedPrice);
                        chartProvider.setActiveTool('none');
                        _mainTabController.animateTo(2);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            duration: const Duration(seconds: 2),
                            backgroundColor: AppColors.primary,
                            content: Text(
                              'Precio \$${tappedPrice.toStringAsFixed(tappedPrice < 1.0 ? 4 : 2)} precargado en Panel de Trading.',
                              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                            ),
                          ),
                        );
                      }
                    },
                    zoomPanBehavior: ZoomPanBehavior(
                      enablePinching: true,
                      enablePanning: chartProvider.activeTool == 'none' && _draggingLine == null,
                      enableMouseWheelZooming: true,
                      zoomMode: ZoomMode.x,
                    ),
                    crosshairBehavior: CrosshairBehavior(
                      enable: true,
                      lineType: CrosshairLineType.horizontal,
                      activationMode: ActivationMode.singleTap,
                      lineColor: AppColors.primary,
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
                      majorGridLines: const MajorGridLines(color: AppColors.gridLine, width: 0.5),
                      borderColor: Colors.transparent,
                      axisLine: const AxisLine(color: AppColors.gridLine),
                      minimum: _draggingLine != null ? _visibleMinX : null,
                      maximum: _draggingLine != null ? _visibleMaxX : null,
                    ),
                    primaryYAxis: NumericAxis(
                      opposedPosition: true,
                      numberFormat: NumberFormat.simpleCurrency(decimalDigits: currentPrice != null && currentPrice < 1.0 ? 4 : 2),
                      majorGridLines: const MajorGridLines(color: AppColors.gridLine, width: 0.5),
                      borderColor: Colors.transparent,
                      axisLine: const AxisLine(color: AppColors.gridLine),
                      plotBands: plotBands,
                      minimum: _draggingLine != null ? _visibleMinY : null,
                      maximum: _draggingLine != null ? _visibleMaxY : null,
                    ),
                    annotations: <CartesianChartAnnotation>[
                      if (chartProvider.rulerStartPrice != null &&
                          chartProvider.rulerEndPrice != null &&
                          chartProvider.rulerStartTime != null &&
                          chartProvider.rulerEndTime != null)
                        CartesianChartAnnotation(
                          widget: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: (chartProvider.rulerEndPrice! >= chartProvider.rulerStartPrice! ? AppColors.bull : AppColors.bear).withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${chartProvider.rulerEndPrice! >= chartProvider.rulerStartPrice! ? '+' : ''}${(((chartProvider.rulerEndPrice! - chartProvider.rulerStartPrice!) / chartProvider.rulerStartPrice!) * 100).toStringAsFixed(2)}%',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ),
                          coordinateUnit: CoordinateUnit.point,
                          x: DateTime.fromMillisecondsSinceEpoch(
                            ((chartProvider.rulerStartTime!.millisecondsSinceEpoch + chartProvider.rulerEndTime!.millisecondsSinceEpoch) / 2).toInt(),
                          ),
                          y: (chartProvider.rulerStartPrice! + chartProvider.rulerEndPrice!) / 2,
                          horizontalAlignment: ChartAlignment.center,
                          verticalAlignment: ChartAlignment.center,
                        ),
                    ],
                    series: <CartesianSeries>[
                      CandleSeries<ChartData, DateTime>(
                        animationDuration: 0,
                        onRendererCreated: (controller) => _chartSeriesController = controller,
                        dataSource: chartData,
                        name: currentSymbol,
                        xValueMapper: (ChartData data, _) => data.date,
                        lowValueMapper: (ChartData data, _) => data.low,
                        highValueMapper: (ChartData data, _) => data.high,
                        openValueMapper: (ChartData data, _) => data.open,
                        closeValueMapper: (ChartData data, _) => data.close,
                        enableSolidCandles: true,
                        bearColor: AppColors.bear,
                        bullColor: AppColors.bull,
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
                              chartProvider.rulerStartPrice! < chartProvider.rulerEndPrice! ? chartProvider.rulerStartPrice! : chartProvider.rulerEndPrice!,
                              chartProvider.rulerStartPrice! > chartProvider.rulerEndPrice! ? chartProvider.rulerStartPrice! : chartProvider.rulerEndPrice!,
                            ),
                            RulerData(
                              chartProvider.rulerEndTime!,
                              chartProvider.rulerStartPrice! < chartProvider.rulerEndPrice! ? chartProvider.rulerStartPrice! : chartProvider.rulerEndPrice!,
                              chartProvider.rulerStartPrice! > chartProvider.rulerEndPrice! ? chartProvider.rulerStartPrice! : chartProvider.rulerEndPrice!,
                            ),
                          ],
                          xValueMapper: (RulerData data, _) => data.time,
                          lowValueMapper: (RulerData data, _) => data.low,
                          highValueMapper: (RulerData data, _) => data.high,
                          color: (chartProvider.rulerEndPrice! >= chartProvider.rulerStartPrice! ? AppColors.bull : AppColors.bear).withValues(alpha: 0.15),
                          borderColor: chartProvider.rulerEndPrice! >= chartProvider.rulerStartPrice! ? AppColors.bull : AppColors.bear,
                          borderWidth: 1.5,
                        ),
                    ],
                  ),
                if (chartProvider.isLoading)
                  const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary))),
                ChartActiveToolChip(
                  activeTool: chartProvider.activeTool,
                  hasRulerStart: chartProvider.rulerStartPrice != null,
                ),
              ],
            ),
          ),
        ),
        ChartToolbar(
          chartProvider: chartProvider,
          currentExchange: currentExchange,
          currentSymbol: currentSymbol,
          onClearAll: () => _showClearAllConfirmDialog(context, chartProvider, currentExchange, currentSymbol),
        ),
        Expanded(
          flex: 1,
          child: ChartDrawingListPanel(
            chartProvider: chartProvider,
            currentExchange: currentExchange,
            currentSymbol: currentSymbol,
          ),
        )
      ],
    );
  }
}
