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
  late final double _maxPossible;

  String _formatAmount(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    String s = value.toStringAsFixed(6);
    s = s.replaceAll(RegExp(r'0+$'), '');
    s = s.replaceAll(RegExp(r'\.$'), '');
    return s;
  }

  @override
  void initState() {
    super.initState();
    _remainingBuy = widget.provider.getRemainingAmount(widget.buy);
    _remainingSell = widget.provider.getRemainingAmount(widget.sell);
    _maxPossible = _remainingBuy < _remainingSell ? _remainingBuy : _remainingSell;
    _amountController = TextEditingController(text: _formatAmount(_maxPossible));
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final qty = double.tryParse(_amountController.text) ?? 0.0;
    final buyFeeShare = widget.buy.amount > 0 ? (qty / widget.buy.amount) * widget.buy.fee : 0.0;
    final sellFeeShare = widget.sell.amount > 0 ? (qty / widget.sell.amount) * widget.sell.fee : 0.0;
    final grossProfit = (widget.sell.price - widget.buy.price) * qty;
    final netProfit = grossProfit - buyFeeShare - sellFeeShare;
    final totalBuyCost = widget.buy.price * qty;
    final profitPct = totalBuyCost > 0 ? (netProfit / totalBuyCost) * 100 : 0.0;
    final isProfit = netProfit >= 0;

    final parts = widget.buy.symbol.split('/');
    final baseAsset = parts.isNotEmpty ? parts[0] : 'ETH';
    final quoteAsset = parts.length > 1 ? parts[1] : 'USDT';

    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      title: Row(
        children: [
          const Icon(Icons.link, color: AppColors.primary, size: 22),
          const SizedBox(width: 8),
          const Text('Confirmar Casamiento', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.buy.symbol} · ${widget.buy.exchange}',
              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 12),

            // Buy Card
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bull.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.bull.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('COMPRA', style: TextStyle(color: AppColors.bull, fontWeight: FontWeight.bold, fontSize: 10)),
                      const SizedBox(height: 2),
                      Text('Precio: \$${widget.buy.price.toStringAsFixed(widget.buy.price < 1 ? 4 : 2)}', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                  Text('Disp: ${_formatAmount(_remainingBuy)} $baseAsset', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Sell Card
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bear.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.bear.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('VENTA', style: TextStyle(color: AppColors.bear, fontWeight: FontWeight.bold, fontSize: 10)),
                      const SizedBox(height: 2),
                      Text('Precio: \$${widget.sell.price.toStringAsFixed(widget.sell.price < 1 ? 4 : 2)}', style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                  Text('Disp: ${_formatAmount(_remainingSell)} $baseAsset', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Quantity to Match Input
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      labelText: 'Cantidad a Casar ($baseAsset)',
                      labelStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      filled: true,
                      fillColor: AppColors.card,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.primary)),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    setState(() {
                      _amountController.text = _formatAmount(_maxPossible);
                    });
                  },
                  child: const Text('MÁX', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Projected Profit Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (isProfit ? AppColors.bull : AppColors.bear).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isProfit ? AppColors.bull : AppColors.bear),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Resultado Neto:', style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                  Text(
                    '${isProfit ? '+' : ''}\$${netProfit.toStringAsFixed(2)} $quoteAsset (${isProfit ? '+' : ''}${profitPct.toStringAsFixed(2)}%)',
                    style: TextStyle(
                      color: isProfit ? AppColors.bull : AppColors.bear,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
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
            backgroundColor: isProfit ? AppColors.bull : AppColors.secondary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () async {
            final qtyToMatch = double.tryParse(_amountController.text) ?? 0.0;
            if (qtyToMatch <= 0 || qtyToMatch > _remainingBuy + 0.00001 || qtyToMatch > _remainingSell + 0.00001) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cantidad de casamiento no válida.')));
              return;
            }

            final finalQty = qtyToMatch > _maxPossible ? _maxPossible : qtyToMatch;

            final success = await widget.provider.matchTransactions(
              buy: widget.buy,
              sell: widget.sell,
              amountToMatch: finalQty,
            );

            if (success) {
              Navigator.pop(context);
              widget.onMatchedSuccessfully();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppColors.bull,
                  content: Text('¡Operaciones casadas con éxito! PnL: ${isProfit ? '+' : ''}\$${netProfit.toStringAsFixed(2)}'),
                ),
              );
            }
          },
          child: const Text('Confirmar Casar', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

