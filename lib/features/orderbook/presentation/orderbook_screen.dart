import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../providers/orderbook_provider.dart';
import '../../watchlist/providers/watchlist_provider.dart';

class OrderBookScreen extends StatefulWidget {
  final void Function(double price, String side)? onPriceSelected;

  const OrderBookScreen({
    Key? key,
    this.onPriceSelected,
  }) : super(key: key);

  @override
  State<OrderBookScreen> createState() => _OrderBookScreenState();
}

class _OrderBookScreenState extends State<OrderBookScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final orderBookProvider = Provider.of<OrderBookProvider>(context);
    final watchlistProvider = Provider.of<WatchlistProvider>(context);

    final currentExchange = watchlistProvider.currentExchange;
    final currentSymbol = watchlistProvider.selectedSymbol;
    final currentPrice = watchlistProvider.prices[currentSymbol];

    // Ensure orderbook is initialized
    orderBookProvider.init(currentExchange, currentSymbol);

    return Container(
      color: const Color(0xFF0B0E11),
      child: Column(
        children: [
          // Sub-Tab Header
          Container(
            height: 38,
            color: AppColors.card,
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: AppColors.primary,
                    indicatorWeight: 2,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.textMuted,
                    labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    tabs: const [
                      Tab(text: 'Libro de Órdenes'),
                      Tab(text: 'Últimos Trades'),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16, color: AppColors.textSecondary),
                  tooltip: 'Recargar Libro',
                  onPressed: () => orderBookProvider.fetchOrderBookAndTrades(),
                ),
              ],
            ),
          ),

          // Main View
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOrderBookTab(orderBookProvider, currentPrice),
                _buildRecentTradesTab(orderBookProvider),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderBookTab(OrderBookProvider provider, double? currentPrice) {
    if (provider.isLoading && provider.bids.isEmpty && provider.asks.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    final asks = provider.asks.reversed.toList(); // Highest price at top
    final bids = provider.bids;

    return Column(
      children: [
        // Column Headers
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: const Color(0xFF131722),
          child: const Row(
            children: [
              Expanded(flex: 3, child: Text('Precio (USDT)', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold))),
              Expanded(flex: 3, child: Text('Cantidad', textAlign: TextAlign.right, style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold))),
              Expanded(flex: 3, child: Text('Total (USDT)', textAlign: TextAlign.right, style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold))),
            ],
          ),
        ),

        // Asks (Ventas en Rojo)
        Expanded(
          flex: 1,
          child: ListView.builder(
            reverse: true, // Scroll to bottom near spread
            itemCount: asks.length,
            itemBuilder: (context, index) {
              final item = asks[index];
              return _buildBookRow(item, isBid: false, maxCum: provider.maxCumulative);
            },
          ),
        ),

        // Spread / Current Price Bar (Center)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF181D26),
            border: Border.symmetric(horizontal: BorderSide(color: AppColors.border.withValues(alpha: 0.5), width: 1)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    currentPrice != null && currentPrice > 0
                        ? '\$${currentPrice.toStringAsFixed(currentPrice < 1.0 ? 4 : 2)}'
                        : '--',
                    style: const TextStyle(
                      color: AppColors.bull,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_upward, color: AppColors.bull, size: 14),
                ],
              ),
              Text(
                'Spread: \$${provider.spread.toStringAsFixed(provider.spread < 1.0 ? 4 : 2)} (${provider.spreadPct.toStringAsFixed(2)}%)',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),

        // Bids (Compras en Verde)
        Expanded(
          flex: 1,
          child: ListView.builder(
            itemCount: bids.length,
            itemBuilder: (context, index) {
              final item = bids[index];
              return _buildBookRow(item, isBid: true, maxCum: provider.maxCumulative);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBookRow(OrderBookItem item, {required bool isBid, required double maxCum}) {
    final depthRatio = (item.cumulativeAmount / maxCum).clamp(0.0, 1.0);
    final color = isBid ? AppColors.bull : AppColors.bear;
    final depthBgColor = isBid ? AppColors.bull.withValues(alpha: 0.12) : AppColors.bear.withValues(alpha: 0.12);

    return InkWell(
      onTap: () {
        if (widget.onPriceSelected != null) {
          widget.onPriceSelected!(item.price, isBid ? 'buy' : 'sell');
        }
      },
      child: Stack(
        children: [
          // Depth Bar
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: depthRatio,
                child: Container(color: depthBgColor),
              ),
            ),
          ),
          // Row Content
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3.5),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    item.price.toStringAsFixed(item.price < 1.0 ? 4 : 2),
                    style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    item.amount.toStringAsFixed(4),
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 11),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    item.total.toStringAsFixed(2),
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentTradesTab(OrderBookProvider provider) {
    if (provider.recentTrades.isEmpty) {
      return const Center(child: Text('Sin datos de trades recientes', style: TextStyle(color: AppColors.textMuted)));
    }

    final timeFormat = DateFormat('HH:mm:ss');

    return Column(
      children: [
        // Column Headers
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: const Color(0xFF131722),
          child: const Row(
            children: [
              Expanded(flex: 3, child: Text('Hora', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold))),
              Expanded(flex: 3, child: Text('Precio (USDT)', textAlign: TextAlign.right, style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold))),
              Expanded(flex: 3, child: Text('Cantidad', textAlign: TextAlign.right, style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.bold))),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: provider.recentTrades.length,
            itemBuilder: (context, index) {
              final trade = provider.recentTrades[index];
              final isBuy = trade.side == 'buy';
              final color = isBuy ? AppColors.bull : AppColors.bear;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(timeFormat.format(trade.time), style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        trade.price.toStringAsFixed(trade.price < 1.0 ? 4 : 2),
                        textAlign: TextAlign.right,
                        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        trade.amount.toStringAsFixed(4),
                        textAlign: TextAlign.right,
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
