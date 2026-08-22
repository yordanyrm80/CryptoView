import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/watchlist_provider.dart';
import '../../chart/providers/chart_provider.dart';

class WatchlistScreen extends StatefulWidget {
  final Function(int) onTabChange; // To automatically switch to Chart tab

  const WatchlistScreen({Key? key, required this.onTabChange}) : super(key: key);

  @override
  _WatchlistScreenState createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final watchlistProvider = Provider.of<WatchlistProvider>(context);
    final chartProvider = Provider.of<ChartProvider>(context, listen: false);

    return Scaffold(
      backgroundColor: const Color(0xFF0C0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF12161F),
        elevation: 0,
        title: const Text(
          'CryptoView',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
            letterSpacing: 0.5,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: const Color(0xFF12161F),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Exchange:',
                  style: TextStyle(color: Color(0xFF90A4AE), fontSize: 14),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    dropdownColor: const Color(0xFF171A22),
                    value: watchlistProvider.currentExchange,
                    style: const TextStyle(
                      color: Color(0xFF00E6B8),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    items: <String>['Binance', 'KuCoin', 'BingX']
                        .map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        watchlistProvider.changeExchange(newValue);
                      }
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
            // Add Symbol Bar
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF171A22),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF263238), width: 1),
              ),
              child: Row(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12.0),
                    child: Icon(Icons.add_chart, color: Color(0xFF90A4AE)),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Añadir par (ej: SOL/USDT)...',
                        hintStyle: TextStyle(color: Color(0xFF546E7A)),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (value) {
                        if (value.isNotEmpty) {
                          watchlistProvider.addSymbol(value);
                          _searchController.clear();
                        }
                      },
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Color(0xFF00E6B8)),
                    onPressed: () {
                      if (_searchController.text.isNotEmpty) {
                        watchlistProvider.addSymbol(_searchController.text);
                        _searchController.clear();
                      }
                    },
                  )
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Watchlist Title
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'LISTA DE SEGUIMIENTO',
                  style: TextStyle(
                    color: Color(0xFF90A4AE),
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
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00E6B8)),
                    ),
                  )
              ],
            ),
            const SizedBox(height: 8),
            // Watchlist
            Expanded(
              child: watchlistProvider.symbols.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.star_border, size: 64, color: const Color(0xFF263238)),
                          const SizedBox(height: 16),
                          const Text(
                            'Tu lista está vacía',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Busca y añade un par arriba.',
                            style: TextStyle(color: Color(0xFF546E7A), fontSize: 14),
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

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFF1D2430) : const Color(0xFF171A22),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF00E6B8) : const Color(0xFF263238),
                              width: 1,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            onTap: () {
                              watchlistProvider.changeSymbol(symbol);
                              // Load chart data for selected pair
                              chartProvider.loadChartData(watchlistProvider.currentExchange, symbol);
                              // Auto-switch to Chart Tab
                              widget.onTabChange(1);
                            },
                            title: Text(
                              symbol,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            subtitle: Text(
                              watchlistProvider.currentExchange,
                              style: const TextStyle(
                                color: Color(0xFF546E7A),
                                fontSize: 12,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  price != null && price > 0
                                      ? '\$${price.toStringAsFixed(price < 1.0 ? 5 : 2)}'
                                      : 'Cargando...',
                                  style: TextStyle(
                                    color: isSelected ? const Color(0xFF00E6B8) : Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Color(0xFFF6465D), size: 20),
                                  onPressed: () {
                                    watchlistProvider.removeSymbol(symbol);
                                  },
                                ),
                              ],
                            ),
                          ),
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
