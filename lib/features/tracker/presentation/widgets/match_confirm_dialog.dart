import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/transaction_model.dart';
import '../../providers/tracker_provider.dart';

class MatchConfirmDialog extends StatefulWidget {
  final TransactionModel buy;
  final TransactionModel sell;
  final TrackerProvider provider;
  final VoidCallback onMatchedSuccessfully;

  const MatchConfirmDialog({
    Key? key,
    required this.buy,
    required this.sell,
    required this.provider,
    required this.onMatchedSuccessfully,
  }) : super(key: key);

  @override
  _MatchConfirmDialogState createState() => _MatchConfirmDialogState();
}

class _MatchConfirmDialogState extends State<MatchConfirmDialog> {
  late final TextEditingController _amountController;
  late final double _remainingBuy;
  late final double _remainingSell;

  @override
  void initState() {
    super.initState();
    _remainingBuy = widget.provider.getRemainingAmount(widget.buy);
    _remainingSell = widget.provider.getRemainingAmount(widget.sell);
    final maxPossible = _remainingBuy < _remainingSell ? _remainingBuy : _remainingSell;
    _amountController = TextEditingController(text: maxPossible.toString());
  }

  @override
  void dispose() {
    _amountController.dispose();
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
      title: const Text('Casar Operaciones', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Par: ${widget.buy.symbol} (${widget.buy.exchange})', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text('Compra disponible: $_remainingBuy', style: const TextStyle(color: AppColors.bull)),
          Text('Venta disponible: $_remainingSell', style: const TextStyle(color: AppColors.bear)),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Cantidad a Casar',
              labelStyle: TextStyle(color: AppColors.textSecondary),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
            ),
          ),
        ],
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
            final qty = double.tryParse(_amountController.text) ?? 0.0;
            if (qty <= 0 || qty > _remainingBuy || qty > _remainingSell) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cantidad de casamiento no válida.')));
              return;
            }

            final success = await widget.provider.matchTransactions(
              buy: widget.buy,
              sell: widget.sell,
              amountToMatch: qty,
            );

            if (success) {
              Navigator.pop(context);
              widget.onMatchedSuccessfully();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(backgroundColor: AppColors.bull, content: Text('¡Operaciones casadas correctamente!')),
              );
            }
          },
          child: const Text('Confirmar Casar'),
        )
      ],
    );
  }
}
