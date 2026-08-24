class TransactionModel {
  final int? id;
  final String exchange;
  final String symbol;
  final String type; // 'buy' or 'sell'
  final double price;
  final double amount;
  final double fee;
  final DateTime date;
  final bool isMatched;

  TransactionModel({
    this.id,
    required this.exchange,
    required this.symbol,
    required this.type,
    required this.price,
    required this.amount,
    required this.fee,
    required this.date,
    this.isMatched = false,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'exchange': exchange,
      'symbol': symbol,
      'type': type,
      'price': price,
      'amount': amount,
      'fee': fee,
      'date': date.toUtc().toIso8601String(),
      'is_matched': isMatched ? 1 : 0,
    };
  }

  factory TransactionModel.fromMap(Map<String, dynamic> map) {
    return TransactionModel(
      id: map['id'] as int?,
      exchange: map['exchange'] as String,
      symbol: map['symbol'] as String,
      type: map['type'] as String,
      price: (map['price'] as num).toDouble(),
      amount: (map['amount'] as num).toDouble(),
      fee: (map['fee'] as num).toDouble(),
      date: DateTime.parse(map['date'] as String).toUtc(),
      isMatched: map['is_matched'] == 1,
    );
  }

  TransactionModel copyWith({
    int? id,
    String? exchange,
    String? symbol,
    String? type,
    double? price,
    double? amount,
    double? fee,
    DateTime? date,
    bool? isMatched,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      exchange: exchange ?? this.exchange,
      symbol: symbol ?? this.symbol,
      type: type ?? this.type,
      price: price ?? this.price,
      amount: amount ?? this.amount,
      fee: fee ?? this.fee,
      date: date ?? this.date,
      isMatched: isMatched ?? this.isMatched,
    );
  }
}
