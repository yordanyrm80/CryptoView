import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/transaction_model.dart';
import '../../domain/withdrawal_model.dart';
import '../../providers/tracker_provider.dart';
import 'match_confirm_dialog.dart';

class SelectMatchCandidateSheet extends StatefulWidget {
  final TransactionModel sourceTx;
  final TrackerProvider provider;
  final VoidCallback onMatchedSuccessfully;

  const SelectMatchCandidateSheet({
    Key? key,
    required this.sourceTx,
    required this.provider,
    required this.onMatchedSuccessfully,
  }) : super(key: key);

  @override
  _SelectMatchCandidateSheetState createState() => _SelectMatchCandidateSheetState();
}

class _SelectMatchCandidateSheetState extends State<SelectMatchCandidateSheet> {
  bool _filterOnlySuggested = false;
  int _selectedTab = 0; // 0: Ventas Spot, 1: Gastos / Retiros

  String _formatAmount(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    String s = value.toStringAsFixed(6);
    s = s.replaceAll(RegExp(r'0+$'), '');
    s = s.replaceAll(RegExp(r'\.$'), '');
    return s;
  }

  void _showExpenseMatchConfirmDialog({
    required BuildContext context,
    required TransactionModel buy,
    required WithdrawalModel expense,
    required double maxMatchable,
    required String baseAsset,
  }) {
    final amountController = TextEditingController(text: _formatAmount(maxMatchable));
    final noteController = TextEditingController(text: expense.description ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.shopping_bag_outlined, color: Colors.orange, size: 20),
            SizedBox(width: 8),
            Text(
              'Casar Compra con Gasto',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Estás asociando esta compra de ${buy.symbol} (\$${buy.price.toStringAsFixed(2)}) con el gasto o retiro seleccionado.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 12),
            const Text('Cantidad a Conciliar', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 4),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
              decoration: InputDecoration(
                suffixText: baseAsset,
                suffixStyle: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Nota / Concepto', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            const SizedBox(height: 4),
            TextField(
              controller: noteController,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Ej. Amazon 1000 MXN, Walmart, etc.',
                hintStyle: const TextStyle(color: AppColors.textMuted),
                filled: true,
                fillColor: AppColors.card,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              final qty = double.tryParse(amountController.text.trim()) ?? 0.0;
              if (qty <= 0 || qty > maxMatchable + 0.000001) return;

              Navigator.pop(ctx);
              final success = await widget.provider.matchBuyWithExpense(
                buy: buy,
                expense: expense,
                amountToMatch: qty,
                note: noteController.text.trim(),
              );

              if (success) {
                widget.onMatchedSuccessfully();
              }
            },
            child: const Text('Confirmar Casamiento', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showDirectExpenseDialog({
    required BuildContext context,
    required TransactionModel buy,
    required double sourceRemaining,
    required String baseAsset,
  }) {
    final amountController = TextEditingController(text: _formatAmount(sourceRemaining));
    final noteController = TextEditingController();
    String selectedCategory = 'Compra Amazon';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
          title: const Row(
            children: [
              Icon(Icons.shopping_bag_outlined, color: Colors.orange, size: 20),
              SizedBox(width: 8),
              Text('Marcar Compra como Gasto', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Esta compra saldrá de "Compras vivas" y ya no se mostrará como compra abierta en el gráfico.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Text('Cantidad ($baseAsset)', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(height: 4),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                  decoration: InputDecoration(
                    suffixText: baseAsset,
                    suffixStyle: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                    filled: true,
                    fillColor: AppColors.card,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Categoría del Gasto', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  value: selectedCategory,
                  dropdownColor: AppColors.surface,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.card,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Compra Amazon', child: Text('Compra Amazon')),
                    DropdownMenuItem(value: 'Walmart / Cashi', child: Text('Walmart / Cashi')),
                    DropdownMenuItem(value: 'Gasto Personal', child: Text('Gasto Personal')),
                    DropdownMenuItem(value: 'Store Credit', child: Text('Store Credit')),
                    DropdownMenuItem(value: 'Recarga Móvil', child: Text('Recarga Móvil')),
                    DropdownMenuItem(value: 'Entretenimiento', child: Text('Entretenimiento')),
                    DropdownMenuItem(value: 'Otro Gasto', child: Text('Otro Gasto')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedCategory = val);
                  },
                ),
                const SizedBox(height: 12),
                const Text('Nota o Descripción', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                const SizedBox(height: 4),
                TextField(
                  controller: noteController,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Ej. Amazon 1000 MXN, Bitrefill, etc.',
                    hintStyle: const TextStyle(color: AppColors.textMuted),
                    filled: true,
                    fillColor: AppColors.card,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final qty = double.tryParse(amountController.text.trim()) ?? 0.0;
                if (qty <= 0 || qty > sourceRemaining + 0.000001) return;

                Navigator.pop(ctx);
                final success = await widget.provider.convertBuyToExpense(
                  buy: buy,
                  amount: qty,
                  description: noteController.text.trim().isNotEmpty
                      ? noteController.text.trim()
                      : '$selectedCategory: ${_formatAmount(qty)} $baseAsset',
                  category: selectedCategory,
                );

                if (success) {
                  widget.onMatchedSuccessfully();
                }
              },
              child: const Text('Confirmar Gasto', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sourceTx = widget.sourceTx;
    final provider = widget.provider;
    final isSourceBuy = sourceTx.type == 'buy';
    final targetType = isSourceBuy ? 'sell' : 'buy';
    final sourceRemaining = provider.getRemainingAmount(sourceTx);

    final parts = sourceTx.symbol.split('/');
    final baseAsset = parts.isNotEmpty ? parts[0] : 'ETH';
    final quoteAsset = parts.length > 1 ? parts[1] : (sourceTx.symbol.contains('-') ? sourceTx.symbol.split('-')[1] : 'USDT');

    final cleanSymbol = sourceTx.symbol.replaceAll('-', '/').toUpperCase();
    final cleanExchange = sourceTx.exchange.toLowerCase();

    // Standard buy block configured in settings (e.g. $400 USDT)
    final standardBuySize = provider.getBuyAmountForExchange(sourceTx.exchange);

    // Filter available opposite candidates (Spot)
    final rawCandidates = provider.transactions.where((tx) {
      if (tx.id == sourceTx.id) return false;
      if (tx.type != targetType) return false;
      if (tx.symbol.replaceAll('-', '/').toUpperCase() != cleanSymbol) return false;
      if (tx.exchange.toLowerCase() != cleanExchange) return false;
      return provider.getRemainingAmount(tx) > 0.000001;
    }).toList();

    // Available expenses/withdrawals for matching (when source is BUY)
    final availableExpenses = isSourceBuy
        ? provider.withdrawals.where((w) {
            if (w.currency.toUpperCase() != baseAsset.toUpperCase()) return false;
            return provider.getRemainingWithdrawalAmount(w) > 0.000001;
          }).toList()
        : <WithdrawalModel>[];

    // Calculate proximity scores for each candidate
    final scoredCandidates = rawCandidates.map((candidate) {
      final candRemaining = provider.getRemainingAmount(candidate);
      final candQuoteCost = candidate.price * candRemaining;
      
      // Cost proximity to configured standard buy size ($400)
      final costDiff = (candQuoteCost - standardBuySize).abs();
      final isNearStandardBlock = costDiff <= (standardBuySize * 0.25); // within 25% of $400 (e.g. $300-$500)

      // Token quantity proximity to source
      final tokenDiffRatio = sourceRemaining > 0 ? (candRemaining - sourceRemaining).abs() / sourceRemaining : 1.0;
      final isSimilarTokenSize = tokenDiffRatio <= 0.20; // within 20% of token amount

      // Chronological order: Did purchase occur before sale?
      final isChronological = isSourceBuy ? candidate.date.isAfter(sourceTx.date) : candidate.date.isBefore(sourceTx.date);

      // Best match flag: Near $400 block, similar token volume, and correct chronology
      final isIdealMatch = isNearStandardBlock && isSimilarTokenSize && isChronological;

      // Score (lower is better)
      double score = 0.0;
      score += (costDiff / standardBuySize) * 50.0;
      score += tokenDiffRatio * 50.0;
      if (!isChronological) score += 100.0;

      return {
        'candidate': candidate,
        'remaining': candRemaining,
        'quoteCost': candQuoteCost,
        'isIdeal': isIdealMatch,
        'isNear400': isNearStandardBlock,
        'isSimilarSize': isSimilarTokenSize,
        'score': score,
      };
    }).toList();

    // Sort by best score (most relevant first)
    scoredCandidates.sort((a, b) => (a['score'] as double).compareTo(b['score'] as double));

    final filteredList = _filterOnlySuggested
        ? scoredCandidates.where((item) => (item['isIdeal'] as bool) || (item['isNear400'] as bool)).toList()
        : scoredCandidates;

    final sourceDateStr = '${sourceTx.date.day.toString().padLeft(2, '0')}/${sourceTx.date.month.toString().padLeft(2, '0')}/${sourceTx.date.year}';

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Casar ${isSourceBuy ? "Compra" : "Venta"} de $cleanSymbol',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.textMuted, size: 20),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Source Transaction Card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (isSourceBuy ? AppColors.bull : AppColors.bear).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (isSourceBuy ? AppColors.bull : AppColors.bear).withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSourceBuy ? AppColors.bull : AppColors.bear,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isSourceBuy ? 'COMPRA' : 'VENTA',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$sourceDateStr · ${sourceTx.exchange}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Precio: \$${sourceTx.price.toStringAsFixed(sourceTx.price < 1 ? 4 : 2)} $quoteAsset',
                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Disponible: ${_formatAmount(sourceRemaining)} $baseAsset',
                      style: TextStyle(
                        color: isSourceBuy ? AppColors.bull : AppColors.bear,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Total: \$${(sourceTx.price * sourceRemaining).toStringAsFixed(2)} $quoteAsset',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Tab Bar for Buy Matching: Spot Sells vs Expenses/Withdrawals
          if (isSourceBuy) ...[
            Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: () => setState(() => _selectedTab = 0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _selectedTab == 0 ? AppColors.primary.withValues(alpha: 0.15) : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                          border: _selectedTab == 0 ? Border.all(color: AppColors.primary) : null,
                        ),
                        child: Center(
                          child: Text(
                            'Ventas Spot (${filteredList.length})',
                            style: TextStyle(
                              color: _selectedTab == 0 ? AppColors.primary : AppColors.textMuted,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: () => setState(() => _selectedTab = 1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _selectedTab == 1 ? Colors.orange.withValues(alpha: 0.15) : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                          border: _selectedTab == 1 ? Border.all(color: Colors.orange) : null,
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.shopping_bag_outlined, size: 14, color: _selectedTab == 1 ? Colors.orange : AppColors.textMuted),
                              const SizedBox(width: 4),
                              Text(
                                'Gastos / Retiros (${availableExpenses.length})',
                                style: TextStyle(
                                  color: _selectedTab == 1 ? Colors.orange : AppColors.textMuted,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Helper Bar for Spot Sells tab
          if (_selectedTab == 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Buscando compras cercanas a ~\$${standardBuySize.toStringAsFixed(0)} USDT (${filteredList.length}):',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    setState(() {
                      _filterOnlySuggested = !_filterOnlySuggested;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          _filterOnlySuggested ? Icons.check_box : Icons.check_box_outline_blank,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Solo ~\$${standardBuySize.toStringAsFixed(0)}',
                          style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],

          // Candidates List Area
          Expanded(
            child: _selectedTab == 1
                // TAB 1: Gastos / Retiros
                ? Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Text(
                                '¿Esta compra fue un gasto directo o consumo?',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                              onPressed: () {
                                _showDirectExpenseDialog(
                                  context: context,
                                  buy: sourceTx,
                                  sourceRemaining: sourceRemaining,
                                  baseAsset: baseAsset,
                                );
                              },
                              icon: const Icon(Icons.add, size: 14),
                              label: const Text('Nuevo Gasto', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: availableExpenses.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.shopping_bag_outlined, size: 44, color: AppColors.border),
                                      const SizedBox(height: 10),
                                      Text(
                                        'No hay retiros registrados sin casar en $baseAsset.',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 6),
                                      const Text(
                                        'Usa el botón "Nuevo Gasto" de arriba para convertirla en gasto directamente.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.builder(
                                physics: const BouncingScrollPhysics(),
                                itemCount: availableExpenses.length,
                                itemBuilder: (context, index) {
                          final exp = availableExpenses[index];
                          final expRemaining = provider.getRemainingWithdrawalAmount(exp);
                          final matchableQty = sourceRemaining < expRemaining ? sourceRemaining : expRemaining;
                          final expDateStr = '${exp.date.day.toString().padLeft(2, '0')}/${exp.date.month.toString().padLeft(2, '0')}/${exp.date.year}';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.card,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              exp.category.toUpperCase(),
                                              style: const TextStyle(color: Colors.orange, fontSize: 9, fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '$expDateStr · ${exp.exchange}',
                                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        (exp.description != null && exp.description!.isNotEmpty)
                                            ? exp.description!
                                            : 'Retiro de ${exp.currency}',
                                        style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Disponible: ${_formatAmount(expRemaining)} ${exp.currency} (Total: ${_formatAmount(exp.amount)})',
                                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                    minimumSize: const Size(64, 32),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _showExpenseMatchConfirmDialog(
                                      context: context,
                                      buy: sourceTx,
                                      expense: exp,
                                      maxMatchable: matchableQty,
                                      baseAsset: baseAsset,
                                    );
                                  },
                                  icon: const Icon(Icons.link, size: 14),
                                  label: const Text('Casar', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                )
                // TAB 0: Ventas Spot
                : (filteredList.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.link_off, size: 44, color: AppColors.border),
                              const SizedBox(height: 10),
                              Text(
                                _filterOnlySuggested
                                    ? 'No hay ${isSourceBuy ? "ventas" : "compras"} cercanas a ~\$${standardBuySize.toStringAsFixed(0)} USDT.'
                                    : 'No hay ${isSourceBuy ? "ventas" : "compras"} abiertas disponibles en $cleanSymbol.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              if (_filterOnlySuggested)
                                TextButton(
                                  onPressed: () => setState(() => _filterOnlySuggested = false),
                                  child: const Text('Mostrar todos los candidatos'),
                                ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: filteredList.length,
                        itemBuilder: (context, index) {
                          final item = filteredList[index];
                          final candidate = item['candidate'] as TransactionModel;
                          final candRemaining = item['remaining'] as double;
                          final candCost = item['quoteCost'] as double;
                          final isIdeal = item['isIdeal'] as bool;
                          final isNear400 = item['isNear400'] as bool;

                          final matchableQty = sourceRemaining < candRemaining ? sourceRemaining : candRemaining;

                          final buyTx = isSourceBuy ? sourceTx : candidate;
                          final sellTx = isSourceBuy ? candidate : sourceTx;

                          final buyFeeShare = (matchableQty / buyTx.amount) * buyTx.fee;
                          final sellFeeShare = (matchableQty / sellTx.amount) * sellTx.fee;
                          final grossProfit = (sellTx.price - buyTx.price) * matchableQty;
                          final netProfit = grossProfit - buyFeeShare - sellFeeShare;
                          final totalBuyCost = buyTx.price * matchableQty;
                          final profitPct = totalBuyCost > 0 ? (netProfit / totalBuyCost) * 100 : 0.0;
                          final isProfit = netProfit >= 0;

                          final candDateStr = '${candidate.date.day.toString().padLeft(2, '0')}/${candidate.date.month.toString().padLeft(2, '0')}/${candidate.date.year}';

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isIdeal ? AppColors.primary.withValues(alpha: 0.08) : AppColors.card,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isIdeal ? AppColors.primary : AppColors.border,
                                width: isIdeal ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            candDateStr,
                                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Precio: \$${candidate.price.toStringAsFixed(candidate.price < 1 ? 4 : 2)}',
                                            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                          if (isIdeal) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary,
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                '🎯 IDEAL',
                                                style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ] else if (isNear400) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary.withValues(alpha: 0.2),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: AppColors.primary, width: 0.6),
                                              ),
                                              child: Text(
                                                '~\$${standardBuySize.toStringAsFixed(0)}',
                                                style: const TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Compra: ${_formatAmount(candRemaining)} $baseAsset · Total: \$${candCost.toStringAsFixed(2)} $quoteAsset',
                                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Text(
                                            'PnL neto: ',
                                            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                                          ),
                                          Text(
                                            '${isProfit ? '+' : ''}\$${netProfit.toStringAsFixed(2)} (${isProfit ? '+' : ''}${profitPct.toStringAsFixed(1)}%)',
                                            style: TextStyle(
                                              color: isProfit ? AppColors.bull : AppColors.bear,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isProfit ? AppColors.bull : AppColors.secondary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                    minimumSize: const Size(64, 32),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  ),
                                  onPressed: () {
                                    Navigator.pop(context);
                                    showDialog(
                                      context: context,
                                      builder: (_) => MatchConfirmDialog(
                                        buy: buyTx,
                                        sell: sellTx,
                                        provider: provider,
                                        onMatchedSuccessfully: widget.onMatchedSuccessfully,
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.link, size: 14),
                                  label: const Text('Casar', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );
                        },
                      )),
          ),
        ],
      ),
    );
  }
}
