import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/tracker_provider.dart';
import '../domain/transaction_model.dart';
import '../domain/match_model.dart';
import '../../watchlist/providers/watchlist_provider.dart';

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
    
    // Load SQLite data on entry
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<TrackerProvider>(context, listen: false).loadData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Dialog to manually insert a trade (buy/sell)
  void _showAddTransactionDialog() {
    final watchlistProvider = Provider.of<WatchlistProvider>(context, listen: false);
    final trackerProvider = Provider.of<TrackerProvider>(context, listen: false);
    
    String selectedType = 'buy';
    String selectedExchange = watchlistProvider.currentExchange;
    String selectedSymbol = watchlistProvider.selectedSymbol;

    final priceController = TextEditingController();
    final amountController = TextEditingController();
    final feeController = TextEditingController(text: '0.0');

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
                'Registrar Transacción',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Type selector
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: selectedType == 'buy' ? const Color(0xFF0ECB81) : const Color(0xFF263238),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () => setState(() => selectedType = 'buy'),
                            child: const Text('COMPRA (Buy)'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: selectedType == 'sell' ? const Color(0xFFF6465D) : const Color(0xFF263238),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () => setState(() => selectedType = 'sell'),
                            child: const Text('VENTA (Sell)'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Exchange selector
                    DropdownButtonFormField<String>(
                      dropdownColor: const Color(0xFF171A22),
                      value: selectedExchange,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Exchange',
                        labelStyle: TextStyle(color: Color(0xFF90A4AE)),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF263238))),
                      ),
                      items: ['Binance', 'KuCoin', 'BingX'].map((val) {
                        return DropdownMenuItem(value: val, child: Text(val));
                      }).toList(),
                      onChanged: (val) => setState(() => selectedExchange = val!),
                    ),
                    const SizedBox(height: 12),
                    // Symbol/Pair selector
                    DropdownButtonFormField<String>(
                      dropdownColor: const Color(0xFF171A22),
                      value: watchlistProvider.symbols.contains(selectedSymbol) ? selectedSymbol : watchlistProvider.symbols.first,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Par',
                        labelStyle: TextStyle(color: Color(0xFF90A4AE)),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF263238))),
                      ),
                      items: watchlistProvider.symbols.map((val) {
                        return DropdownMenuItem(value: val, child: Text(val));
                      }).toList(),
                      onChanged: (val) => setState(() => selectedSymbol = val!),
                    ),
                    const SizedBox(height: 12),
                    // Price
                    TextField(
                      controller: priceController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Precio de Ejecución (USD)',
                        labelStyle: TextStyle(color: Color(0xFF90A4AE)),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF263238))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Amount
                    TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Cantidad',
                        labelStyle: TextStyle(color: Color(0xFF90A4AE)),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF263238))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Commission Fee
                    TextField(
                      controller: feeController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Comisiones pagadas (USD)',
                        labelStyle: TextStyle(color: Color(0xFF90A4AE)),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF263238))),
                      ),
                    ),
                  ],
                ),
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
                    final price = double.tryParse(priceController.text) ?? 0.0;
                    final amount = double.tryParse(amountController.text) ?? 0.0;
                    final fee = double.tryParse(feeController.text) ?? 0.0;

                    if (price <= 0 || amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Ingresa valores válidos de precio y cantidad.')),
                      );
                      return;
                    }

                    final tx = TransactionModel(
                      exchange: selectedExchange,
                      symbol: selectedSymbol,
                      type: selectedType,
                      price: price,
                      amount: amount,
                      fee: fee,
                      date: DateTime.now(),
                    );

                    await trackerProvider.addTransaction(tx);
                    Navigator.pop(context);
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

  void _showTransactionDetail(TransactionModel tx, TrackerProvider provider) {
    final isBuy = tx.type == 'buy';
    final totalValue = tx.price * tx.amount;
    final remaining = provider.getRemainingAmount(tx);
    final dateStr = '${tx.date.day}/${tx.date.month}/${tx.date.year} ${tx.date.hour.toString().padLeft(2, '0')}:${tx.date.minute.toString().padLeft(2, '0')}';
    
    final parts = tx.symbol.split('/');
    final quoteAsset = parts.length > 1 ? parts[1] : 'USDT';
    final baseAsset = parts.isNotEmpty ? parts[0] : 'ETH';
    
    final matches = provider.matches.where((m) => m.buyTransactionId == tx.id || m.sellTransactionId == tx.id).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF171A22),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            border: Border(top: BorderSide(color: Color(0xFF263238), width: 1)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF546E7A).withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isBuy ? const Color(0xFF0ECB81).withOpacity(0.1) : const Color(0xFFF6465D).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isBuy ? 'COMPRA' : 'VENTA',
                              style: TextStyle(
                                color: isBuy ? const Color(0xFF0ECB81) : const Color(0xFFF6465D),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            tx.symbol,
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Exchange: ${tx.exchange}',
                        style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 13),
                      ),
                    ],
                  ),
                  Text(
                    dateStr,
                    style: const TextStyle(color: Color(0xFF546E7A), fontSize: 12),
                  ),
                ],
              ),
              const Divider(color: Color(0xFF263238), height: 32),
              Row(
                children: [
                  Expanded(
                    child: _detailField(
                      title: 'Precio',
                      value: '${tx.price.toStringAsFixed(tx.price > 1 ? 2 : 6)} $quoteAsset',
                    ),
                  ),
                  Expanded(
                    child: _detailField(
                      title: 'Cantidad',
                      value: '${tx.amount} $baseAsset',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _detailField(
                      title: 'Total Operado',
                      value: '${totalValue.toStringAsFixed(quoteAsset == 'USDT' || quoteAsset == 'USDC' ? 2 : 6)} $quoteAsset',
                      valueColor: isBuy ? const Color(0xFFF6465D) : const Color(0xFF0ECB81),
                    ),
                  ),
                  Expanded(
                    child: _detailField(
                      title: 'Comisión',
                      value: '${tx.fee} $quoteAsset',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _detailField(
                      title: 'Cantidad Disponible',
                      value: '$remaining / ${tx.amount} $baseAsset',
                      valueColor: remaining > 0 ? const Color(0xFF00E6B8) : const Color(0xFF546E7A),
                    ),
                  ),
                  Expanded(
                    child: _detailField(
                      title: 'Estado de Casamiento',
                      value: remaining == 0
                          ? 'Totalmente casado'
                          : remaining == tx.amount
                              ? 'Sin casar'
                              : 'Parcialmente casado',
                      valueColor: remaining == 0
                          ? const Color(0xFF0ECB81)
                          : remaining == tx.amount
                              ? const Color(0xFFF6465D)
                              : Colors.amber,
                    ),
                  ),
                ],
              ),
              if (matches.isNotEmpty) ...[
                const Divider(color: Color(0xFF263238), height: 32),
                const Text(
                  'Casamientos Relacionados',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: matches.length,
                    itemBuilder: (context, i) {
                      final m = matches[i];
                      final matchedText = isBuy 
                          ? 'Casado con venta a \$${m.sellPrice?.toStringAsFixed(2)}'
                          : 'Casado con compra a \$${m.buyPrice?.toStringAsFixed(2)}';
                      final profitText = m.profit != null
                          ? 'Ganancia: \$${m.profit!.toStringAsFixed(2)} (${(m.profit! / (m.buyPrice! * m.matchedAmount) * 100).toStringAsFixed(1)}%)'
                          : '';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0C0F14),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF263238)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  matchedText,
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Volumen casado: ${m.matchedAmount}',
                                  style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 11),
                                ),
                              ],
                            ),
                            if (profitText.isNotEmpty)
                              Text(
                                profitText,
                                style: TextStyle(
                                  color: m.profit! >= 0 ? const Color(0xFF0ECB81) : const Color(0xFFF6465D),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
              const Divider(color: Color(0xFF263238), height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF6465D).withOpacity(0.1),
                    foregroundColor: const Color(0xFFF6465D),
                    side: const BorderSide(color: Color(0xFFF6465D), width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        backgroundColor: const Color(0xFF171A22),
                        title: const Text('¿Eliminar transacción?', style: TextStyle(color: Colors.white)),
                        content: const Text(
                          'Se borrará la transacción. Si tiene casamientos vinculados, se desharán automáticamente.',
                          style: TextStyle(color: Color(0xFF90A4AE)),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancelar', style: TextStyle(color: Color(0xFF546E7A))),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Eliminar', style: TextStyle(color: Color(0xFFF6465D))),
                          ),
                        ],
                      ),
                    );

                    if (confirm == true) {
                      if (tx.id != null) {
                        await provider.deleteTransaction(tx.id!);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Transacción eliminada con éxito.')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.delete_forever, size: 18),
                  label: const Text('Eliminar Transacción', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _detailField({required String title, required String value, Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(color: Color(0xFF546E7A), fontSize: 11),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  void _showApiConfigDialog() {
    final trackerProvider = Provider.of<TrackerProvider>(context, listen: false);
    
    String selectedDialogExchange = 'Binance';
    final keyController = TextEditingController();
    final secretController = TextEditingController();
    final passphraseController = TextEditingController();
    
    bool isLoaded = false;
    bool hasKeys = false;

    void loadCredentialsForExchange(String ex, Function setState) {
      isLoaded = false;
      hasKeys = false;
      keyController.clear();
      secretController.clear();
      passphraseController.clear();
      
      trackerProvider.getCredentials(ex).then((creds) {
        if (creds != null) {
          keyController.text = creds['api_key'] ?? '';
          secretController.text = creds['api_secret'] ?? '';
          passphraseController.text = creds['api_passphrase'] ?? '';
          setState(() {
            hasKeys = true;
          });
        }
        isLoaded = true;
      });
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            if (!isLoaded) {
              final watchlistProvider = Provider.of<WatchlistProvider>(context, listen: false);
              selectedDialogExchange = watchlistProvider.currentExchange;
              loadCredentialsForExchange(selectedDialogExchange, setState);
            }

            final isKucoin = selectedDialogExchange.toLowerCase() == 'kucoin';

            return AlertDialog(
              backgroundColor: const Color(0xFF171A22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFF263238)),
              ),
              title: const Text(
                'Configuración API Exchanges',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<String>(
                      dropdownColor: const Color(0xFF171A22),
                      value: selectedDialogExchange,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Selecciona Exchange',
                        labelStyle: TextStyle(color: Color(0xFF90A4AE)),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF263238))),
                      ),
                      items: ['Binance', 'KuCoin', 'BingX'].map((val) {
                        return DropdownMenuItem(value: val, child: Text(val));
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          selectedDialogExchange = val!;
                          loadCredentialsForExchange(selectedDialogExchange, setState);
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Ingresa tus credenciales de solo lectura (permiso "General") para poder importar tu historial.',
                      style: TextStyle(color: Color(0xFF90A4AE), fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: keyController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'API Key',
                        labelStyle: TextStyle(color: Color(0xFF90A4AE)),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF263238))),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: secretController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'API Secret',
                        labelStyle: TextStyle(color: Color(0xFF90A4AE)),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF263238))),
                      ),
                    ),
                    if (isKucoin) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: passphraseController,
                        obscureText: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'API Passphrase',
                          labelStyle: TextStyle(color: Color(0xFF90A4AE)),
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF263238))),
                        ),
                      ),
                    ],
                    if (hasKeys) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0ECB81).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Color(0xFF0ECB81), size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Credenciales de $selectedDialogExchange configuradas.',
                                style: const TextStyle(color: Color(0xFF0ECB81), fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                if (hasKeys)
                  TextButton(
                    onPressed: () async {
                      await trackerProvider.deleteCredentials(selectedDialogExchange);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Credenciales de $selectedDialogExchange eliminadas.')),
                      );
                    },
                    child: const Text('Eliminar', style: TextStyle(color: Color(0xFFF6465D))),
                  ),
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
                    final key = keyController.text.trim();
                    final secret = secretController.text.trim();
                    final pass = passphraseController.text.trim();

                    if (key.isEmpty || secret.isEmpty || (isKucoin && pass.isEmpty)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Todos los campos son obligatorios.')),
                      );
                      return;
                    }

                    await trackerProvider.saveCredentials(
                      selectedDialogExchange,
                      key,
                      secret,
                      passphrase: isKucoin ? pass : null,
                    );
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF0ECB81),
                        content: Text('¡Credenciales de $selectedDialogExchange guardadas con éxito!'),
                      ),
                    );
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

  // Dialog to confirm matching Buy with Sell
  void _showMatchConfirmDialog(TrackerProvider provider) {
    if (_selectedBuyForMatch == null || _selectedSellForMatch == null) return;
    
    final buy = _selectedBuyForMatch!;
    final sell = _selectedSellForMatch!;

    final remainingBuy = provider.getRemainingAmount(buy);
    final remainingSell = provider.getRemainingAmount(sell);

    // Auto default to the maximum possible overlap volume
    final maxPossible = remainingBuy < remainingSell ? remainingBuy : remainingSell;
    final amountController = TextEditingController(text: maxPossible.toString());

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
            'Casar Operaciones',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Par: ${buy.symbol} (${buy.exchange})',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'Compra disponible: $remainingBuy',
                style: const TextStyle(color: Color(0xFF0ECB81)),
              ),
              Text(
                'Venta disponible: $remainingSell',
                style: const TextStyle(color: Color(0xFFF6465D)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Cantidad a Casar',
                  labelStyle: TextStyle(color: Color(0xFF90A4AE)),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF263238))),
                ),
              ),
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
                final qty = double.tryParse(amountController.text) ?? 0.0;
                if (qty <= 0 || qty > remainingBuy || qty > remainingSell) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cantidad de casamiento no válida.')),
                  );
                  return;
                }

                final success = await provider.matchTransactions(
                  buy: buy,
                  sell: sell,
                  amountToMatch: qty,
                );

                if (success) {
                  setState(() {
                    _selectedBuyForMatch = null;
                    _selectedSellForMatch = null;
                  });
                  Navigator.pop(context);
                  _tabController.animateTo(0); // Switch to Match History tab
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(backgroundColor: Color(0xFF0ECB81), content: Text('¡Operaciones casadas correctamente!')),
                  );
                }
              },
              child: const Text('Confirmar Casar'),
            )
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final trackerProvider = Provider.of<TrackerProvider>(context);
    final watchlistProvider = Provider.of<WatchlistProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0C0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12161F),
        elevation: 0,
        title: const Text(
          'Diario de Operaciones',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.vpn_key_outlined, color: Color(0xFF00E6B8)),
            tooltip: 'Configurar API KuCoin',
            onPressed: _showApiConfigDialog,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00E6B8),
          labelColor: const Color(0xFF00E6B8),
          unselectedLabelColor: const Color(0xFF90A4AE),
          tabs: const [
            Tab(text: 'HISTORIAL'),
            Tab(text: 'REGISTROS'),
            Tab(text: 'CASAR'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF00E6B8),
        foregroundColor: const Color(0xFF0C0F14),
        child: const Icon(Icons.add),
        onPressed: _showAddTransactionDialog,
      ),
      body: Column(
        children: [
          // Statistics Header
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF12161F),
            child: Row(
              children: [
                Expanded(
                  child: _metricCard(
                    title: 'GANANCIA NETO',
                    value: '\$${trackerProvider.totalProfit.toStringAsFixed(2)}',
                    color: trackerProvider.totalProfit >= 0 ? const Color(0xFF0ECB81) : const Color(0xFFF6465D),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _metricCard(
                    title: 'WIN RATE',
                    value: '${trackerProvider.winRate.toStringAsFixed(1)}%',
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          if (['binance', 'kucoin', 'bingx'].contains(watchlistProvider.currentExchange.toLowerCase()))
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF171A22),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF00E6B8).withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sync_alt, color: Color(0xFF00E6B8), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FutureBuilder<DateTime?>(
                      future: trackerProvider.getLastSyncDateForSymbol(watchlistProvider.currentExchange, watchlistProvider.selectedSymbol),
                      builder: (context, snapshot) {
                        final lastSync = snapshot.data;
                        final lastSyncStr = lastSync != null
                            ? 'Último sync: ${lastSync.day}/${lastSync.month}/${lastSync.year} ${lastSync.hour.toString().padLeft(2, '0')}:${lastSync.minute.toString().padLeft(2, '0')}'
                            : 'Sin sincronizar recientemente';
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Importar Historial de ${watchlistProvider.selectedSymbol} desde ${watchlistProvider.currentExchange}',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              lastSyncStr,
                              style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 11),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  _isSyncing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E6B8)),
                        )
                      : ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00E6B8),
                            foregroundColor: const Color(0xFF0C0F14),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () async {
                            setState(() => _isSyncing = true);
                            try {
                              final count = await trackerProvider.importTransactionsForSymbol(
                                watchlistProvider.currentExchange,
                                watchlistProvider.selectedSymbol,
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: const Color(0xFF0ECB81),
                                  content: Text('Se importaron $count nuevas transacciones de ${watchlistProvider.selectedSymbol} desde ${watchlistProvider.currentExchange}.'),
                                ),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: const Color(0xFFF6465D),
                                  content: Text('Error al importar: ${e.toString().replaceAll('Exception:', '')}'),
                                ),
                              );
                            } finally {
                              setState(() => _isSyncing = false);
                            }
                          },
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('Importar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                ],
              ),
            ),
          
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Match History (Historial de Casamientos)
                _buildMatchHistory(trackerProvider),
                
                // Tab 2: Raw Transactions Logs
                _buildTransactionsList(trackerProvider),
                
                // Tab 3: Coupling Panel (Casamiento Manual)
                _buildCouplingPanel(trackerProvider),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _metricCard({required String title, required String value, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF171A22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF263238)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchHistory(TrackerProvider provider) {
    final watchlistProvider = Provider.of<WatchlistProvider>(context, listen: false);
    final filteredMatches = provider.matches.where((m) => m.symbol == watchlistProvider.selectedSymbol).toList();

    if (filteredMatches.isEmpty) {
      return const Center(
        child: Text('No hay operaciones casadas aún.', style: TextStyle(color: Color(0xFF546E7A))),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: filteredMatches.length,
      itemBuilder: (context, index) {
        final match = filteredMatches[index];
        final isProfit = match.profit >= 0;

        return Card(
          color: const Color(0xFF171A22),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF263238)),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${match.symbol} (${match.exchange})',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                Text(
                  (isProfit ? '+' : '') + '\$${match.profit.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: isProfit ? const Color(0xFF0ECB81) : const Color(0xFFF6465D),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),
                Text(
                  'Volumen: ${match.matchedAmount}',
                  style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 13),
                ),
                Text(
                  'Compra: \$${match.buyPrice?.toStringAsFixed(2)} | Venta: \$${match.sellPrice?.toStringAsFixed(2)}',
                  style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 13),
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.link_off, color: Color(0xFFF6465D)),
              tooltip: 'Deshacer casamiento',
              onPressed: () async {
                await provider.deleteMatch(match);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Casamiento deshecho. El volumen vuelve a estar disponible.')),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildTransactionsList(TrackerProvider provider) {
    final watchlistProvider = Provider.of<WatchlistProvider>(context, listen: false);
    final filteredTransactions = provider.transactions.where((tx) => tx.symbol == watchlistProvider.selectedSymbol).toList();

    if (filteredTransactions.isEmpty) {
      return const Center(
        child: Text('No hay registros de transacciones.', style: TextStyle(color: Color(0xFF546E7A))),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: filteredTransactions.length,
      itemBuilder: (context, index) {
        final tx = filteredTransactions[index];
        final isBuy = tx.type == 'buy';
        final parts = tx.symbol.split('/');
        final quoteAsset = parts.length > 1 ? parts[1] : 'USDT';
        final baseAsset = parts.isNotEmpty ? parts[0] : 'ETH';
        final totalStr = (tx.price * tx.amount).toStringAsFixed(quoteAsset == 'USDT' || quoteAsset == 'USDC' ? 2 : 6);
        final priceStr = tx.price.toStringAsFixed(tx.price > 1 ? 2 : 6);
        final dateStr = '${tx.date.day}/${tx.date.month}/${tx.date.year} ${tx.date.hour.toString().padLeft(2, '0')}:${tx.date.minute.toString().padLeft(2, '0')}';

        return Card(
          color: const Color(0xFF171A22),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF263238)),
          ),
          child: ListTile(
            onTap: () => _showTransactionDetail(tx, provider),
            leading: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isBuy ? const Color(0xFF0ECB81).withOpacity(0.1) : const Color(0xFFF6465D).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isBuy ? 'BUY' : 'SELL',
                style: TextStyle(
                  color: isBuy ? const Color(0xFF0ECB81) : const Color(0xFFF6465D),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${tx.symbol} (${tx.exchange})',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  dateStr,
                  style: const TextStyle(color: Color(0xFF546E7A), fontSize: 11),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  'Precio: $priceStr $quoteAsset | Cantidad: ${tx.amount} $baseAsset',
                  style: const TextStyle(color: Color(0xFF90A4AE)),
                ),
                Text(
                  'Total: $totalStr $quoteAsset',
                  style: const TextStyle(color: Color(0xFF546E7A), fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            trailing: const Icon(
              Icons.chevron_right,
              color: Color(0xFF546E7A),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCouplingPanel(TrackerProvider provider) {
    final watchlistProvider = Provider.of<WatchlistProvider>(context, listen: false);
    final buys = provider.openBuys.where((tx) => tx.symbol == watchlistProvider.selectedSymbol).toList();
    final sells = provider.openSells.where((tx) => tx.symbol == watchlistProvider.selectedSymbol).toList();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Text(
            'Selecciona una compra y una venta para enlazarlas:',
            style: TextStyle(color: Color(0xFF90A4AE), fontSize: 13),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              children: [
                // Open Buys list
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'COMPRAS (Buys)',
                        style: TextStyle(color: Color(0xFF0ECB81), fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: buys.isEmpty
                            ? const Center(child: Text('Sin compras', style: TextStyle(color: Color(0xFF546E7A), fontSize: 12)))
                            : ListView.builder(
                                physics: const BouncingScrollPhysics(),
                                itemCount: buys.length,
                                itemBuilder: (context, index) {
                                  final tx = buys[index];
                                  final isSelected = _selectedBuyForMatch?.id == tx.id;
                                  final remaining = provider.getRemainingAmount(tx);

                                  return GestureDetector(
                                    onTap: () => setState(() => _selectedBuyForMatch = tx),
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isSelected ? const Color(0xFF0ECB81).withOpacity(0.2) : const Color(0xFF171A22),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isSelected ? const Color(0xFF0ECB81) : const Color(0xFF263238),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            tx.symbol,
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                          Text('Prec: \$${tx.price}', style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 12)),
                                          Text('Disp: $remaining', style: const TextStyle(color: Color(0xFF546E7A), fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      )
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // Open Sells list
                Expanded(
                  child: Column(
                    children: [
                      const Text(
                        'VENTAS (Sells)',
                        style: TextStyle(color: Color(0xFFF6465D), fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: sells.isEmpty
                            ? const Center(child: Text('Sin ventas', style: TextStyle(color: Color(0xFF546E7A), fontSize: 12)))
                            : ListView.builder(
                                physics: const BouncingScrollPhysics(),
                                itemCount: sells.length,
                                itemBuilder: (context, index) {
                                  final tx = sells[index];
                                  final isSelected = _selectedSellForMatch?.id == tx.id;
                                  final remaining = provider.getRemainingAmount(tx);

                                  return GestureDetector(
                                    onTap: () => setState(() => _selectedSellForMatch = tx),
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(vertical: 4),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isSelected ? const Color(0xFFF6465D).withOpacity(0.2) : const Color(0xFF171A22),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isSelected ? const Color(0xFFF6465D) : const Color(0xFF263238),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            tx.symbol,
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                          Text('Prec: \$${tx.price}', style: const TextStyle(color: Color(0xFF90A4AE), fontSize: 12)),
                                          Text('Disp: $remaining', style: const TextStyle(color: Color(0xFF546E7A), fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      )
                    ],
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Match Action Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00E6B8),
                foregroundColor: const Color(0xFF0C0F14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                disabledBackgroundColor: const Color(0xFF263238),
              ),
              onPressed: (_selectedBuyForMatch != null && _selectedSellForMatch != null)
                  ? () => _showMatchConfirmDialog(provider)
                  : null,
              child: const Text(
                'CASAR SELECCIONADOS',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
