import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/tracker_provider.dart';
import '../domain/transaction_model.dart';
import '../../watchlist/providers/watchlist_provider.dart';
import 'widgets/metrics_header_card.dart';
import 'widgets/match_tile.dart';
import 'widgets/transaction_tile.dart';
import 'widgets/withdrawal_tile.dart';
import 'widgets/add_expense_dialog.dart';
import 'widgets/api_config_dialog.dart';
import 'widgets/match_confirm_dialog.dart';
import 'widgets/transaction_detail_sheet.dart';
import 'widgets/select_match_candidate_sheet.dart';
import '../domain/withdrawal_model.dart';

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
    _tabController = TabController(length: 4, vsync: this);
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

  void _showConfirmMatchDialogFromExpense(
    TransactionModel buy,
    WithdrawalModel expense,
    double maxMatchable,
    String currency,
    TrackerProvider provider,
  ) {
    String formatAmount(double val) {
      String s = val.toStringAsFixed(8);
      while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
        s = s.substring(0, s.length - 1);
      }
      return s;
    }

    final amountController = TextEditingController(text: formatAmount(maxMatchable));
    final noteController = TextEditingController(text: expense.description ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.shopping_bag_outlined, color: Colors.orange, size: 20),
            SizedBox(width: 8),
            Text(
              'Casar Gasto con Compra',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estás asociando el gasto de ${expense.currency} con la compra de ${buy.symbol} (\$${buy.price.toStringAsFixed(2)}).',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            const Text('Cantidad a Conciliar', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 4),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
              decoration: InputDecoration(
                suffixText: currency,
                suffixStyle: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Nota / Concepto', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 4),
            TextField(
              controller: noteController,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Ej. Amazon 1000 MXN, Walmart, etc.',
                hintStyle: const TextStyle(color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              final qty = double.tryParse(amountController.text.trim()) ?? 0.0;
              if (qty <= 0 || qty > maxMatchable + 0.000001) return;

              Navigator.pop(ctx);
              final success = await provider.matchBuyWithExpense(
                buy: buy,
                expense: expense,
                amountToMatch: qty,
                note: noteController.text.trim(),
              );

              if (success) {
                _tabController.animateTo(0);
              }
            },
            child: const Text('Confirmar Casamiento', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showMatchBuyForExpenseSheet(WithdrawalModel expense, TrackerProvider provider) {
    final currency = expense.currency.toUpperCase();
    final candidateBuys = provider.openBuys.where((tx) {
      final parts = tx.symbol.split('/');
      final base = parts.isNotEmpty ? parts[0] : (tx.symbol.contains('-') ? tx.symbol.split('-')[0] : tx.symbol);
      return base.toUpperCase() == currency && provider.getRemainingAmount(tx) > 0.000001;
    }).toList();

    final remainingExpense = provider.getRemainingWithdrawalAmount(expense);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Casar Gasto con Compra de $currency',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textMuted, size: 20),
                  onPressed: () => Navigator.pop(ctx),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (expense.description != null && expense.description!.isNotEmpty)
                            ? expense.description!
                            : 'Gasto / Retiro en $currency',
                        style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Total: ${expense.amount} $currency · ${expense.exchange}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Por conciliar:', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                      Text(
                        '$remainingExpense $currency',
                        style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Selecciona una compra abierta para conciliar:',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: candidateBuys.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.link_off, size: 44, color: AppColors.border),
                            const SizedBox(height: 10),
                            Text(
                              'No hay compras abiertas disponibles de $currency.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: candidateBuys.length,
                      itemBuilder: (context, index) {
                        final buyTx = candidateBuys[index];
                        final buyRemaining = provider.getRemainingAmount(buyTx);
                        final maxMatch = remainingExpense < buyRemaining ? remainingExpense : buyRemaining;
                        final buyDateStr = '${buyTx.date.day.toString().padLeft(2, '0')}/${buyTx.date.month.toString().padLeft(2, '0')}/${buyTx.date.year}';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: AppColors.bull.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text('COMPRA', style: TextStyle(color: AppColors.bull, fontSize: 9, fontWeight: FontWeight.bold)),
                                        ),
                                        const SizedBox(width: 8),
                                        Text('$buyDateStr · ${buyTx.exchange}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text('Precio: \$${buyTx.price.toStringAsFixed(buyTx.price < 1 ? 4 : 2)}', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                                    const SizedBox(height: 2),
                                    Text('Disponible: $buyRemaining $currency', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                                  ],
                                ),
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                  minimumSize: const Size(64, 32),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _showConfirmMatchDialogFromExpense(buyTx, expense, maxMatch, currency, provider);
                                },
                                icon: const Icon(Icons.link, size: 14),
                                label: const Text('Casar', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
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

  void _showAddExpenseDialog() {
    final trackerProvider = Provider.of<TrackerProvider>(context, listen: false);
    final watchlistProvider = Provider.of<WatchlistProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (_) => AddExpenseDialog(
        provider: trackerProvider,
        defaultCurrency: trackerProvider.currentBaseAsset,
        defaultExchange: watchlistProvider.currentExchange,
      ),
    );
  }

  Future<void> _syncWithdrawalsApi() async {
    final trackerProvider = Provider.of<TrackerProvider>(context, listen: false);
    final watchlistProvider = Provider.of<WatchlistProvider>(context, listen: false);
    final currentExchange = watchlistProvider.currentExchange;

    setState(() => _isSyncing = true);
    try {
      final count = await trackerProvider.importWithdrawalsFromApi(currentExchange);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.surface,
            content: Text('Sincronización de retiros completada: $count retiros nuevos importados.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.bear,
            content: Text('Error al sincronizar retiros: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _syncBitrefillApi() async {
    final trackerProvider = Provider.of<TrackerProvider>(context, listen: false);
    setState(() => _isSyncing = true);
    try {
      final count = await trackerProvider.syncBitrefillOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.surface,
            content: Text(count > 0
                ? 'Bitrefill: $count nuevos gastos importados vía API.'
                : 'Bitrefill: Todos tus gastos están al día.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.bear,
            content: Text('Error al sincronizar Bitrefill: $e'),
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
    final currentExpenses = trackerProvider.filteredWithdrawals;

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
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: 'Casados (${currentMatches.length})'),
            Tab(text: 'Compras (${currentBuys.length})'),
            Tab(text: 'Ventas (${currentSells.length})'),
            Tab(text: 'Gastos (${currentExpenses.length})'),
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
                            const Text('Empareja una compra con una venta o gasto para conciliar.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
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
                            const Text('Sincroniza tus órdenes vía API con el botón de la barra superior.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
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
                            const Text('Sincroniza tus órdenes vía API con el botón de la barra superior.', style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
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

                // Tab 4: Gastos y Retiros
                Column(
                  children: [
                    // Action toolbar for expenses
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(color: AppColors.primary),
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: (trackerProvider.isImporting || _isSyncing) ? null : _syncWithdrawalsApi,
                              icon: const Icon(Icons.cloud_download_outlined, size: 14),
                              label: const Text('Retiros Exchange', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF00E5FF),
                                side: const BorderSide(color: Color(0xFF00E5FF)),
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: (trackerProvider.isImporting || _isSyncing) ? null : _syncBitrefillApi,
                              icon: const Icon(Icons.bolt_rounded, size: 15, color: Color(0xFF00E5FF)),
                              label: const Text('Sync Bitrefill', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: _showAddExpenseDialog,
                              icon: const Icon(Icons.add, size: 15),
                              label: const Text('Registrar', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: currentExpenses.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.shopping_bag_outlined, size: 54, color: AppColors.border),
                                  const SizedBox(height: 12),
                                  Text(
                                    trackerProvider.filterOnlyCurrentSymbol
                                        ? 'No hay gastos ni retiros registrados en ${trackerProvider.currentBaseAsset}'
                                        : 'No hay gastos ni retiros registrados',
                                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Sincroniza desde la API o registra pagos de Amazon, Walmart, etc.',
                                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                                  ),
                                  if (trackerProvider.filterOnlyCurrentSymbol && trackerProvider.withdrawals.isNotEmpty) ...[
                                    const SizedBox(height: 14),
                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.primary,
                                        side: const BorderSide(color: AppColors.primary),
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                      ),
                                      onPressed: () => trackerProvider.setFilterOnlyCurrentSymbol(false),
                                      icon: const Icon(Icons.visibility_outlined, size: 14),
                                      label: Text('Ver todos los gastos (${trackerProvider.withdrawals.length})', style: const TextStyle(fontSize: 12)),
                                    ),
                                  ],
                                ],
                              ),
                            )
                          : ListView.builder(
                              physics: const BouncingScrollPhysics(),
                              itemCount: currentExpenses.length,
                              itemBuilder: (context, i) {
                                final exp = currentExpenses[i];
                                return WithdrawalTile(
                                  withdrawal: exp,
                                  provider: trackerProvider,
                                  onSelectForMatch: () => _showMatchBuyForExpenseSheet(exp, trackerProvider),
                                );
                              },
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
}
