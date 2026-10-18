import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/services/cloud_api_service.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/watchlist/providers/watchlist_provider.dart';
import 'features/chart/providers/chart_provider.dart';
import 'features/tracker/providers/tracker_provider.dart';
import 'features/watchlist/presentation/watchlist_screen.dart';
import 'features/chart/presentation/chart_screen.dart';
import 'features/tracker/presentation/tracker_screen.dart';
import 'features/exchanges/presentation/exchanges_screen.dart';

import 'features/settings/providers/settings_provider.dart';
import 'features/settings/presentation/settings_screen.dart';
import 'features/orderbook/providers/orderbook_provider.dart';
import 'features/trading/providers/trading_provider.dart';

import 'core/widgets/panel_resize_handle.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite for Desktop (Windows)
  if (!kIsWeb && Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => WatchlistProvider()),
        ChangeNotifierProvider(create: (_) => ChartProvider()),
        ChangeNotifierProvider(create: (_) => TrackerProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => OrderBookProvider()),
        ChangeNotifierProvider(create: (_) => TradingProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CryptoView',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainContainer(),
    );
  }
}

class MainContainer extends StatefulWidget {
  const MainContainer({Key? key}) : super(key: key);

  @override
  _MainContainerState createState() => _MainContainerState();
}

class _MainContainerState extends State<MainContainer> {
  int _currentIndex = 1; // Default to Chart screen on mobile
  bool _isWatchlistExpanded = true;
  bool _isTrackerExpanded = true;
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  final GlobalKey<ScaffoldState> _mobileScaffoldKey = GlobalKey<ScaffoldState>();

