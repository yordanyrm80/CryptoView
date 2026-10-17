class WithdrawalModel {
  final int? id;
  final String exchange;
  final String currency; // e.g. 'BTC', 'LTC', 'USDT'
  final double amount;
  final double fee;
  final DateTime date;
  final String? txId;
  final String? address;
  final String? description; // e.g. 'Amazon.com.mx 1000 MXN'
  final String category; // e.g. 'Gasto Personal', 'Retiro', 'Compra'
  final bool isMatched;

  WithdrawalModel({
    this.id,
    required this.exchange,
    required this.currency,
    required this.amount,
    this.fee = 0.0,
    required this.date,
    this.txId,
    this.address,
    this.description,
    this.category = 'Gasto Personal',
    this.isMatched = false,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'exchange': exchange,
      'currency': currency,
      'amount': amount,
      'fee': fee,
      'date': date.toUtc().toIso8601String(),
      'tx_id': txId,
      'address': address,
      'description': description,
      'category': category,
      'is_matched': isMatched ? 1 : 0,
    };
  }

  factory WithdrawalModel.fromMap(Map<String, dynamic> map) {
    return WithdrawalModel(
      id: map['id'] as int?,
      exchange: map['exchange'] as String,
      currency: map['currency'] as String,
      amount: (map['amount'] as num).toDouble(),
      fee: (map['fee'] as num?)?.toDouble() ?? 0.0,
      date: DateTime.parse(map['date'] as String).toUtc(),
      txId: map['tx_id'] as String?,
      address: map['address'] as String?,
      description: map['description'] as String?,
      category: (map['category'] as String?) ?? 'Gasto Personal',
      isMatched: (map['is_matched'] as int?) == 1,
    );
  }

  WithdrawalModel copyWith({
    int? id,
    String? exchange,
    String? currency,
    double? amount,
    double? fee,
    DateTime? date,
    String? txId,
    String? address,
    String? description,
    String? category,
    bool? isMatched,
  }) {
    return WithdrawalModel(
      id: id ?? this.id,
      exchange: exchange ?? this.exchange,
      currency: currency ?? this.currency,
      amount: amount ?? this.amount,
      fee: fee ?? this.fee,
      date: date ?? this.date,
      txId: txId ?? this.txId,
      address: address ?? this.address,
      description: description ?? this.description,
      category: category ?? this.category,
      isMatched: isMatched ?? this.isMatched,
    );
  }
}
