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
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 20,
            letterSpacing: 0.5,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.card,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Exchange:',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    dropdownColor: AppColors.surface,
                    value: watchlistProvider.currentExchange,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            AddSymbolBar(onAddSymbol: watchlistProvider.addSymbol),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'LISTA DE SEGUIMIENTO',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
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
            const SizedBox(height: 8),
            Expanded(
              child: watchlistProvider.symbols.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.star_border, size: 64, color: AppColors.border),
                          SizedBox(height: 16),
                          Text(
                            'Tu lista está vacía',
                            style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Busca y añade un par arriba.',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
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

                        return WatchlistItemTile(
                          symbol: symbol,
                          exchange: watchlistProvider.currentExchange,
                          price: price,
                          isSelected: isSelected,
                          onTap: () {
                            watchlistProvider.changeSymbol(symbol);
                            chartProvider.loadChartData(watchlistProvider.currentExchange, symbol);
                            onTabChange(1);
                          },
                          onDelete: () => watchlistProvider.removeSymbol(symbol),
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