  void _showExchangesModal() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ExchangesScreen()),
    );
  }

  void _showSettingsModal() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _toggleBottomSheet() {
    if (_sheetController.isAttached) {
      if (_sheetController.size > 0.1) {
        _sheetController.animateTo(
          0.06,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        _sheetController.animateTo(
          0.55,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.of(context).size.width;
    final bool isWide = width > 950;
    final watchlistProvider = Provider.of<WatchlistProvider>(context);
    final trackerProvider = Provider.of<TrackerProvider>(context);
    final settingsProvider = Provider.of<SettingsProvider>(context);

    // ==========================================
    // 1. DESKTOP / WIDE SCREEN (Collapsible & Resizable Panels)
    // ==========================================
    if (isWide) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(42),
          child: Container(
            color: AppColors.card,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _isWatchlistExpanded ? Icons.menu_open : Icons.menu,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      tooltip: _isWatchlistExpanded ? 'Plegar lista de monedas' : 'Desplegar lista de monedas',
                      onPressed: () => setState(() => _isWatchlistExpanded = !_isWatchlistExpanded),
                    ),
                    const SizedBox(width: 6),
                    Image.asset(
                      'assets/icon/app_icon.png',
                      width: 22,
                      height: 22,
                      errorBuilder: (_, __, ___) => const Icon(Icons.candlestick_chart, color: AppColors.primary, size: 18),
                    ),
                    const SizedBox(width: 8),
                    const Text('CryptoView Pro', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(width: 12),
                    const CloudEngineStatusPill(),
                  ],
                ),
                Row(
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      ),
                      icon: const Icon(Icons.currency_exchange, size: 16),
                      label: const Text('Exchanges & Sincronización', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: _showExchangesModal,
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.settings, color: AppColors.primary, size: 20),
                      tooltip: 'Configuración General y Colores',
                      onPressed: _showSettingsModal,
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: Icon(
                        _isTrackerExpanded ? Icons.view_sidebar : Icons.view_sidebar_outlined,
                        color: _isTrackerExpanded ? AppColors.primary : AppColors.textMuted,
                        size: 20,
                      ),
                      tooltip: _isTrackerExpanded ? 'Plegar diario y casados' : 'Desplegar diario y casados',
                      onPressed: () => setState(() => _isTrackerExpanded = !_isTrackerExpanded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        body: Row(
          children: [
            // Left Sidebar: Watchlist (Resizable & Collapsible)
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              width: _isWatchlistExpanded ? settingsProvider.watchlistWidth : 44,
              child: _isWatchlistExpanded
                  ? WatchlistScreen(onTabChange: (_) {})
                  : Container(
                      color: AppColors.surface,
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          IconButton(
                            icon: const Icon(Icons.chevron_right, color: AppColors.primary),
                            tooltip: 'Desplegar Lista',
                            onPressed: () => setState(() => _isWatchlistExpanded = true),
                          ),
                          const SizedBox(height: 16),
                          RotatedBox(
                            quarterTurns: 3,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star, color: Colors.amber, size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  watchlistProvider.selectedSymbol,
                                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            // Draggable Splitter Handle (Left: Watchlist <-> Chart)
            if (_isWatchlistExpanded)
              PanelResizeHandle(
                tooltip: 'Arrastra para ajustar el ancho de la lista de monedas (Doble clic para plegar)',
                onDeltaDrag: (delta) {
                  settingsProvider.setWatchlistWidth(settingsProvider.watchlistWidth + delta);
                },
                onDoubleTap: () => setState(() => _isWatchlistExpanded = false),
              )
            else
              Container(width: 1, color: AppColors.divider),
            // Middle: Chart Screen (Expands dynamically to available space)
            const Expanded(
              child: ChartScreen(),
            ),
            // Draggable Splitter Handle (Right: Chart <-> Tracker / Diario)
            if (_isTrackerExpanded)
              PanelResizeHandle(
                tooltip: 'Arrastra para ajustar el ancho del diario y casamientos (Doble clic para plegar)',
                onDeltaDrag: (delta) {
                  settingsProvider.setTrackerWidth(settingsProvider.trackerWidth - delta);
                },
                onDoubleTap: () => setState(() => _isTrackerExpanded = false),
              )
            else
              Container(width: 1, color: AppColors.divider),
            // Right Sidebar: Tracker/Operations (Resizable & Collapsible)
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              width: _isTrackerExpanded ? settingsProvider.trackerWidth : 44,
              child: _isTrackerExpanded
                  ? const TrackerScreen()
                  : Container(
                      color: AppColors.surface,
                      child: Column(
                        children: [
                          const SizedBox(height: 12),
                          IconButton(
                            icon: const Icon(Icons.chevron_left, color: AppColors.primary),
                            tooltip: 'Desplegar Diario & Casamientos',
                            onPressed: () => setState(() => _isTrackerExpanded = true),
                          ),
                          const SizedBox(height: 16),
                          RotatedBox(
                            quarterTurns: 3,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.link, color: AppColors.bull, size: 14),
                                const SizedBox(width: 6),
                                Text(
                                  'Casados: ${trackerProvider.totalMatchesCount}',
                                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      );
    }

    // ==========================================
    // 2. MOBILE / NARROW SCREEN (Desplegable UX)
    // ==========================================
    // On Mobile: Main screen is the Chart with:
    // a) Slide-out Watchlist Drawer (from left or header button)
    // b) Slide-up Draggable Tracker Panel (from bottom)
    return Scaffold(
      key: _mobileScaffoldKey,
      backgroundColor: AppColors.background,
      // Left Drawer for Watchlist
      drawer: Drawer(
        backgroundColor: AppColors.surface,
        child: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: AppColors.card,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.star, color: Colors.amber, size: 20),
                        SizedBox(width: 8),
                        Text('Lista de Monedas', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.settings, color: AppColors.primary, size: 20),
                          tooltip: 'Configuración General y Colores',
                          onPressed: () {
                            Navigator.pop(context);
                            _showSettingsModal();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: WatchlistScreen(
                  onTabChange: (_) {
                    Navigator.pop(context); // Close drawer on selection
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          // Background View: The Full Chart Screen
          Positioned.fill(
            bottom: 48, // Leave room for bottom sheet handle bar
            child: const ChartScreen(),
          ),

          // Sliding Bottom Panel: Diario de Casamientos & Operaciones
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0.07,
            minChildSize: 0.06,
            maxChildSize: 0.92,
            snap: true,
            snapSizes: const [0.06, 0.50, 0.92],
            builder: (BuildContext context, ScrollController scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                  boxShadow: [
                    BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, -3)),
                  ],
                ),
                child: Column(
                  children: [
                    // Pull Handle & Quick Status Bar
                    GestureDetector(
                      onTap: _toggleBottomSheet,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        color: Colors.transparent,
                        child: Column(
                          children: [
                            // Tactile drag bar pill
                            Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: AppColors.textMuted,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.account_balance_wallet, color: AppColors.primary, size: 16),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Diario & Casamientos (${watchlistProvider.selectedSymbol})',
                                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.bull.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'PnL: \$${trackerProvider.totalNetProfit.toStringAsFixed(2)}',
                                        style: const TextStyle(color: AppColors.bull, fontWeight: FontWeight.bold, fontSize: 11),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.unfold_more, color: AppColors.textSecondary, size: 16),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(color: AppColors.border, height: 1),
                    // Expanded Tracker Content
                    Expanded(
                      child: const TrackerScreen(),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          type: BottomNavigationBarType.fixed,
          backgroundColor: AppColors.card,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textSecondary,
          onTap: (index) {
            if (index == 0) {
              // Open Watchlist Drawer
              _mobileScaffoldKey.currentState?.openDrawer();
            } else if (index == 2) {
              // Expand bottom tracker sheet
              _toggleBottomSheet();
            } else if (index == 3) {
              _showExchangesModal();
            } else {
              setState(() => _currentIndex = index);
            }
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.star_border),
              activeIcon: Icon(Icons.star, color: AppColors.primary),
              label: 'Monedas',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.show_chart),
              activeIcon: Icon(Icons.show_chart, color: AppColors.primary),
              label: 'Gráfico',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_outlined),
              activeIcon: Icon(Icons.account_balance_wallet, color: AppColors.primary),
              label: 'Casados',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.currency_exchange),
              activeIcon: Icon(Icons.currency_exchange, color: AppColors.primary),
              label: 'Exchanges',
            ),
          ],
        ),
      ),
    );
  }
}

class CloudEngineStatusPill extends StatefulWidget {
  const CloudEngineStatusPill({super.key});

  @override
  State<CloudEngineStatusPill> createState() => _CloudEngineStatusPillState();
}

class _CloudEngineStatusPillState extends State<CloudEngineStatusPill> {
  Timer? _pollTimer;
  bool _isLoading = false;
  bool _isOnline = false;
  String _workerStatus = 'checking'; // 'online', 'stalled', 'offline', 'error', 'checking'
  int _candlesCount = 0;
  int _symbolsCount = 0;
  int _tradesCount = 0;
  double? _workerLastSeenSeconds;
  String? _errorMessage;
  DateTime? _lastCheckedAt;

  @override
  void initState() {
    super.initState();
    _checkHealth();
    // Chequear periódicamente cada 35 segundos
    _pollTimer = Timer.periodic(const Duration(seconds: 35), (_) {
      _checkHealth();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkHealth() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final res = await CloudApiService.instance.checkHealth();
      if (!mounted) return;

      if (res['http_code'] == 200 && res['status'] == 'online') {
        setState(() {
          _isOnline = true;
          _workerStatus = res['worker_status'] ?? 'unknown';
          _candlesCount = (res['total_candles_stored'] as num?)?.toInt() ?? 0;
          _symbolsCount = (res['tracked_symbols_active'] as num?)?.toInt() ?? 0;
          _tradesCount = (res['total_trades_stored'] as num?)?.toInt() ?? 0;
          _workerLastSeenSeconds = (res['worker_last_seen_seconds'] as num?)?.toDouble();
          _errorMessage = null;
          _lastCheckedAt = DateTime.now();
          _isLoading = false;
        });
      } else {
        setState(() {
          _isOnline = false;
          _workerStatus = 'offline';
          _errorMessage = res['message']?.toString() ?? 'Error conectando con el servidor Cloud';
          _lastCheckedAt = DateTime.now();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isOnline = false;
        _workerStatus = 'offline';
        _errorMessage = e.toString();
        _lastCheckedAt = DateTime.now();
        _isLoading = false;
      });
    }
  }

  String _formatK(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(0)}k';
    }
    return count.toString();
  }

  String _formatCommas(int number) {
    final str = number.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return str.replaceAllMapped(reg, (Match m) => '${m[1]},');
  }

  Color _getStatusColor() {
    if (_workerStatus == 'checking') return AppColors.textMuted;
    if (!_isOnline) return AppColors.bear;
    if (_workerStatus == 'online') return AppColors.bull;
    if (_workerStatus == 'stalled') return Colors.amber;
    return AppColors.bear;
  }

  String _getStatusText() {
    if (_workerStatus == 'checking') return 'Cloud...';
    if (!_isOnline) return 'Cloud Offline';
    if (_workerStatus == 'online') {
      return _candlesCount > 0 ? 'Cloud 24/7 (${_formatK(_candlesCount)})' : 'Cloud 24/7';
    }
    if (_workerStatus == 'stalled') return 'Worker Demorado';
    return 'Worker Inactivo';
  }

  void _showDiagnosticDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final statusColor = _getStatusColor();
            final url = CloudApiService.instance.baseUrl;

            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: statusColor.withValues(alpha: 0.4), width: 1.5),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.cloud_sync, color: statusColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CryptoView Cloud Engine',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Telemetría de Servidor & Base de Datos',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textSecondary, size: 20),
                    onPressed: () => Navigator.pop(dialogCtx),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Status banner
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: statusColor,
                                boxShadow: [
                                  BoxShadow(color: statusColor.withValues(alpha: 0.6), blurRadius: 6, spreadRadius: 1),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _isOnline
                                    ? (_workerStatus == 'online'
                                        ? 'Servidor y Worker Ingestor Operando al 100%'
                                        : 'Servidor Conectado, Ingestor Pendiente')
                                    : 'Sin Conexión con el Servidor Cloud',
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (_isLoading)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Metrics List
                      _buildMetricRow(
                        icon: Icons.link,
                        label: 'Servidor / Endpoint',
                        value: url,
                        valueColor: AppColors.primary,
                      ),
                      const Divider(color: AppColors.border, height: 16),
                      _buildMetricRow(
                        icon: Icons.storage,
                        label: 'Base de Datos',
                        value: _isOnline ? 'TimescaleDB / PostgreSQL 17' : 'Desconectado',
                        valueColor: _isOnline ? AppColors.bull : AppColors.bear,
                      ),
                      const Divider(color: AppColors.border, height: 16),
                      _buildMetricRow(
                        icon: Icons.candlestick_chart,
                        label: 'Velas Históricas Almacenadas',
                        value: _isOnline ? '${_formatCommas(_candlesCount)} velas' : '0',
                        valueColor: AppColors.bull,
                      ),
                      const Divider(color: AppColors.border, height: 16),
                      _buildMetricRow(
                        icon: Icons.show_chart,
                        label: 'Pares Monitoreados 24/7',
                        value: _isOnline ? '$_symbolsCount pares activos' : '0',
                        valueColor: AppColors.textPrimary,
                      ),
                      const Divider(color: AppColors.border, height: 16),
                      _buildMetricRow(
                        icon: Icons.receipt_long,
                        label: 'Operaciones / Trades Guardados',
                        value: _isOnline ? '$_tradesCount transacciones' : '0',
                        valueColor: AppColors.textPrimary,
                      ),
                      const Divider(color: AppColors.border, height: 16),
                      _buildMetricRow(
                        icon: Icons.favorite,
                        label: 'Último Latido Ingestion Worker',
                        value: _workerLastSeenSeconds != null
                            ? 'hace ${_workerLastSeenSeconds!.toStringAsFixed(1)}s (${_workerStatus.toUpperCase()})'
                            : (_isOnline ? 'Sin datos de latido' : 'No disponible'),
                        valueColor: _workerStatus == 'online' ? AppColors.bull : Colors.amber,
                      ),

                      if (_errorMessage != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.bear.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.bear.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: AppColors.bear, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: AppColors.bear, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      if (_lastCheckedAt != null) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Último chequeo: ${_lastCheckedAt!.hour.toString().padLeft(2, '0')}:${_lastCheckedAt!.minute.toString().padLeft(2, '0')}:${_lastCheckedAt!.second.toString().padLeft(2, '0')}',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Revisar Ahora'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                  onPressed: () async {
                    await _checkHealth();
                    setDialogState(() {});
                  },
                ),
                TextButton.icon(
                  icon: const Icon(Icons.settings, size: 16),
                  label: const Text('Configurar Servidor'),
                  style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                  onPressed: () {
                    Navigator.pop(dialogCtx);
                    showDialog(
                      context: context,
                      barrierColor: Colors.black.withValues(alpha: 0.6),
                      builder: (ctx) => Dialog(
                        backgroundColor: Colors.transparent,
                        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: const SettingsScreen(),
                        ),
                      ),
                    );
                  },
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.card,
                    foregroundColor: AppColors.textPrimary,
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cerrar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMetricRow({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
        Text(
          value,
          style: TextStyle(color: valueColor, fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();
    final statusText = _getStatusText();

    return Tooltip(
      message: 'Estado del servidor Cloud 24/7 (clic para ver diagnóstico)',
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _showDiagnosticDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: statusColor.withValues(alpha: 0.35), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.8),
                        blurRadius: 5,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

