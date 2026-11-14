import 'package:flutter_test/flutter_test.dart';
import 'package:cryptoview/features/bots/domain/bot_models.dart';

void main() {
  group('OrdenEjecutadaBot', () {
    test('parses OPEN resting limit order with tranche metadata', () {
      final order = OrdenEjecutadaBot.fromJson({
        'id': '6af8035cc9003600077d1720',
        'bot_id': 'apex_titan_btc_live',
        'symbol': 'BTC/USDT',
        'side': 'sell',
        'order_type': 'limit',
        'price': 79125.1,
        'amount': 0.00792709,
        'fee': 0.0,
        'status': 'open',
        'created_at': 1794638684000,
        'filled_at': null,
        'tranche_index': 0,
        'tranche_id': 7,
        'target_sell_price': 79125.101,
        'reason': 'Resting TP T0',
      });

      expect(order.side, 'SELL');
      expect(order.tipoOrden, 'LIMIT');
      expect(order.estaAbierta, isTrue);
      expect(order.estaCerrada, isFalse);
      expect(order.estaCancelada, isFalse);
      expect(order.indiceTramo, 0);
      expect(order.idTramo, 7);
      expect(order.precioObjetivoVenta, closeTo(79125.101, 1e-6));
      expect(order.motivo, 'Resting TP T0');
      expect(order.fechaEjecucion, isNull);
    });

    test('parses CANCELED expired buy limit order and CLOSED order with filled_at', () {
      final canceled = OrdenEjecutadaBot.fromJson({
        'id': 'ord_exp',
        'bot_id': 'apex_titan_btc_live',
        'symbol': 'BTC/USDT',
        'side': 'BUY',
        'order_type': 'LIMIT',
        'price': 68000.0,
        'amount': 0.005,
        'fee': 0.0,
        'status': 'canceled',
        'created_at': 1794638000000,
      });
      expect(canceled.estaCancelada, isTrue);
      expect(canceled.estaAbierta, isFalse);

      final closed = OrdenEjecutadaBot.fromJson({
        'id': 'ord_closed',
        'bot_id': 'apex_titan_btc_live',
        'symbol': 'BTC/USDT',
        'side': 'SELL',
        'order_type': 'STOP_MARKET',
        'price': 84500.0,
        'amount': 0.01,
        'fee': 0.845,
        'status': 'CLOSED',
        'created_at': 1794638000000,
        'filled_at': 1794638060000,
      });
      expect(closed.estaCerrada, isTrue);
      expect(closed.tipoOrden, 'STOP_MARKET');
      expect(closed.fechaEjecucion, isNotNull);
    });
  });
}
