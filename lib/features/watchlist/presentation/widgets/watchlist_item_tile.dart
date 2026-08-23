import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class WatchlistItemTile extends StatelessWidget {
  final String symbol;
  final String exchange;
  final double? price;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const WatchlistItemTile({
    Key? key,
    required this.symbol,
    required this.exchange,
    required this.price,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.cardSelected : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? AppColors.primary : AppColors.border,
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        onTap: onTap,
        title: Text(
          symbol,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          exchange,
          style: const TextStyle(
            color: AppColors.textMuted,
            fontSize: 12,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              price != null && price! > 0
                  ? '\$${price!.toStringAsFixed(price! < 1.0 ? 5 : 2)}'
                  : 'Cargando...',
              style: TextStyle(
                color: isSelected ? AppColors.primary : AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.bear, size: 20),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
