import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/bot_models.dart';
import '../../providers/bots_provider.dart';

Future<void> showBotCapitalDialog(
  BuildContext context,
  BotsProvider provider,
  ResumenBot bot,
  bool esDeposito,
) async {
  final currencyFmt = NumberFormat.currency(symbol: r'$', decimalDigits: 2);
  final montoCtrl = TextEditingController();
  final notaCtrl = TextEditingController(
    text: esDeposito
        ? 'Asignación adicional de capital operativo'
        : 'Retiro de rendimientos a cuenta principal',
  );

  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      title: Row(
        children: [
          Icon(
            esDeposito
                ? Icons.south_west_rounded
                : Icons.north_east_rounded,
            color: esDeposito ? AppColors.bull : Colors.amber,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            esDeposito ? 'Asignar Capital al Bot' : 'Retirar Liquidez del Bot',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bot.idBot,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        bot.simbolo,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Reserva Disponible',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 10),
                      ),
                      Text(
                        '${currencyFmt.format(bot.usdtDisponible)} USDT',
                        style: const TextStyle(
                          color: AppColors.bull,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: montoCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Importe en USDT',
                prefixText: r'$ ',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notaCtrl,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 13),
              decoration: const InputDecoration(
                labelText: 'Concepto / Referencia contable',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: esDeposito ? AppColors.bull : Colors.amber,
            foregroundColor: Colors.black,
          ),
          onPressed: () async {
            final monto =
                double.tryParse(montoCtrl.text.replaceAll(',', '.').trim()) ??
                    0.0;
            if (monto <= 0) return;
            Navigator.pop(ctx);
            final ok = esDeposito
                ? await provider.depositarCapital(bot.idBot, monto,
                    motivo: notaCtrl.text.trim())
                : await provider.retirarCapital(bot.idBot, monto,
                    motivo: notaCtrl.text.trim());
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(ok
                      ? 'Ajuste de capital registrado correctamente.'
                      : 'No se pudo procesar la operación en el servidor.'),
                  backgroundColor:
                      ok ? AppColors.bull : AppColors.bear,
                ),
              );
            }
          },
          child: Text(
            esDeposito ? 'Confirmar Asignación' : 'Confirmar Retiro',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
}
