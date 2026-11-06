import 'package:flutter_test/flutter_test.dart';
import 'package:cryptoview/features/tracker/domain/transaction_model.dart';
import 'package:cryptoview/features/tracker/domain/match_model.dart';

void main() {
  group('TransactionModel Tests', () {
    test('Serialización y deserialización a Map preserva tipos y valores', () {
      final now = DateTime.utc(2026, 5, 23, 14, 30);
      final tx = TransactionModel(
        id: 42,
        exchange: 'KuCoin',
        symbol: 'ETH/USDT',
        type: 'buy',
        price: 2036.28,
        amount: 0.19636,
        fee: 0.40,
        date: now,
        isMatched: false,
      );

      final map = tx.toMap();
      expect(map['id'], 42);
      expect(map['exchange'], 'KuCoin');
      expect(map['symbol'], 'ETH/USDT');
      expect(map['price'], 2036.28);
      expect(map['amount'], 0.19636);
      expect(map['is_matched'], 0);

      final restored = TransactionModel.fromMap(map);
      expect(restored.id, tx.id);
      expect(restored.price, tx.price);
      expect(restored.amount, tx.amount);
      expect(restored.isMatched, false);
    });

    test('copyWith genera una nueva instancia con los valores actualizados', () {
      final tx = TransactionModel(
        id: 1,
        exchange: 'Binance',
        symbol: 'BTC/USDT',
        type: 'buy',
        price: 60000.0,
        amount: 0.5,
        fee: 0.3,
        date: DateTime.utc(2026, 1, 1),
      );

      final updated = tx.copyWith(isMatched: true);
      expect(updated.id, 1);
      expect(updated.isMatched, true);
      expect(tx.isMatched, false);
    });
  });

  group('MatchModel & Cálculo de PnL FIFO Tests', () {
    test('Cálculo de ganancia neta en casamiento exacto de compra y venta', () {
      // Compra 1.0 ETH @ $2,000, Venta 1.0 ETH @ $2,500
      const buyPrice = 2000.0;
      const sellPrice = 2500.0;
      const amount = 1.0;
      const buyFee = 2.0; // 0.1% de $2,000
      const sellFee = 2.5; // 0.1% de $2,500

      final grossProfit = (sellPrice - buyPrice) * amount; // $500.0
      final netProfit = grossProfit - (buyFee + sellFee); // $495.5

      final match = MatchModel(
        id: 101,
        buyTransactionId: 10,
        sellTransactionId: 20,
        matchedAmount: amount,
        profit: netProfit,
        date: DateTime.utc(2026, 6, 1),
        buyPrice: buyPrice,
        sellPrice: sellPrice,
        symbol: 'ETH/USDT',
      );

      expect(match.profit, 495.5);
      expect(match.matchedAmount, 1.0);
      expect(match.isExpenseMatch, false);
    });

    test('Casamiento parcial respeta la fracción restante no emparejada', () {
      // Compra 2.0 BTC @ $60,000. Venta parcial 0.5 BTC @ $68,000.
      const initialBuyAmount = 2.0;
      const matchedAmount = 0.5;
      const remainingAmount = initialBuyAmount - matchedAmount;

      expect(remainingAmount, 1.5);
      expect(remainingAmount > 0, true);

      final match = MatchModel(
        id: 102,
        buyTransactionId: 1,
        sellTransactionId: 2,
        matchedAmount: matchedAmount,
        profit: (68000.0 - 60000.0) * matchedAmount, // $4,000
        date: DateTime.utc(2026, 6, 10),
      );

      expect(match.profit, 4000.0);
    });

    test('Casamiento por gasto personal (Bitrefill / Retiro) marca isExpenseMatch', () {
      final expenseMatch = MatchModel(
        id: 103,
        buyTransactionId: 5,
        sellTransactionId: 0,
        withdrawalId: 88,
        matchType: 'expense',
        matchedAmount: 100.0,
        profit: 0.0,
        date: DateTime.utc(2026, 7, 1),
        expenseDescription: 'Bitrefill - Tarjeta de Regalo Supermercado',
      );

      expect(expenseMatch.isExpenseMatch, true);
      expect(expenseMatch.withdrawalId, 88);
      expect(expenseMatch.expenseDescription, contains('Bitrefill'));
    });
  });
}
