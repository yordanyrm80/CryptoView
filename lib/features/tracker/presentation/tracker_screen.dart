import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/tracker_provider.dart';
import '../domain/transaction_model.dart';
import '../../watchlist/providers/watchlist_provider.dart';
import 'widgets/metrics_header_card.dart';
import 'widgets/match_tile.dart';
import 'widgets/transaction_tile.dart';
import 'widgets/add_transaction_dialog.dart';
import 'widgets/api_config_dialog.dart';
import 'widgets/match_confirm_dialog.dart';
import 'widgets/transaction_detail_sheet.dart';

class TrackerScreen extends StatefulWidget {
  const TrackerScreen({Key? key}) : super(key: key);

  @override
  _TrackerScreenState createState() => _TrackerScreenState();
}

class _TrackerScreenState extends State<TrackerScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  TransactionModel? _selectedBuyForMatch;
  TransactionModel? _selectedSellForMatch;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<TrackerProvider>(context, listen: false).loadData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showAddTransactionDialog() {
    final watchlistProvider = Provider.of<WatchlistProvider>(context, listen: false);
    final trackerProvider = Provider.of<TrackerProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (_) => AddTransactionDialog(
        watchlistProvider: watchlistProvider,
        trackerProvider: trackerProvider,
      ),
    );
  }

  void _showApiConfigDialog() {
    final trackerProvider = Provider.of<TrackerProvider>(context, listen: false);
    final watchlistProvider = Provider.of<WatchlistProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (_) => ApiConfigDialog(
        trackerProvider: trackerProvider,
        defaultExchange: watchlistProvider.currentExchange,
      ),
    );
  }

  void _showTransactionDetail(TransactionModel tx, TrackerProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TransactionDetailSheet(tx: tx, provider: provider),
    );
  }

  void _showMatchConfirmDialog(TrackerProvider provider) {
    if (_selectedBuyForMatch == null || _selectedSellForMatch == null) return;
    showDialog(
      context: context,
      builder: (_) => MatchConfirmDialog(
        buy: _selectedBuyForMatch!,
        sell: _selectedSellForMatch!,
        provider: provider,
        onMatchedSuccessfully: () {
          setState(() {
            _selectedBuyForMatch = null;
            _selectedSellForMatch = null;
          });
          _tabController.animateTo(0);
        },
      ),
    );
  }

  Future<void> _syncFromApi() async {
    final watchlistProvider = Provider.of<WatchlistProvider>(context, listen: false);
    final trackerProvider = Provider.of<TrackerProvider>(context, listen: false);

    final currentExchange = watchlistProvider.currentExchange;
    final currentSymbol = watchlistProvider.selectedSymbol;

    setState(() => _isSyncing = true);

    try {
      final importedCount = await trackerProvider.importTransactionsForSymbol(currentExchange, currentSymbol);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.bull,
            content: Text(importedCount > 0
                ? '¡Se importaron $importedCount nuevas transacciones de $currentExchange!'
                : 'Historial al día. No hay nuevas órdenes en $currentSymbol.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.bear,
            content: Text('Error al sincronizar: $e'),
            action: SnackBarAction(
              label: 'Configurar API',
              textColor: Colors.white,
              onPressed: _showApiConfigDialog,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trackerProvider = Provider.of<TrackerProvider>(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        title: const Text(
          'Diario de Trading & Casamientos',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.vpn_key_outlined),
            tooltip: 'Configurar API Keys',
            onPressed: _showApiConfigDialog,
          ),
          IconButton(
            icon: _isSyncing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary)))
                : const Icon(Icons.cloud_sync_outlined),
            tooltip: 'Sincronizar Historial vía API',
            onPressed: _isSyncing ? null : _syncFromApi,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: [
            Tab(text: 'Casados (${trackerProvider.matches.length})'),
            Tab(text: 'Compras (${trackerProvider.openBuys.length})'),
            Tab(text: 'Ventas (${trackerProvider.openSells.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Historial de Casamientos
          Column(
            children: [
              MetricsHeaderCard(
                totalProfit: trackerProvider.totalProfit,
                winRate: trackerProvider.winRate,
                totalMatches: trackerProvider.matches.length,
              ),
              Expanded(
                child: trackerProvider.matches.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.link_off, size: 64, color: AppColors.border),
                            SizedBox(height: 16),
                            Text('No hay operaciones casadas', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                            SizedBox(height: 8),
                            Text('Empareja una compra con una venta para calcular PnL.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: trackerProvider.matches.length,
                        itemBuilder: (context, i) => MatchTile(match: trackerProvider.matches[i], provider: trackerProvider),
                      ),
              ),
            ],
          ),

          // Tab 2: Compras Abiertas
          trackerProvider.openBuys.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.shopping_bag_outlined, size: 64, color: AppColors.border),
                      SizedBox(height: 16),
                      Text('No hay compras abiertas', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text('Sincroniza desde API o registra una con el botón +.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  itemCount: trackerProvider.openBuys.length,
                  itemBuilder: (context, i) {
                    final tx = trackerProvider.openBuys[i];
                    final isSelected = _selectedBuyForMatch?.id == tx.id;
                    return TransactionTile(
                      tx: tx,
                      provider: trackerProvider,
                      isSelected: isSelected,
                      onSelectForMatch: () {
                        setState(() {
                          _selectedBuyForMatch = isSelected ? null : tx;
                        });
                        if (_selectedBuyForMatch != null && _selectedSellForMatch != null) {
                          _showMatchConfirmDialog(trackerProvider);
                        }
                      },
                      onTapDetail: () => _showTransactionDetail(tx, trackerProvider),
                    );
                  },
                ),

          // Tab 3: Ventas Abiertas
          trackerProvider.openSells.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.sell_outlined, size: 64, color: AppColors.border),
                      SizedBox(height: 16),
                      Text('No hay ventas abiertas', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                      SizedBox(height: 8),
                      Text('Sincroniza desde API o registra una con el botón +.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  physics: const BouncingScrollPhysics(),
                  itemCount: trackerProvider.openSells.length,
                  itemBuilder: (context, i) {
                    final tx = trackerProvider.openSells[i];
                    final isSelected = _selectedSellForMatch?.id == tx.id;
                    return TransactionTile(
                      tx: tx,
                      provider: trackerProvider,
                      isSelected: isSelected,
                      onSelectForMatch: () {
                        setState(() {
                          _selectedSellForMatch = isSelected ? null : tx;
                        });
                        if (_selectedBuyForMatch != null && _selectedSellForMatch != null) {
                          _showMatchConfirmDialog(trackerProvider);
                        }
                      },
                      onTapDetail: () => _showTransactionDetail(tx, trackerProvider),
                    );
                  },
                ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.background,
        icon: const Icon(Icons.add),
        label: const Text('Nueva Operación', style: TextStyle(fontWeight: FontWeight.bold)),
        onPressed: _showAddTransactionDialog,
      ),
    );
  }
}
