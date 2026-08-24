class MatchModel {
  final int? id;
  final int buyTransactionId;
  final int sellTransactionId;
  final double matchedAmount;
  final double profit;
  final DateTime date;

  // Joined fields for UI convenience
  final double? buyPrice;
  final double? sellPrice;
  final String? symbol;
  final String? exchange;

  MatchModel({
    this.id,
    required this.buyTransactionId,
    required this.sellTransactionId,
    required this.matchedAmount,
    required this.profit,
    required this.date,
    this.buyPrice,
    this.sellPrice,
    this.symbol,
    this.exchange,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'buy_transaction_id': buyTransactionId,
      'sell_transaction_id': sellTransactionId,
      'matched_amount': matchedAmount,
      'profit': profit,
      'date': date.toUtc().toIso8601String(),
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
      buyPrice: map['buy_price'] != null ? (map['buy_price'] as num).toDouble() : null,
      sellPrice: map['sell_price'] != null ? (map['sell_price'] as num).toDouble() : null,
      symbol: map['symbol'] as String?,
      exchange: map['exchange'] as String?,
    );
  }
}
