import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/transaction_model.dart';
import '../../providers/tracker_provider.dart';
import '../../../watchlist/providers/watchlist_provider.dart';

class AddTransactionDialog extends StatefulWidget {
  final WatchlistProvider watchlistProvider;
  final TrackerProvider trackerProvider;

  const AddTransactionDialog({
    Key? key,
    required this.watchlistProvider,
    required this.trackerProvider,
  }) : super(key: key);

  @override
  _AddTransactionDialogState createState() => _AddTransactionDialogState();
}

class _AddTransactionDialogState extends State<AddTransactionDialog> {
  String _selectedType = 'buy';
  late String _selectedExchange;
  late String _selectedSymbol;

  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _feeController = TextEditingController(text: '0.0');

  @override
  void initState() {
    super.initState();
    _selectedExchange = widget.watchlistProvider.currentExchange;
    _selectedSymbol = widget.watchlistProvider.selectedSymbol;
  }

  @override
  void dispose() {
    _priceController.dispose();
    _amountController.dispose();
    _feeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      title: const Text('Registrar Transacción', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedType == 'buy' ? AppColors.bull : AppColors.border,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => setState(() => _selectedType = 'buy'),
                    child: const Text('COMPRA (Buy)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedType == 'sell' ? AppColors.bear : AppColors.border,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => setState(() => _selectedType = 'sell'),
                    child: const Text('VENTA (Sell)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              dropdownColor: AppColors.surface,
              value: _selectedExchange,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Exchange',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
              ),
              items: const ['Binance', 'KuCoin', 'BingX'].map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(),
              onChanged: (val) => setState(() => _selectedExchange = val!),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              dropdownColor: AppColors.surface,
              value: widget.watchlistProvider.symbols.contains(_selectedSymbol) ? _selectedSymbol : widget.watchlistProvider.symbols.first,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Par',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
              ),
              items: widget.watchlistProvider.symbols.map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(),
              onChanged: (val) => setState(() => _selectedSymbol = val!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Precio de Ejecución (USD)',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Cantidad',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _feeController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Comisiones pagadas (USD)',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.background,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () async {
            final price = double.tryParse(_priceController.text) ?? 0.0;
            final amount = double.tryParse(_amountController.text) ?? 0.0;
            final fee = double.tryParse(_feeController.text) ?? 0.0;

            if (price <= 0 || amount <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Ingresa valores válidos de precio y cantidad.')),
              );
              return;
            }

            final tx = TransactionModel(
              exchange: _selectedExchange,
              symbol: _selectedSymbol,
              type: _selectedType,
              price: price,
              amount: amount,
              fee: fee,
              date: DateTime.now(),
            );

            await widget.trackerProvider.addTransaction(tx);
            Navigator.pop(context);
          },
          child: const Text('Guardar'),
        )
      ],
    );
  }
}
