import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:criptobot_ui/theme/app_theme.dart';
import 'package:criptobot_ui/models/bot_models.dart';

void main() {
  testWidgets('Validación de modelos y temas en Flutter', (WidgetTester tester) async {
    final bot = ResumenBot(
      idBot: 'btc_quantum_apex',
      simbolo: 'BTC/USDT',
      nombreEstrategia: 'BtcQuantumCompoundRegimeStrategy',
      presupuesto: 10000.0,
      estado: 'RUNNING',
      simulacionDryRun: true,
      tramosActivos: 1,
      montoInvertidoUsdt: 3000.0,
      beneficioRealizadoUsdt: 150.0,
      equidadActualUsdt: 10150.0,
      tasaAciertoPct: 100.0,
      operacionesTotales: 1,
    );

    expect(bot.idBot, 'btc_quantum_apex');
    expect(bot.equidadActualUsdt, 10150.0);

    // Probar renderizado de un widget básico con el tema de la app
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.temaOscuro,
        home: const Scaffold(
          body: Center(child: Text('CRIPTOBOT INSTITUCIONAL')),
        ),
      ),
    );

    expect(find.text('CRIPTOBOT INSTITUCIONAL'), findsOneWidget);
  });
}
