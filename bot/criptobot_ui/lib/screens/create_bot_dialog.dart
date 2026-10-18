import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class CreateBotDialog extends StatefulWidget {
  const CreateBotDialog({super.key});

  @override
  State<CreateBotDialog> createState() => _CreateBotDialogState();
}

class _CreateBotDialogState extends State<CreateBotDialog> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController(text: 'btc_evolution_pro');
  final _budgetController = TextEditingController(text: '1000.0');
  final _tpController = TextEditingController(text: '4.5');
  final _tsController = TextEditingController(text: '1.4');
  final _subaccountNameController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _apiSecretController = TextEditingController();
  final _apiPassphraseController = TextEditingController();

  String _selectedSymbol = 'BTC/USDT';
  String _selectedStrategy = 'BtcQuantumEvolutionRegimeStrategy';
  bool _dryRun = true;
  bool _submitting = false;

  final List<String> _symbols = ['BTC/USDT', 'ETH/USDT', 'LTC/USDT'];
  final List<Map<String, String>> _strategies = [
    {
      'id': 'BtcQuantumEvolutionRegimeStrategy',
      'label': 'Quantum Evolution (Flagship Champion +4,387%)',
    },
    {
      'id': 'BtcQuantumCompoundRegimeStrategy',
      'label': 'Quantum Apex Compound (5 Tramos Base)',
    },
    {
      'id': 'AdaptiveThreeRegimeStrategy',
      'label': 'Adaptive 3-Regime (General Altcoins)',
    },
  ];

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final subName = _subaccountNameController.text.trim();
    final aKey = _apiKeyController.text.trim();
    final aSecret = _apiSecretController.text.trim();
    final aPass = _apiPassphraseController.text.trim();

    if (!_dryRun && (aKey.isEmpty || aSecret.isEmpty || aPass.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error de Seguridad: Para operar en VIVO es obligatorio ingresar API Key, API Secret y API Passphrase de la subcuenta.'),
          backgroundColor: AppTheme.rojoPerdida,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    final success = await ApiService.crearBot(
      botId: _idController.text.trim(),
      symbol: _selectedSymbol,
      strategyName: _selectedStrategy,
      budget: double.tryParse(_budgetController.text.trim()) ?? 1000.0,
      dryRun: _dryRun,
      takeProfitPct: double.tryParse(_tpController.text.trim()) ?? 4.5,
      trailingStopPct: double.tryParse(_tsController.text.trim()) ?? 1.4,
      maxTranches: _selectedStrategy == 'BtcQuantumEvolutionRegimeStrategy' ? 8 : 5,
      subaccountName: subName.isNotEmpty ? subName : null,
      apiKey: aKey.isNotEmpty ? aKey : null,
      apiSecret: aSecret.isNotEmpty ? aSecret : null,
      apiPassphrase: aPass.isNotEmpty ? aPass : null,
    );

    if (mounted) {
      setState(() => _submitting = false);
      if (success) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bot creado y registrado exitosamente'),
            backgroundColor: AppTheme.verdeSuave,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al crear el bot en el servidor'),
            backgroundColor: AppTheme.rojoPerdida,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.fondoTarjeta,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.bordeTarjeta),
      ),
      title: const Row(
        children: [
          Icon(Icons.smart_toy, color: AppTheme.azulCyan),
          SizedBox(width: 8),
          Text(
            'Desplegar Nuevo Bot',
            style: TextStyle(color: AppTheme.textoPrincipal, fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Bot ID
                const Text('Identificador del Bot (ID único):', style: TextStyle(color: AppTheme.textoSecundario, fontSize: 12)),
                const SizedBox(height: 4),
                TextFormField(
                  controller: _idController,
                  style: const TextStyle(color: AppTheme.textoPrincipal),
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: AppTheme.fondoPrincipal,
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 14),

                // Symbol & Strategy Dropdowns
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Símbolo:', style: TextStyle(color: AppTheme.textoSecundario, fontSize: 12)),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<String>(
                            initialValue: _selectedSymbol,
                            dropdownColor: AppTheme.fondoTarjetaSecundaria,
                            style: const TextStyle(color: AppTheme.textoPrincipal),
                            decoration: const InputDecoration(
                              filled: true,
                              fillColor: AppTheme.fondoPrincipal,
                              border: OutlineInputBorder(),
                            ),
                            items: _symbols.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedSymbol = val);
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Presupuesto USDT:', style: TextStyle(color: AppTheme.textoSecundario, fontSize: 12)),
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: _budgetController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: AppTheme.textoPrincipal),
                            decoration: const InputDecoration(
                              filled: true,
                              fillColor: AppTheme.fondoPrincipal,
                              border: OutlineInputBorder(),
                              prefixText: '\$ ',
                            ),
                            validator: (v) {
                              final num = double.tryParse(v ?? '');
                              return (num == null || num <= 0) ? 'Monto inválido' : null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Strategy
                const Text('Estrategia Cuantitativa:', style: TextStyle(color: AppTheme.textoSecundario, fontSize: 12)),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  initialValue: _selectedStrategy,
                  isExpanded: true,
                  dropdownColor: AppTheme.fondoTarjetaSecundaria,
                  style: const TextStyle(color: AppTheme.textoPrincipal, fontSize: 13),
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: AppTheme.fondoPrincipal,
                    border: OutlineInputBorder(),
                  ),
                  items: _strategies.map((st) {
                    return DropdownMenuItem(
                      value: st['id'],
                      child: Text(st['label']!, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedStrategy = val;
                        if (val == 'BtcQuantumEvolutionRegimeStrategy') {
                          _tpController.text = '4.5';
                          _tsController.text = '1.4';
                        } else {
                          _tpController.text = '5.0';
                          _tsController.text = '2.0';
                        }
                      });
                    }
                  },
                ),
                const SizedBox(height: 14),

                // TP & TS params
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Take Profit %:', style: TextStyle(color: AppTheme.textoSecundario, fontSize: 12)),
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: _tpController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: AppTheme.textoPrincipal),
                            decoration: const InputDecoration(
                              filled: true,
                              fillColor: AppTheme.fondoPrincipal,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Trailing Stop %:', style: TextStyle(color: AppTheme.textoSecundario, fontSize: 12)),
                          const SizedBox(height: 4),
                          TextFormField(
                            controller: _tsController,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(color: AppTheme.textoPrincipal),
                            decoration: const InputDecoration(
                              filled: true,
                              fillColor: AppTheme.fondoPrincipal,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Dry run toggle
                SwitchListTile(
                  title: const Text('Simulación Segura (Dry-Run)', style: TextStyle(color: AppTheme.textoPrincipal, fontSize: 14)),
                  subtitle: const Text('Sin órdenes reales en KuCoin hasta validar', style: TextStyle(color: AppTheme.textoSecundario, fontSize: 11)),
                  value: _dryRun,
                  activeThumbColor: AppTheme.azulCyan,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => _dryRun = v),
                ),
                const SizedBox(height: 10),

                // Subaccount dedicated credentials (optional)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('Subcuenta Dedicada KuCoin (Opcional)', style: TextStyle(color: AppTheme.azulCyan, fontSize: 13, fontWeight: FontWeight.bold)),
                    subtitle: const Text('Asigna una subcuenta para aislar saldo y órdenes', style: TextStyle(color: AppTheme.textoSecundario, fontSize: 11)),
                    children: [
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _subaccountNameController,
                        style: const TextStyle(color: AppTheme.textoPrincipal, fontSize: 12),
                        decoration: const InputDecoration(
                          labelText: 'Nombre de la Subcuenta',
                          hintText: 'ej. Subcuenta-Bot-1',
                          filled: true,
                          fillColor: AppTheme.fondoPrincipal,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _apiKeyController,
                        style: const TextStyle(color: AppTheme.textoPrincipal, fontSize: 12),
                        decoration: const InputDecoration(
                          labelText: 'API Key de la Subcuenta',
                          filled: true,
                          fillColor: AppTheme.fondoPrincipal,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _apiSecretController,
                        obscureText: true,
                        style: const TextStyle(color: AppTheme.textoPrincipal, fontSize: 12),
                        decoration: const InputDecoration(
                          labelText: 'API Secret de la Subcuenta',
                          filled: true,
                          fillColor: AppTheme.fondoPrincipal,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _apiPassphraseController,
                        obscureText: true,
                        style: const TextStyle(color: AppTheme.textoPrincipal, fontSize: 12),
                        decoration: const InputDecoration(
                          labelText: 'API Passphrase de la Subcuenta',
                          filled: true,
                          fillColor: AppTheme.fondoPrincipal,
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: AppTheme.textoSecundario)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.azulCyan),
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Text('Desplegar Bot', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
