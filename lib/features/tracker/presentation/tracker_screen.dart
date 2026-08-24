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
import 'widgets/select_match_candidate_sheet.dart';

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
  String? _lastContextSymbol;
  String? _lastContextExchange;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<TrackerProvider>(context, listen: false).loadData();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final watchlistProvider = Provider.of<WatchlistProvider>(context);
    final trackerProvider = Provider.of<TrackerProvider>(context, listen: false);

    if (_lastContextSymbol != watchlistProvider.selectedSymbol ||
        _lastContextExchange != watchlistProvider.currentExchange) {
      _lastContextSymbol = watchlistProvider.selectedSymbol;
      _lastContextExchange = watchlistProvider.currentExchange;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        trackerProvider.updateActiveContext(
          watchlistProvider.selectedSymbol,
          watchlistProvider.currentExchange,
        );
      });
    }
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

  void _showMatchCandidateSheet(TransactionModel tx, TrackerProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SelectMatchCandidateSheet(
        sourceTx: tx,
        provider: provider,
        onMatchedSuccessfully: () {
          _tabController.animateTo(0);
        },
      ),
    );
  }

  void _showSyncRangeDialog() {
    final watchlistProvider = Provider.of<WatchlistProvider>(context, listen: false);
    final currentExchange = watchlistProvider.currentExchange;
    final currentSymbol = watchlistProvider.selectedSymbol;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Row(
          children: [
            const Icon(Icons.cloud_sync, color: AppColors.primary, size: 22),
            const SizedBox(width: 8),
            Text('Sincronizar $currentSymbol', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selecciona el período a consultar en $currentExchange:',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 14),
            _buildSyncRangeOption(
              icon: Icons.flash_on,
              title: 'Hoy (Últimas 24 horas)',
              subtitle: 'Ideal para descargar tus operaciones del día al instante',
              days: 1,
            ),
            const SizedBox(height: 8),
            _buildSyncRangeOption(
              icon: Icons.calendar_view_week,
              title: 'Últimos 7 Días',
              subtitle: 'Sincroniza la actividad de la última semana',
              days: 7,
            ),
            const SizedBox(height: 8),
            _buildSyncRangeOption(
              icon: Icons.calendar_month,
              title: 'Últimos 30 Días',
              subtitle: 'Sincroniza todas las órdenes del último mes',
              days: 30,
            ),
            const SizedBox(height: 8),
            _buildSyncRangeOption(
              icon: Icons.history,
              title: 'Todo el Historial (Hasta 2 años)',
              subtitle: 'Consulta histórica completa permitida por el exchange',
              days: 730,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncRangeOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required int days,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        Navigator.pop(context);
        _syncFromApi(lookbackDays: days);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: AppColors.textMuted, size: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _syncFromApi({int lookbackDays = 1}) async {
    final watchlistProvider = Provider.of<WatchlistProvider>(context, listen: false);
    final trackerProvider = Provider.of<TrackerProvider>(context, listen: false);

    final currentExchange = watchlistProvider.currentExchange;
    final currentSymbol = watchlistProvider.selectedSymbol;

    setState(() => _isSyncing = true);

    try {
      final importedCount = await trackerProvider.importTransactionsForSymbol(
        currentExchange,
        currentSymbol,
        lookbackDays: lookbackDays,
      );
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
    final watchlistProvider = Provider.of<WatchlistProvider>(context);

    final currentMatches = trackerProvider.filteredMatches;
    final currentBuys = trackerProvider.filteredOpenBuys;
    final currentSells = trackerProvider.filteredOpenSells;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Diario de Casamiento',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 17),
            ),
            Text(
              '${watchlistProvider.selectedSymbol} · ${watchlistProvider.currentExchange}',
              style: const TextStyle(color: AppColors.primary, fontSize: 12),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.vpn_key_outlined),
            tooltip: 'Configurar API Keys',
            onPressed: _showApiConfigDialog,
          ),
          IconButton(
            icon: (trackerProvider.isImporting || _isSyncing)
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary)))
                : const Icon(Icons.cloud_sync_outlined),
            tooltip: 'Sincronizar Historial vía API',
            onPressed: (trackerProvider.isImporting || _isSyncing) ? null : _showSyncRangeDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: [
            Tab(text: 'Casados (${currentMatches.length})'),
            Tab(text: 'Compras (${currentBuys.length})'),
            Tab(text: 'Ventas (${currentSells.length})'),
          ],
        ),
      ),
      body: Column(
        children: [
          MetricsHeaderCard(
            provider: trackerProvider,
            onRefreshBalance: () => trackerProvider.fetchLiveBalance(watchlistProvider.currentExchange),
          ),
          if (trackerProvider.isImporting)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Sincronizando Historial (${(trackerProvider.importProgress * 100).toInt()}%)',
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '${trackerProvider.importFoundCount} ops encontradas',
                        style: const TextStyle(
                          color: AppColors.bull,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: trackerProvider.importProgress > 0 ? trackerProvider.importProgress : null,
                      backgroundColor: AppColors.card,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                      minHeight: 5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    trackerProvider.importStatusMessage,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Historial de Casamientos
                currentMatches.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.link_off, size: 54, color: AppColors.border),
                            const SizedBox(height: 12),
                            Text(
                              trackerProvider.filterOnlyCurrentSymbol
                                  ? 'No hay operaciones casadas en ${trackerProvider.activeSymbol}'
                                  : 'No hay operaciones casadas',
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            const Text('Empareja una compra con una venta para calcular PnL.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: currentMatches.length,
                        itemBuilder: (context, i) => MatchTile(match: currentMatches[i], provider: trackerProvider),
                      ),

                // Tab 2: Compras Abiertas
                currentBuys.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.shopping_bag_outlined, size: 54, color: AppColors.border),
                            const SizedBox(height: 12),
                            Text(
                              trackerProvider.filterOnlyCurrentSymbol
                                  ? 'No hay compras abiertas en ${trackerProvider.activeSymbol}'
                                  : 'No hay compras abiertas',
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            const Text('Sincroniza desde API o registra una con el botón +.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: currentBuys.length,
                        itemBuilder: (context, i) {
                          final tx = currentBuys[i];
                          return TransactionTile(
                            tx: tx,
                            provider: trackerProvider,
                            isSelected: false,
                            onSelectForMatch: () => _showMatchCandidateSheet(tx, trackerProvider),
                            onTapDetail: () => _showTransactionDetail(tx, trackerProvider),
                          );
                        },
                      ),

                // Tab 3: Ventas Abiertas
                currentSells.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.sell_outlined, size: 54, color: AppColors.border),
                            const SizedBox(height: 12),
                            Text(
                              trackerProvider.filterOnlyCurrentSymbol
                                  ? 'No hay ventas abiertas en ${trackerProvider.activeSymbol}'
                                  : 'No hay ventas abiertas',
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            const Text('Sincroniza desde API o registra una con el botón +.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: currentSells.length,
                        itemBuilder: (context, i) {
                          final tx = currentSells[i];
                          return TransactionTile(
                            tx: tx,
                            provider: trackerProvider,
                            isSelected: false,
                            onSelectForMatch: () => _showMatchCandidateSheet(tx, trackerProvider),
                            onTapDetail: () => _showTransactionDetail(tx, trackerProvider),
                          );
                        },
                      ),
              ],
            ),
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
