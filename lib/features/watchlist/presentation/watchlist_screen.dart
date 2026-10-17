import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/watchlist_provider.dart';
import '../../chart/providers/chart_provider.dart';
import 'widgets/add_symbol_bar.dart';
import 'widgets/watchlist_item_tile.dart';

class WatchlistScreen extends StatelessWidget {
  final Function(int) onTabChange;

  const WatchlistScreen({Key? key, required this.onTabChange}) : super(key: key);

  void _confirmDeleteSymbol(BuildContext context, WatchlistProvider watchlistProvider, String symbol) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: AppColors.bear, size: 22),
            SizedBox(width: 8),
            Text(
              'Eliminar moneda',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          '¿Estás seguro de que deseas eliminar $symbol de tu lista de seguimiento?',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.bear,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              watchlistProvider.removeSymbol(symbol);
            },
            child: const Text('Eliminar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final watchlistProvider = Provider.of<WatchlistProvider>(context);
    final chartProvider = Provider.of<ChartProvider>(context, listen: false);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        title: const Text(
          'CryptoView',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: 0.5,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            color: AppColors.card,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Flexible(
                  child: Text(
                    'Exchange:',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ),
                const SizedBox(width: 4),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isDense: true,
                    dropdownColor: AppColors.surface,
                    value: watchlistProvider.currentExchange,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    items: const ['Binance', 'KuCoin', 'BingX']
                        .map((val) => DropdownMenuItem(value: val, child: Text(val)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) watchlistProvider.changeExchange(val);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 10.0),
        child: Column(
          children: [
            AddSymbolBar(onAddSymbol: watchlistProvider.addSymbol),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'LISTA DE SEGUIMIENTO',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                if (watchlistProvider.isLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  )
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: watchlistProvider.symbols.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.star_border, size: 48, color: AppColors.border),
                          SizedBox(height: 12),
                          Text(
                            'Tu lista está vacía',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Busca y añade un par arriba.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: watchlistProvider.symbols.length,
                      itemBuilder: (context, index) {
                        final symbol = watchlistProvider.symbols[index];
                        final price = watchlistProvider.prices[symbol];
                        final isSelected = watchlistProvider.selectedSymbol == symbol;
                        final isFavorite = watchlistProvider.isFavorite(symbol);

                        return WatchlistItemTile(
                          symbol: symbol,
                          exchange: watchlistProvider.currentExchange,
                          price: price,
                          isSelected: isSelected,
                          isFavorite: isFavorite,
                          onTap: () {
                            watchlistProvider.changeSymbol(symbol);
                            chartProvider.loadChartData(watchlistProvider.currentExchange, symbol);
                            onTabChange(1);
                          },
                          onToggleFavorite: () => watchlistProvider.toggleFavorite(symbol),
                          onDelete: () => _confirmDeleteSymbol(context, watchlistProvider, symbol),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
