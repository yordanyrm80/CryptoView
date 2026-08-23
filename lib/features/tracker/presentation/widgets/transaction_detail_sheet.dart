import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/transaction_model.dart';
import '../../providers/tracker_provider.dart';

class TransactionDetailSheet extends StatelessWidget {
  final TransactionModel tx;
  final TrackerProvider provider;

  const TransactionDetailSheet({Key? key, required this.tx, required this.provider}) : super(key: key);

  Widget _detailField({required String title, required String value, Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(color: valueColor ?? AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBuy = tx.type == 'buy';
    final totalValue = tx.price * tx.amount;
    final remaining = provider.getRemainingAmount(tx);
    final dateStr = '${tx.date.day}/${tx.date.month}/${tx.date.year} ${tx.date.hour.toString().padLeft(2, '0')}:${tx.date.minute.toString().padLeft(2, '0')}';

    final parts = tx.symbol.split('/');
    final quoteAsset = parts.length > 1 ? parts[1] : 'USDT';
    final baseAsset = parts.isNotEmpty ? parts[0] : 'ETH';

    final matches = provider.matches.where((m) => m.buyTransactionId == tx.id || m.sellTransactionId == tx.id).toList();

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
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
                color: AppColors.textMuted.withOpacity(0.3),
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
                          color: isBuy ? AppColors.bull.withOpacity(0.1) : AppColors.bear.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isBuy ? 'COMPRA' : 'VENTA',
                          style: TextStyle(
                            color: isBuy ? AppColors.bull : AppColors.bear,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(tx.symbol, style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Exchange: ${tx.exchange}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                ],
              ),
              Text(dateStr, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ),
          const Divider(color: AppColors.border, height: 32),
          Row(
            children: [
              Expanded(child: _detailField(title: 'Precio', value: '${tx.price.toStringAsFixed(tx.price > 1 ? 2 : 6)} $quoteAsset')),
              Expanded(child: _detailField(title: 'Cantidad', value: '${tx.amount} $baseAsset')),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _detailField(
                  title: 'Total Operado',
                  value: '${totalValue.toStringAsFixed(quoteAsset == 'USDT' || quoteAsset == 'USDC' ? 2 : 6)} $quoteAsset',
                  valueColor: isBuy ? AppColors.bear : AppColors.bull,
                ),
              ),
              Expanded(child: _detailField(title: 'Comisión', value: '${tx.fee} $quoteAsset')),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _detailField(
                  title: 'Cantidad Disponible',
                  value: '$remaining / ${tx.amount} $baseAsset',
                  valueColor: remaining > 0 ? AppColors.primary : AppColors.textMuted,
                ),
              ),
              Expanded(
                child: _detailField(
                  title: 'Estado de Casamiento',
                  value: remaining == 0 ? 'Totalmente casado' : remaining == tx.amount ? 'Sin casar' : 'Parcialmente casado',
                  valueColor: remaining == 0 ? AppColors.bull : remaining == tx.amount ? AppColors.bear : AppColors.secondary,
                ),
              ),
            ],
          ),
          if (matches.isNotEmpty) ...[
            const Divider(color: AppColors.border, height: 32),
            const Text('Casamientos Relacionados', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
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
                  
                  final buyPrice = m.buyPrice ?? 1.0;
                  final percent = buyPrice > 0 ? (m.profit / (buyPrice * m.matchedAmount) * 100).toStringAsFixed(1) : '0';
                  final profitText = 'Ganancia: \$${m.profit.toStringAsFixed(2)} ($percent%)';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(matchedText, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)),
                            const SizedBox(height: 2),
                            Text('Volumen casado: ${m.matchedAmount}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                          ],
                        ),
                        Text(
                          profitText,
                          style: TextStyle(
                            color: m.profit >= 0 ? AppColors.bull : AppColors.bear,
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
          const Divider(color: AppColors.border, height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.bear.withOpacity(0.1),
                foregroundColor: AppColors.bear,
                side: const BorderSide(color: AppColors.bear, width: 1),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: AppColors.surface,
                    title: const Text('¿Eliminar transacción?', style: TextStyle(color: AppColors.textPrimary)),
                    content: const Text(
                      'Se borrará la transacción. Si tiene casamientos vinculados, se desharán automáticamente.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted))),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar', style: TextStyle(color: AppColors.bear))),
                    ],
                  ),
                );

                if (confirm == true && tx.id != null) {
                  await provider.deleteTransaction(tx.id!);
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transacción eliminada con éxito.')));
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
  }
}
