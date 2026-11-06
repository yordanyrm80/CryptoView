import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/bot_models.dart';
import '../../providers/bots_provider.dart';
import 'bot_dialog_helpers.dart';
import 'bot_preset_dialog.dart';

Future<void> showBotStrategyParamsDialog(
  BuildContext context,
  BotsProvider provider,
  ResumenBot bot,
) async {
  final availableConfigs =
      provider.configuracionesParaEstrategia(bot.nombreEstrategia);
  String selectedConfigId = availableConfigs.first.id;

  final tpCtrl =
      TextEditingController(text: bot.takeProfitPct.toString());
  final tsCtrl =
      TextEditingController(text: bot.trailingStopPct.toString());
  final trendCtrl = TextEditingController(
      text: (bot.pesoTendencia * 100.0).toStringAsFixed(0));
  final rsiT0Ctrl =
      TextEditingController(text: bot.umbralRsiT0.toStringAsFixed(1));
  final rsiPanicCtrl =
      TextEditingController(text: bot.umbralRsiPanico.toStringAsFixed(1));
  final baseWeightsCtrl = TextEditingController(
      text: formatPercentWeights(bot.pesosTramosBase));
  final floorWeightsCtrl = TextEditingController(
      text: formatPercentWeights(bot.pesosTramosSuelo));

  bool saving = false;

  void applyConfigToFields(ConfiguracionEstrategiaBot cfg) {
    selectedConfigId = cfg.id;
    tpCtrl.text = cfg.takeProfitPct.toString();
    tsCtrl.text = cfg.trailingStopPct.toString();
    trendCtrl.text = (cfg.pesoTendencia * 100.0).toStringAsFixed(0);
    rsiT0Ctrl.text = cfg.umbralRsiT0.toStringAsFixed(1);
    rsiPanicCtrl.text = cfg.umbralRsiPanico.toStringAsFixed(1);
    baseWeightsCtrl.text = formatPercentWeights(cfg.pesosTramosBase);
    floorWeightsCtrl.text = formatPercentWeights(cfg.pesosTramosSuelo);
  }

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModalState) {
        final configs =
            provider.configuracionesParaEstrategia(bot.nombreEstrategia);
        if (!configs.any((c) => c.id == selectedConfigId)) {
          selectedConfigId = configs.first.id;
        }

        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppColors.border),
          ),
          title: Row(
            children: [
              const Icon(Icons.tune, color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Parámetros de Estrategia · ${bot.idBot}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Estrategia: ${formatStrategyName(bot.nombreEstrategia)}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon: const Icon(Icons.verified_outlined, size: 14),
                        label: const Text(
                          'Aplicar Configuración Recomendada',
                          style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () {
                          final rec = provider.obtenerConfiguracionRecomendada(
                              bot.nombreEstrategia);
                          setModalState(() {
                            applyConfigToFields(rec);
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: selectedConfigId,
                          isExpanded: true,
                          dropdownColor: AppColors.surface,
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 12),
                          decoration: const InputDecoration(
                            labelText: 'Cargar Configuración Guardada',
                            isDense: true,
                          ),
                          items: configs.map((cfg) {
                            return DropdownMenuItem(
                              value: cfg.id,
                              child: Text(
                                cfg.esRecomendada
                                    ? '★ ${cfg.nombre} (TP ${cfg.takeProfitPct}% · TS ${cfg.trailingStopPct}% · Tendencia ${(cfg.pesoTendencia * 100).toStringAsFixed(0)}%)'
                                    : '${cfg.nombre} (TP ${cfg.takeProfitPct}% · TS ${cfg.trailingStopPct}% · Tendencia ${(cfg.pesoTendencia * 100).toStringAsFixed(0)}%)',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (cfgId) {
                            if (cfgId == null) return;
                            final chosen = configs.firstWhere(
                              (c) => c.id == cfgId,
                              orElse: () => configs.first,
                            );
                            setModalState(() {
                              applyConfigToFields(chosen);
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                          visualDensity: VisualDensity.compact,
                        ),
                        icon:
                            const Icon(Icons.bookmark_add_outlined, size: 15),
                        label: const Text('Guardar como Preset',
                            style: TextStyle(fontSize: 11)),
                        onPressed: () async {
                          final bw = parsePercentWeightsInput(
                              baseWeightsCtrl.text,
                              const [0.30, 0.25, 0.20, 0.15, 0.10]);
                          final fw = parsePercentWeightsInput(
                              floorWeightsCtrl.text,
                              const [0.40, 0.35, 0.25]);
                          final trPct =
                              double.tryParse(trendCtrl.text.trim()) ?? 70.0;
                          await showBotPresetDialog(
                            context,
                            provider,
                            strategyName: bot.nombreEstrategia,
                            takeProfitPct:
                                double.tryParse(tpCtrl.text.trim()) ?? 4.5,
                            trailingStopPct:
                                double.tryParse(tsCtrl.text.trim()) ?? 1.4,
                            trendWeight:
                                trPct > 1.0 ? trPct / 100.0 : trPct,
                            baseWeights: bw,
                            floorWeights: fw,
                            t0Rsi:
                                double.tryParse(rsiT0Ctrl.text.trim()) ??
                                    48.0,
                            panicRsi:
                                double.tryParse(rsiPanicCtrl.text.trim()) ??
                                    28.0,
                            onSavedName: (_) => setModalState(() {}),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: tpCtrl,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 12.5),
                          decoration: const InputDecoration(
                            labelText: 'Take Profit (%)',
                            suffixText: '%',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: tsCtrl,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 12.5),
                          decoration: const InputDecoration(
                            labelText: 'Trailing Stop (%)',
                            suffixText: '%',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: trendCtrl,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 12.5),
                          decoration: const InputDecoration(
                            labelText: 'Peso Tendencia (%)',
                            suffixText: '%',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: rsiT0Ctrl,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 12),
                          decoration: const InputDecoration(
                            labelText: 'Umbral RSI T0',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: rsiPanicCtrl,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 12),
                          decoration: const InputDecoration(
                            labelText: 'Umbral RSI Pánico',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: baseWeightsCtrl,
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 12),
                          decoration: const InputDecoration(
                            labelText: 'Pesos Tramos Base (%)',
                            hintText: '30, 25, 20, 15, 10',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: floorWeightsCtrl,
                          style: const TextStyle(
                              color: AppColors.textPrimary, fontSize: 12),
                          decoration: const InputDecoration(
                            labelText: 'Pesos Suelo (%)',
                            hintText: '40, 35, 25',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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
              label: Text(
                  saving ? 'Aplicando...' : 'Guardar Parámetros en el Bot'),
              onPressed: saving
                  ? null
                  : () async {
                      setModalState(() => saving = true);
                      final bw = parsePercentWeightsInput(
                          baseWeightsCtrl.text,
                          const [0.30, 0.25, 0.20, 0.15, 0.10]);
                      final fw = parsePercentWeightsInput(
                          floorWeightsCtrl.text, const [0.40, 0.35, 0.25]);
                      final rawTrend =
                          double.tryParse(trendCtrl.text.trim()) ?? 70.0;
                      final trendWeight =
                          rawTrend > 1.0 ? rawTrend / 100.0 : rawTrend;

                      final res = await provider.actualizarConfiguracionBot(
                        botId: bot.idBot,
                        takeProfitPct:
                            double.tryParse(tpCtrl.text.trim()) ?? 4.5,
                        trailingStopPct:
                            double.tryParse(tsCtrl.text.trim()) ?? 1.4,
                        trendWeight: trendWeight,
                        baseMaxTranches: bw.length,
                        extraFloorTranches: fw.length,
                        baseTrancheWeights: bw,
                        floorTrancheWeights: fw,
                        t0RsiThreshold:
                            double.tryParse(rsiT0Ctrl.text.trim()) ?? 48.0,
                        panicRsiThreshold:
                            double.tryParse(rsiPanicCtrl.text.trim()) ?? 28.0,
                      );
                      final ok = res['ok'] == true;
                      final msg = (res['message'] ?? '').toString();
                      if (ctx.mounted) {
                        if (ok) {
                          Navigator.pop(ctx);
                        } else {
                          setModalState(() => saving = false);
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
        );
      },
    ),
  );
}
