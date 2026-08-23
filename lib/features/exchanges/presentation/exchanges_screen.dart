import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../tracker/providers/tracker_provider.dart';
import '../../watchlist/providers/watchlist_provider.dart';
import '../../tracker/presentation/widgets/api_config_dialog.dart';

class ExchangesScreen extends StatefulWidget {
  const ExchangesScreen({Key? key}) : super(key: key);

  @override
  _ExchangesScreenState createState() => _ExchangesScreenState();
}

class _ExchangesScreenState extends State<ExchangesScreen> {
  String _selectedExchange = 'KuCoin';
  int _selectedLookbackDays = 730; // 7, 30, 730
  final TextEditingController _buyAmountController = TextEditingController(text: '100.0');

  final List<String> _exchanges = ['KuCoin', 'Binance', 'BingX'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadExchangeSettings();
    });
  }

  @override
  void dispose() {
    _buyAmountController.dispose();
    super.dispose();
  }

  Future<void> _loadExchangeSettings() async {
    final trackerProvider = Provider.of<TrackerProvider>(context, listen: false);
    final amount = await trackerProvider.getDefaultBuyAmount(_selectedExchange);
    _buyAmountController.text = amount.toStringAsFixed(2);
    await trackerProvider.fetchLiveBalance(_selectedExchange);
  }

  Future<void> _saveBuyAmount() async {
    final amount = double.tryParse(_buyAmountController.text) ?? 100.0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un monto válido mayor a 0.')),
      );
      return;
    }
    final trackerProvider = Provider.of<TrackerProvider>(context, listen: false);
    await trackerProvider.setDefaultBuyAmount(_selectedExchange, amount);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.bull,
          content: Text('Monto habitual guardado: \$$amount USDT para $_selectedExchange'),
        ),
      );
    }
  }

  void _showApiDialog() {
    final trackerProvider = Provider.of<TrackerProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (_) => ApiConfigDialog(
        trackerProvider: trackerProvider,
        defaultExchange: _selectedExchange,
      ),
    ).then((_) {
      trackerProvider.fetchLiveBalance(_selectedExchange);
    });
  }

  Future<void> _startBatchSync(List<String> favorites) async {
    if (favorites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.secondary,
          content: Text('No tienes monedas marcadas como favoritas ⭐ en el Watchlist.'),
        ),
      );
      return;
    }

    final trackerProvider = Provider.of<TrackerProvider>(context, listen: false);

    try {
      final total = await trackerProvider.importBatchTransactions(
        exchange: _selectedExchange,
        symbols: favorites,
        lookbackDays: _selectedLookbackDays,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.bull,
            content: Text('¡Sincronización masiva finalizada! Se importaron $total transacciones nuevas.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.bear,
            content: Text('Error en sincronización: $e'),
            action: SnackBarAction(
              label: 'Configurar API',
              textColor: Colors.white,
              onPressed: _showApiDialog,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final trackerProvider = Provider.of<TrackerProvider>(context);
    final watchlistProvider = Provider.of<WatchlistProvider>(context);
    final favorites = watchlistProvider.favoriteSymbols;
    final isImporting = trackerProvider.isImporting;

    final balance = trackerProvider.exchangeBalances['USDT'] ?? 0.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        title: const Text(
          'Gestión de Exchanges & Sincronización',
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 17),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Selector de Exchange
            Row(
              children: _exchanges.map((ex) {
                final isSelected = ex == _selectedExchange;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSelected ? AppColors.primary : AppColors.surface,
                        foregroundColor: isSelected ? AppColors.background : AppColors.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: isSelected ? AppColors.primary : AppColors.border),
                        ),
                      ),
                      onPressed: isImporting
                          ? null
                          : () {
                              setState(() => _selectedExchange = ex);
                              _loadExchangeSettings();
                            },
                      child: Text(ex, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // 2. Card de Saldo y Credenciales API
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.account_balance_wallet, color: AppColors.primary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Saldo Disponible ($_selectedExchange)',
                            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: trackerProvider.isFetchingBalance
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                            : const Icon(Icons.refresh, color: AppColors.textSecondary, size: 20),
                        tooltip: 'Actualizar Saldo',
                        onPressed: trackerProvider.isFetchingBalance ? null : () => trackerProvider.fetchLiveBalance(_selectedExchange),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '\$${balance.toStringAsFixed(2)} USDT',
                    style: const TextStyle(color: AppColors.bull, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: AppColors.border, height: 1),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Credenciales API', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.vpn_key_outlined, size: 16),
                        label: const Text('Configurar API', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: isImporting ? null : _showApiDialog,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 3. Card de Configuración de Compras Manuales
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.shopping_cart_outlined, color: AppColors.secondary, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Monto Habitual de Compras Manuales',
                        style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Cantidad estándar en USDT con la que sueles operar manualmente:',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _buyAmountController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                          decoration: InputDecoration(
                            prefixText: '\$ ',
                            prefixStyle: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                            suffixText: 'USDT',
                            suffixStyle: const TextStyle(color: AppColors.textSecondary),
                            filled: true,
                            fillColor: AppColors.background,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.background,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _saveBuyAmount,
                        child: const Text('Guardar', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [50, 100, 200, 500, 1000].map((val) {
                      return ActionChip(
                        backgroundColor: AppColors.card,
                        label: Text('\$$val', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                        onPressed: () {
                          _buyAmountController.text = val.toDouble().toStringAsFixed(2);
                          _saveBuyAmount();
                        },
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 4. Card de Sincronización Masiva de Favoritas
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.history_edu, color: AppColors.primary, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Sincronización de Historial en Lote',
                        style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Selecciona el rango de tiempo a consultar en $_selectedExchange:',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 10),

                  Row(
                    children: [
                      _buildTimeRangeChip(label: 'Última Semana (7d)', days: 7),
                      const SizedBox(width: 6),
                      _buildTimeRangeChip(label: 'Último Mes (30d)', days: 30),
                      const SizedBox(width: 6),
                      _buildTimeRangeChip(label: 'Máximo (2 años)', days: 730),
                    ],
                  ),

                  const SizedBox(height: 16),
                  const Divider(color: AppColors.border, height: 1),
                  const SizedBox(height: 12),

                  // Monedas Favoritas a Sincronizar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            'Monedas Favoritas (${favorites.length})',
                            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                      const Text('Definidas con ⭐ en Seguimiento', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (favorites.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: AppColors.secondary, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Marca con la estrella ⭐ en la pestaña Seguimiento las monedas que deseas sincronizar.',
                              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: favorites.map((sym) {
                        return Chip(
                          backgroundColor: AppColors.card,
                          avatar: const Icon(Icons.star, color: Colors.amber, size: 14),
                          label: Text(sym, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                          side: const BorderSide(color: AppColors.border),
                        );
                      }).toList(),
                    ),

                  const SizedBox(height: 16),

                  // Panel de Progreso en Vivo
                  if (isImporting) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Progreso (${(trackerProvider.importProgress * 100).toInt()}%)',
                                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              Text(
                                '${trackerProvider.importFoundCount} ops encontradas',
                                style: const TextStyle(color: AppColors.bull, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: trackerProvider.importProgress > 0 ? trackerProvider.importProgress : null,
                              backgroundColor: AppColors.card,
                              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                              minHeight: 6,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            trackerProvider.importStatusMessage,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Botón Principal de Sincronización
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.bull,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        disabledBackgroundColor: AppColors.border,
                      ),
                      icon: isImporting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.cloud_download, size: 20),
                      label: Text(
                        isImporting ? 'Sincronizando...' : 'Importar Historial de Monedas Favoritas ⭐',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      onPressed: isImporting ? null : () => _startBatchSync(favorites),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeRangeChip({required String label, required int days}) {
    final isSelected = _selectedLookbackDays == days;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedLookbackDays = days),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : AppColors.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? AppColors.primary : AppColors.border),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? AppColors.background : AppColors.textSecondary,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        ),
      ),
    );
  }
}
