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
import 'features/bots/providers/bots_provider.dart';
import 'features/bots/presentation/bots_workspace_screen.dart';

import 'core/widgets/panel_resize_handle.dart';
import 'core/widgets/cloud_engine_status_pill.dart';

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
        ChangeNotifierProvider(create: (_) => BotsProvider()),
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
      title: 'CryptoView Pro',
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
  // Desktop active workspace: 0 = Trading, 1 = Bots, 2 = Exchanges, 3 = Settings
  int _desktopWorkspaceIndex = 0;

  // Mobile navigation index: 1 = Gráfico, 2 = Bots
  int _mobileTabIndex = 1;

  bool _isWatchlistExpanded = true;
  bool _isTrackerExpanded = true;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  final GlobalKey<ScaffoldState> _mobileScaffoldKey =
      GlobalKey<ScaffoldState>();

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

  void _openSymbolInTradingWorkspace(
      String symbol, WatchlistProvider watchlistProvider) {
    watchlistProvider.addSymbol(symbol);
    watchlistProvider.changeSymbol(symbol);
    setState(() {
      _desktopWorkspaceIndex = 0;
      _mobileTabIndex = 1;
    });
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

  Widget _buildDesktopActivityDock(BotsProvider botsProvider) {
    return Container(
      width: 54,
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(
          right: BorderSide(color: AppColors.divider, width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _buildDockItem(
            index: 0,
            icon: Icons.candlestick_chart_outlined,
            activeIcon: Icons.candlestick_chart,
            label: 'Trading',
            tooltip: 'Espacio de Trading, Gráfico y Casamiento',
          ),
          const SizedBox(height: 4),
          _buildDockItem(
            index: 1,
            icon: Icons.smart_toy_outlined,
            activeIcon: Icons.smart_toy,
            label: 'Bots',
            tooltip: 'Centro de Control de Flota de Bots',
            badgeCount: botsProvider.botsActivosCount,
          ),
          const SizedBox(height: 4),
          _buildDockItem(
            index: 2,
            icon: Icons.currency_exchange,
            activeIcon: Icons.currency_exchange,
            label: 'Exchanges',
            tooltip: 'Conexiones API y Sincronización',
          ),
          const Spacer(),
          const Divider(color: AppColors.divider, indent: 10, endIndent: 10),
          _buildDockItem(
            index: 3,
            icon: Icons.tune_outlined,
            activeIcon: Icons.tune,
            label: 'Ajustes',
            tooltip: 'Configuración General y Respaldos',
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildDockItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required String tooltip,
    int badgeCount = 0,
  }) {
    final bool isSelected = _desktopWorkspaceIndex == index;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        onTap: () => setState(() => _desktopWorkspaceIndex = index),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: isSelected ? AppColors.primary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    isSelected ? activeIcon : icon,
                    size: 20,
                    color:
                        isSelected ? AppColors.primary : AppColors.textSecondary,
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      right: -7,
                      top: -5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.bull,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$badgeCount',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color:
                      isSelected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPanelToggleChip({
    required IconData icon,
    required String label,
    required bool isActive,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: isActive
                ? AppColors.primary.withValues(alpha: 0.14)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isActive
                  ? AppColors.primary.withValues(alpha: 0.45)
                  : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isActive ? AppColors.primary : AppColors.textMuted,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                  color: isActive ? AppColors.textPrimary : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.of(context).size.width;
    final bool isWide = width > 950;
    final watchlistProvider = Provider.of<WatchlistProvider>(context);
    final trackerProvider = Provider.of<TrackerProvider>(context);
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final botsProvider = Provider.of<BotsProvider>(context);

    // ==========================================
    // 1. DESKTOP / WIDE SCREEN (Modular Workspaces + Hideable Panels)
    // ==========================================
    if (isWide) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(42),
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.card,
              border: Border(
                bottom: BorderSide(color: AppColors.divider, width: 1),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Image.asset(
                      'assets/icon/app_icon.png',
                      width: 20,
                      height: 20,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.candlestick_chart,
                          color: AppColors.primary,
                          size: 18),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'CryptoView Pro',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const CloudEngineStatusPill(),
                  ],
                ),
                Row(
                  children: [
                    if (_desktopWorkspaceIndex == 0) ...[
                      _buildPanelToggleChip(
                        icon: Icons.view_sidebar_outlined,
                        label: 'Monedas',
                        isActive: _isWatchlistExpanded,
                        tooltip: _isWatchlistExpanded
                            ? 'Ocultar completamente la lista de monedas'
                            : 'Mostrar lista de monedas',
                        onTap: () => setState(
                            () => _isWatchlistExpanded = !_isWatchlistExpanded),
                      ),
                      const SizedBox(width: 8),
                      _buildPanelToggleChip(
                        icon: Icons.vertical_split_outlined,
                        label: 'Casamiento y Operaciones',
                        isActive: _isTrackerExpanded,
                        tooltip: _isTrackerExpanded
                            ? 'Ocultar completamente el panel de casamiento'
                            : 'Mostrar panel de casamiento y operaciones',
                        onTap: () => setState(
                            () => _isTrackerExpanded = !_isTrackerExpanded),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        body: Row(
          children: [
            _buildDesktopActivityDock(botsProvider),
            Expanded(
              child: IndexedStack(
                index: _desktopWorkspaceIndex,
                children: [
                  // WORKSPACE 0: TRADING & ANÁLISIS
                  Row(
                    children: [
                      if (_isWatchlistExpanded) ...[
                        SizedBox(
                          width: settingsProvider.watchlistWidth,
                          child: WatchlistScreen(onTabChange: (_) {}),
                        ),
                        PanelResizeHandle(
                          tooltip:
                              'Arrastra para ajustar ancho (Doble clic para ocultar)',
                          onDeltaDrag: (delta) {
                            settingsProvider.setWatchlistWidth(
                                settingsProvider.watchlistWidth + delta);
                          },
                          onDoubleTap: () =>
                              setState(() => _isWatchlistExpanded = false),
                        ),
                      ],
                      const Expanded(
                        child: ChartScreen(),
                      ),
                      if (_isTrackerExpanded) ...[
                        PanelResizeHandle(
                          tooltip:
                              'Arrastra para ajustar ancho (Doble clic para ocultar)',
                          onDeltaDrag: (delta) {
                            settingsProvider.setTrackerWidth(
                                settingsProvider.trackerWidth - delta);
                          },
                          onDoubleTap: () =>
                              setState(() => _isTrackerExpanded = false),
                        ),
                        SizedBox(
                          width: settingsProvider.trackerWidth,
                          child: const TrackerScreen(),
                        ),
                      ],
                    ],
                  ),

                  // WORKSPACE 1: FLOTA DE BOTS CUANTITATIVOS
                  BotsWorkspaceScreen(
                    onOpenSymbolInChart: (symbol) =>
                        _openSymbolInTradingWorkspace(
                            symbol, watchlistProvider),
                  ),

                  // WORKSPACE 2: EXCHANGES & SINCRONIZACIÓN
                  const ExchangesScreen(),

                  // WORKSPACE 3: CONFIGURACIÓN GENERAL Y RESPALDOS
                  const SettingsScreen(),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ==========================================
    // 2. MOBILE / NARROW SCREEN (Adaptable Multi-Workspace UX)
    // ==========================================
    return Scaffold(
      key: _mobileScaffoldKey,
      backgroundColor: AppColors.background,
      drawer: Drawer(
        backgroundColor: AppColors.surface,
        child: SafeArea(
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: AppColors.card,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.star, color: Colors.amber, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Seguimiento de Mercado',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.settings,
                              color: AppColors.primary, size: 20),
                          tooltip: 'Configuración del Sistema',
                          onPressed: () {
                            Navigator.pop(context);
                            _showSettingsModal();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: AppColors.textSecondary, size: 20),
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
                    Navigator.pop(context);
                    setState(() => _mobileTabIndex = 1);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _mobileTabIndex == 2 ? 1 : 0,
        children: [
          // Vista 0: Gráfico + Panel Deslizable de Operaciones
          Stack(
            children: [
              const Positioned.fill(
                bottom: 48,
                child: ChartScreen(),
              ),
              DraggableScrollableSheet(
                controller: _sheetController,
                initialChildSize: 0.07,
                minChildSize: 0.06,
                maxChildSize: 0.92,
                snap: true,
                snapSizes: const [0.06, 0.50, 0.92],
                builder:
                    (BuildContext context, ScrollController scrollController) {
                  return Container(
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(18)),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black54,
                            blurRadius: 10,
                            offset: Offset(0, -3)),
                      ],
                    ),
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _toggleBottomSheet,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: 8, horizontal: 16),
                            color: Colors.transparent,
                            child: Column(
                              children: [
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
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.account_balance_wallet,
                                            color: AppColors.primary, size: 16),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Operaciones y Casamientos (${watchlistProvider.selectedSymbol})',
                                          style: const TextStyle(
                                            color: AppColors.textPrimary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.bull
                                                .withValues(alpha: 0.2),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'PnL: \$${trackerProvider.totalNetProfit.toStringAsFixed(2)}',
                                            style: const TextStyle(
                                              color: AppColors.bull,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        const Icon(Icons.unfold_more,
                                            color: AppColors.textSecondary,
                                            size: 16),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(color: AppColors.border, height: 1),
                        const Expanded(
                          child: TrackerScreen(),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          // Vista 1: Espacio de Bots en Móvil
          SafeArea(
            child: BotsWorkspaceScreen(
              onOpenSymbolInChart: (symbol) =>
                  _openSymbolInTradingWorkspace(symbol, watchlistProvider),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _mobileTabIndex,
          type: BottomNavigationBarType.fixed,
          backgroundColor: AppColors.card,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textSecondary,
          selectedFontSize: 11,
          unselectedFontSize: 10.5,
          onTap: (index) {
            if (index == 0) {
              _mobileScaffoldKey.currentState?.openDrawer();
            } else if (index == 3) {
              setState(() => _mobileTabIndex = 1);
              _toggleBottomSheet();
            } else if (index == 4) {
              _showExchangesModal();
            } else {
              setState(() => _mobileTabIndex = index);
            }
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.star_border),
              activeIcon: Icon(Icons.star, color: AppColors.primary),
              label: 'Monedas',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.candlestick_chart_outlined),
              activeIcon:
                  Icon(Icons.candlestick_chart, color: AppColors.primary),
              label: 'Trading',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.smart_toy_outlined),
              activeIcon: Icon(Icons.smart_toy, color: AppColors.primary),
              label: 'Bots',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.account_balance_wallet_outlined),
              activeIcon:
                  Icon(Icons.account_balance_wallet, color: AppColors.primary),
              label: 'Casados',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.currency_exchange),
              activeIcon:
                  Icon(Icons.currency_exchange, color: AppColors.primary),
              label: 'Exchanges',
            ),
          ],
        ),
      ),
    );
  }
}

