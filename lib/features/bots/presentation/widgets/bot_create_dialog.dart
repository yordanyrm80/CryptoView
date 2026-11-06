import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/bot_models.dart';
import '../../providers/bots_provider.dart';
import 'bot_dialog_helpers.dart';
import 'bot_preset_dialog.dart';

Future<void> showBotCreateDialog(
    BuildContext context, BotsProvider provider) async {
  const strategies = [
    {
      'id': 'BtcQuantumEvolutionRegimeStrategy',
      'label': 'Quantum Evolution Regime (Estrategia Ganadora)',
    },
  ];

  const quickSymbols = [
    'BTC/USDT',
    'ETH/USDT',
    'SOL/USDT',
    'LTC/USDT',
  ];

  String selectedStrategy = 'BtcQuantumEvolutionRegimeStrategy';
  final recCfg = provider.obtenerConfiguracionRecomendada(selectedStrategy);
  String selectedConfigId = recCfg.id;

  final formKey = GlobalKey<FormState>();
  final idCtrl = TextEditingController(text: 'btc_quantum_01');
  final symbolCtrl = TextEditingController(text: 'BTC/USDT');
  final budgetCtrl = TextEditingController(text: '1000.0');

  final tpCtrl =
      TextEditingController(text: recCfg.takeProfitPct.toString());
  final tsCtrl =
      TextEditingController(text: recCfg.trailingStopPct.toString());
  final trendCtrl = TextEditingController(
      text: (recCfg.pesoTendencia * 100.0)
          .toStringAsFixed(0));
  final rsiT0Ctrl =
      TextEditingController(text: recCfg.umbralRsiT0.toStringAsFixed(1));
  final rsiPanicCtrl =
      TextEditingController(text: recCfg.umbralRsiPanico.toStringAsFixed(1));
  final baseWeightsCtrl = TextEditingController(
      text: formatPercentWeights(recCfg.pesosTramosBase));
  final floorWeightsCtrl = TextEditingController(
      text: formatPercentWeights(recCfg.pesosTramosSuelo));

  final subNameCtrl = TextEditingController();
  final apiKeyCtrl = TextEditingController();
  final apiSecretCtrl = TextEditingController();
  final apiPassCtrl = TextEditingController();

  bool dryRun = true;
  bool submitting = false;

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
        final availableConfigs =
            provider.configuracionesParaEstrategia(selectedStrategy);
        if (!availableConfigs.any((c) => c.id == selectedConfigId)) {
          selectedConfigId = availableConfigs.first.id;
        }

        return AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppColors.border),
          ),
          title: const Row(
            children: [
              Icon(Icons.smart_toy_outlined,
                  color: AppColors.primary, size: 20),
              SizedBox(width: 10),
              Text(
                'Desplegar Nueva Instancia de Bot',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Identificador, Par y Capital
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: idCtrl,
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 13),
                            decoration: const InputDecoration(
                              labelText: 'Identificador Único (ID)',
                              hintText: 'ej. btc_quantum_01',
                              isDense: true,
                            ),
                            validator: (v) {
                              final clean = (v ?? '').trim();
                              if (clean.length < 3) {
                                return 'Mín. 3 caracteres';
                              }
                              final exists = provider.todosLosBots.any((b) =>
                                  b.idBot.trim().toLowerCase() ==
                                  clean.toLowerCase());
                              if (exists) {
                                return 'ID ya registrado en la flota';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: symbolCtrl,
                            style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.bold),
                            decoration: const InputDecoration(
                              labelText: 'Par de Mercado',
                              hintText: 'BTC/USDT',
                              isDense: true,
                            ),
                            validator: (v) => (v == null || !v.contains('/'))
                                ? 'Formato BASE/USDT'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: budgetCtrl,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                    decimal: true),
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 13),
                            decoration: const InputDecoration(
                              labelText: 'Capital (USDT)',
                              prefixText: r'$ ',
                              isDense: true,
                            ),
                            validator: (v) {
                              final n = double.tryParse(v ?? '');
                              return (n == null || n <= 0)
                                  ? 'Inválido'
                                  : null;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: quickSymbols.map((sym) {
                        final isSelected =
                            symbolCtrl.text.trim().toUpperCase() == sym;
                        return InkWell(
                          onTap: () =>
                              setModalState(() => symbolCtrl.text = sym),
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary.withValues(alpha: 0.2)
                                  : AppColors.background,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSelected
                                  ? AppColors.primary
                                  : AppColors.border,
                              ),
                            ),
                            child: Text(
                              sym,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),

                    // 2. Combo de Estrategia
                    DropdownButtonFormField<String>(
                      initialValue: selectedStrategy,
                      isExpanded: true,
                      dropdownColor: AppColors.surface,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Estrategia Cuantitativa',
                        isDense: true,
                      ),
                      items: strategies
                          .map((st) => DropdownMenuItem(
                                value: st['id'],
                                child: Text(st['label']!,
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setModalState(() {
                            selectedStrategy = val;
                            final rec = provider
                                .obtenerConfiguracionRecomendada(val);
                            applyConfigToFields(rec);
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    // 3. Selector de Configuración Guardada + Botón "Aplicar Configuración Recomendada"
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.tune,
                                      size: 14, color: AppColors.primary),
                                  SizedBox(width: 6),
                                  Text(
                                    'CONFIGURACIÓN DE PARÁMETROS DE LA ESTRATEGIA',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ],
                              ),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.verified_outlined,
                                    size: 14),
                                label: const Text(
                                  'Aplicar Configuración Recomendada',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold),
                                ),
                                onPressed: () {
                                  final rec =
                                      provider.obtenerConfiguracionRecomendada(
                                          selectedStrategy);
                                  setModalState(() {
                                    applyConfigToFields(rec);
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'Configuración Recomendada aplicada (TP 4.5%, TS 1.4%, Tendencia 70%, 8 Tramos).'),
                                      backgroundColor: AppColors.bull,
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: selectedConfigId,
                                  isExpanded: true,
                                  dropdownColor: AppColors.surface,
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12),
                                  decoration: const InputDecoration(
                                    labelText:
                                        'Configuraciones Guardadas (Presets)',
                                    isDense: true,
                                  ),
                                  items: availableConfigs.map((cfg) {
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
                                    final chosen = availableConfigs.firstWhere(
                                      (c) => c.id == cfgId,
                                      orElse: () => availableConfigs.first,
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
                                  side: const BorderSide(
                                      color: AppColors.primary),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 10),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: const Icon(Icons.bookmark_add_outlined,
                                    size: 15),
                                label: const Text('Guardar actual',
                                    style: TextStyle(fontSize: 11)),
                                onPressed: () async {
                                  final bw = parsePercentWeightsInput(
                                      baseWeightsCtrl.text,
                                      const [0.30, 0.25, 0.20, 0.15, 0.10]);
                                  final fw = parsePercentWeightsInput(
                                      floorWeightsCtrl.text,
                                      const [0.40, 0.35, 0.25]);
                                  final trPct = double.tryParse(
                                          trendCtrl.text.trim()) ??
                                      70.0;
                                  await showBotPresetDialog(
                                    context,
                                    provider,
                                    strategyName: selectedStrategy,
                                    takeProfitPct: double.tryParse(
                                            tpCtrl.text.trim()) ??
                                        4.5,
                                    trailingStopPct: double.tryParse(
                                            tsCtrl.text.trim()) ??
                                        1.4,
                                    trendWeight:
                                        trPct > 1.0 ? trPct / 100.0 : trPct,
                                    baseWeights: bw,
                                    floorWeights: fw,
                                    t0Rsi: double.tryParse(
                                            rsiT0Ctrl.text.trim()) ??
                                        48.0,
                                    panicRsi: double.tryParse(
                                            rsiPanicCtrl.text.trim()) ??
                                        28.0,
                                    onSavedName: (_) {
                                      setModalState(() {});
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // Campos editables de los parámetros de la estrategia
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: tpCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12.5),
                                  decoration: const InputDecoration(
                                    labelText: 'Take Profit (%)',
                                    suffixText: '%',
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: tsCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12.5),
                                  decoration: const InputDecoration(
                                    labelText: 'Trailing Stop (%)',
                                    suffixText: '%',
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: trendCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12.5),
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
                                child: TextFormField(
                                  controller: rsiT0Ctrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12),
                                  decoration: const InputDecoration(
                                    labelText: 'Umbral RSI T0',
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: rsiPanicCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12),
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
                                child: TextFormField(
                                  controller: baseWeightsCtrl,
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12),
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
                                child: TextFormField(
                                  controller: floorWeightsCtrl,
                                  style: const TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 12),
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
                    const SizedBox(height: 14),
                    const Text(
                      'AISLAMIENTO DE SUBCUENTA DEDICADA (1 BOT = 1 SUBCUENTA)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: subNameCtrl,
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 12),
                      decoration: InputDecoration(
                        labelText: dryRun
                            ? 'Identificador de Subcuenta (Opcional en Simulación)'
                            : 'Identificador de Subcuenta Exclusiva (Obligatorio)',
                        hintText: 'ej. kucoin_sub_btc_01',
                        prefixIcon: const Icon(Icons.account_tree_outlined,
                            size: 16, color: AppColors.textSecondary),
                        isDense: true,
                      ),
                      validator: (v) {
                        final clean = (v ?? '').trim();
                        if (!dryRun && clean.isEmpty) {
                          return 'Cada bot en vivo requiere su propia subcuenta dedicada';
                        }
                        if (clean.isNotEmpty) {
                          final duplicate = provider.todosLosBots.any((b) =>
                              (b.nombreSubcuenta ?? '').trim().toLowerCase() ==
                              clean.toLowerCase());
                          if (duplicate) {
                            return 'Esta subcuenta ya está asignada a otro bot de la flota';
                          }
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: dryRun ? AppColors.border : AppColors.bull,
                        ),
                      ),
                      child: SwitchListTile(
                        dense: true,
                        title: Text(
                          dryRun
                              ? 'Modo Simulación (Paper Trading)'
                              : 'Ejecución en Vivo (Órdenes Reales en Subcuenta)',
                          style: TextStyle(
                            color: dryRun
                                ? AppColors.textPrimary
                                : AppColors.bull,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        subtitle: Text(
                          dryRun
                              ? 'Evalúa señales en tiempo real sin comprometer saldo en el exchange.'
                              : 'Opera exclusivamente sobre el saldo aislado de la subcuenta.',
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11),
                        ),
                        value: !dryRun,
                        activeThumbColor: AppColors.bull,
                        onChanged: (v) => setModalState(() => dryRun = !v),
                      ),
                    ),
                    if (!dryRun) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: apiKeyCtrl,
                        style: const TextStyle(
                            color: AppColors.textPrimary, fontSize: 12),
                        decoration: const InputDecoration(
                          labelText: 'API Key de la Subcuenta',
                          isDense: true,
                        ),
                        validator: (v) => (!dryRun && (v ?? '').trim().isEmpty)
                            ? 'API Key obligatoria'
                            : null,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: apiSecretCtrl,
                              obscureText: true,
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 12),
                              decoration: const InputDecoration(
                                labelText: 'API Secret',
                                isDense: true,
                              ),
                              validator: (v) =>
                                  (!dryRun && (v ?? '').trim().isEmpty)
                                      ? 'Requerido'
                                      : null,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: apiPassCtrl,
                              obscureText: true,
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontSize: 12),
                              decoration: const InputDecoration(
                                labelText: 'Passphrase',
                                isDense: true,
                              ),
                              validator: (v) =>
                                  (!dryRun && (v ?? '').trim().isEmpty)
                                      ? 'Requerido'
                                      : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: submitting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancelar',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              icon: submitting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.rocket_launch_outlined, size: 16),
              label:
                  Text(submitting ? 'Desplegando...' : 'Desplegar Instancia'),
              onPressed: submitting
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setModalState(() => submitting = true);
                      final bw = parsePercentWeightsInput(
                          baseWeightsCtrl.text,
                          const [0.30, 0.25, 0.20, 0.15, 0.10]);
                      final fw = parsePercentWeightsInput(
                          floorWeightsCtrl.text, const [0.40, 0.35, 0.25]);
                      final rawTrend =
                          double.tryParse(trendCtrl.text.trim()) ?? 70.0;
                      final trendWeight =
                          rawTrend > 1.0 ? rawTrend / 100.0 : rawTrend;

                      final res = await provider.crearBot(
                        botId: idCtrl.text.trim(),
                        symbol: symbolCtrl.text.trim().toUpperCase(),
                        strategyName: selectedStrategy,
                        budget:
                            double.tryParse(budgetCtrl.text.trim()) ?? 1000,
                        dryRun: dryRun,
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
                        subaccountName: subNameCtrl.text.trim().isNotEmpty
                            ? subNameCtrl.text.trim()
                            : null,
                        apiKey: apiKeyCtrl.text.trim().isNotEmpty
                            ? apiKeyCtrl.text.trim()
                            : null,
                        apiSecret: apiSecretCtrl.text.trim().isNotEmpty
                            ? apiSecretCtrl.text.trim()
                            : null,
                        apiPassphrase: apiPassCtrl.text.trim().isNotEmpty
                            ? apiPassCtrl.text.trim()
                            : null,
                      );
                      final ok = res['ok'] == true;
                      final msg = (res['message'] ?? '').toString();
                      if (ctx.mounted) {
                        if (ok) {
                          Navigator.pop(ctx);
                        } else {
                          setModalState(() => submitting = false);
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(msg.isNotEmpty
                                ? msg
                                : (ok
                                    ? 'Instancia creada y registrada correctamente.'
                                    : 'No fue posible registrar el bot.')),
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
