import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/bots_provider.dart';

Future<void> showBotPresetDialog(
  BuildContext context,
  BotsProvider provider, {
  required String strategyName,
  required double takeProfitPct,
  required double trailingStopPct,
  required double trendWeight,
  required List<double> baseWeights,
  required List<double> floorWeights,
  required double t0Rsi,
  required double panicRsi,
  required ValueChanged<String> onSavedName,
}) async {
  final nameCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  bool saving = false;

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.bookmark_add_outlined,
                color: AppColors.primary, size: 20),
            SizedBox(width: 8),
            Text(
              'Guardar Configuración de Estrategia',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Nombre de la Configuración',
                  hintText: 'ej. Agresiva Rango / Personalizada 01',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'Descripción / Notas (Opcional)',
                  hintText: 'ej. Mayor frecuencia en lateralización',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.save_outlined, size: 15),
            label: Text(saving ? 'Guardando...' : 'Guardar Configuración'),
            onPressed: saving
                ? null
                : () async {
                    final name = nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    setDialogState(() => saving = true);
                    final res = await provider.guardarConfiguracionEstrategia(
                      strategyName: strategyName,
                      name: name,
                      description: descCtrl.text.trim(),
                      takeProfitPct: takeProfitPct,
                      trailingStopPct: trailingStopPct,
                      trendWeight: trendWeight,
                      baseMaxTranches: baseWeights.length,
                      extraFloorTranches: floorWeights.length,
                      baseTrancheWeights: baseWeights,
                      floorTrancheWeights: floorWeights,
                      t0RsiThreshold: t0Rsi,
                      panicRsiThreshold: panicRsi,
                    );
                    final ok = res['ok'] == true;
                    final msg = (res['message'] ?? '').toString();
                    if (ctx.mounted) {
                      if (ok) {
                        onSavedName(name);
                        Navigator.pop(ctx);
                      } else {
                        setDialogState(() => saving = false);
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(msg),
                          backgroundColor:
                              ok ? AppColors.bull : AppColors.bear,
                        ),
                      );
                    }
                  },
          ),
        ],
      ),
    ),
  );
}
