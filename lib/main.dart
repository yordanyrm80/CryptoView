import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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
                    const Icon(Icons.candlestick_chart, color: AppColors.primary, size: 18),
                    const SizedBox(width: 8),
                    const Text('CryptoView Pro', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
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
