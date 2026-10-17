class MatchModel {
  final int? id;
  final int buyTransactionId;
  final int sellTransactionId;
  final double matchedAmount;
  final double profit;
  final DateTime date;
  final int? withdrawalId;
  final String matchType; // 'trade' or 'expense'
  final String notes;

  // Joined fields for UI convenience
  final double? buyPrice;
  final double? sellPrice;
  final String? symbol;
  final String? exchange;
  final String? expenseDescription;
  final String? expenseCategory;

  MatchModel({
    this.id,
    required this.buyTransactionId,
    this.sellTransactionId = 0,
    required this.matchedAmount,
    required this.profit,
    required this.date,
    this.withdrawalId,
    this.matchType = 'trade',
    this.notes = '',
    this.buyPrice,
    this.sellPrice,
    this.symbol,
    this.exchange,
    this.expenseDescription,
    this.expenseCategory,
  });

  bool get isExpenseMatch => matchType == 'expense' || withdrawalId != null;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'buy_transaction_id': buyTransactionId,
      'sell_transaction_id': sellTransactionId,
      'matched_amount': matchedAmount,
      'profit': profit,
      'date': date.toUtc().toIso8601String(),
      'withdrawal_id': withdrawalId,
      'match_type': matchType,
      'notes': notes,
    };
  }

  factory MatchModel.fromMap(Map<String, dynamic> map) {
    return MatchModel(
      id: map['id'] as int?,
      buyTransactionId: (map['buy_transaction_id'] as int?) ?? 0,
      sellTransactionId: (map['sell_transaction_id'] as int?) ?? 0,
      matchedAmount: (map['matched_amount'] as num).toDouble(),
      profit: (map['profit'] as num).toDouble(),
      date: DateTime.parse((map['date'] ?? map['match_date']) as String).toUtc(),
      withdrawalId: map['withdrawal_id'] as int?,
      matchType: (map['match_type'] as String?) ?? 'trade',
      notes: (map['notes'] as String?) ?? '',
      buyPrice: map['buy_price'] != null ? (map['buy_price'] as num).toDouble() : null,
      sellPrice: map['sell_price'] != null ? (map['sell_price'] as num).toDouble() : null,
      symbol: map['symbol'] as String?,
      exchange: map['exchange'] as String?,
      expenseDescription: map['expense_description'] as String?,
      expenseCategory: map['expense_category'] as String?,
    );
  }
}
