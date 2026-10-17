import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/withdrawal_model.dart';
import '../../providers/tracker_provider.dart';

class WithdrawalTile extends StatelessWidget {
  final WithdrawalModel withdrawal;
  final TrackerProvider provider;
  final VoidCallback? onSelectForMatch;

  const WithdrawalTile({
    super.key,
    required this.withdrawal,
    required this.provider,
    this.onSelectForMatch,
  });

  String _formatAmount(double val) {
    String s = val.toStringAsFixed(8);
    while (s.contains('.') && (s.endsWith('0') || s.endsWith('.'))) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  void _editDescription(BuildContext context) {
    final controller = TextEditingController(text: withdrawal.description ?? '');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.border)),
        title: const Row(
          children: [
            Icon(Icons.edit_note, color: AppColors.secondary, size: 20),
            SizedBox(width: 8),
            Text('Nota / Descripción del Gasto', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Ej. Amazon 1000 MXN, Cashi Walmart, etc.',
            hintStyle: const TextStyle(color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.card,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await provider.updateWithdrawal(withdrawal.copyWith(description: controller.text.trim()));
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.border)),
        title: const Text('Eliminar Registro', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
        content: Text('¿Deseas eliminar este registro de ${withdrawal.currency}?', style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.bear, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              if (withdrawal.id != null) {
                await provider.deleteWithdrawal(withdrawal.id!);
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final remaining = provider.getRemainingWithdrawalAmount(withdrawal);
    final isPartiallyMatched = remaining < withdrawal.amount;
    final isFullyMatched = remaining == 0 || withdrawal.isMatched;
    final dateStr = '${withdrawal.date.day.toString().padLeft(2, '0')}/${withdrawal.date.month.toString().padLeft(2, '0')}/${withdrawal.date.year}';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isFullyMatched ? AppColors.bull.withValues(alpha: 0.4) : AppColors.border,
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: Category Tag & Currency | Status Badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.shopping_bag_outlined, color: Colors.orange, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            withdrawal.category.toUpperCase(),
                            style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      withdrawal.currency,
                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                if (isFullyMatched)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.bull.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.bull, width: 0.8),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline, color: AppColors.bull, size: 13),
                        SizedBox(width: 4),
                        Text('CONCILIADO', style: TextStyle(color: AppColors.bull, fontWeight: FontWeight.bold, fontSize: 11)),
                      ],
                    ),
                  )
                else if (isPartiallyMatched)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.secondary, width: 0.8),
                    ),
                    child: const Text('PARCIAL', style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold, fontSize: 11)),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // Row 2: Description & Notes
            InkWell(
              onTap: () => _editDescription(context),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined, color: AppColors.textMuted, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        (withdrawal.description != null && withdrawal.description!.isNotEmpty)
                            ? withdrawal.description!
                            : 'Toca para agregar nota (ej. Amazon 1000 MXN)...',
                        style: TextStyle(
                          color: (withdrawal.description != null && withdrawal.description!.isNotEmpty) ? AppColors.textPrimary : AppColors.textMuted,
                          fontSize: 12,
                          fontStyle: (withdrawal.description != null && withdrawal.description!.isNotEmpty) ? FontStyle.normal : FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(Icons.edit, color: AppColors.textMuted, size: 13),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Row 3: Total amount & Fee
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total: ${_formatAmount(withdrawal.amount)} ${withdrawal.currency}',
                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    if (withdrawal.fee > 0)
                      Text(
                        'Comisión: ${_formatAmount(withdrawal.fee)} ${withdrawal.currency}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        const Text('Por conciliar: ', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                        Text(
                          '${_formatAmount(remaining)} ${withdrawal.currency}',
                          style: TextStyle(
                            color: isPartiallyMatched ? AppColors.secondary : Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    Text('${withdrawal.exchange} · $dateStr', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 8),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 8),

            // Row 4: Actions (Delete, Dust, Match)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: AppColors.textMuted, size: 18),
                  tooltip: 'Eliminar registro',
                  onPressed: () => _confirmDelete(context),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isFullyMatched && (isPartiallyMatched || remaining < 0.001)) ...[
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.secondary,
                          side: BorderSide(color: AppColors.secondary.withValues(alpha: 0.6)),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          minimumSize: const Size(60, 30),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () => provider.dismissExpenseDust(withdrawal),
                        icon: const Icon(Icons.cleaning_services, size: 12),
                        label: const Text('Polvillo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (onSelectForMatch != null && !isFullyMatched) ...[
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.withValues(alpha: 0.15),
                          foregroundColor: Colors.orange,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                          minimumSize: const Size(75, 32),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: Colors.orange, width: 1),
                          ),
                        ),
                        onPressed: onSelectForMatch,
                        icon: const Icon(Icons.link, size: 14),
                        label: const Text('Casar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
