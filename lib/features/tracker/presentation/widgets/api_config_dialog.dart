import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/tracker_provider.dart';

class ApiConfigDialog extends StatefulWidget {
  final TrackerProvider trackerProvider;
  final String defaultExchange;

  const ApiConfigDialog({
    Key? key,
    required this.trackerProvider,
    required this.defaultExchange,
  }) : super(key: key);

  @override
  _ApiConfigDialogState createState() => _ApiConfigDialogState();
}

class _ApiConfigDialogState extends State<ApiConfigDialog> {
  late String _selectedExchange;
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _secretController = TextEditingController();
  final TextEditingController _passphraseController = TextEditingController();
  bool _hasKeys = false;

  @override
  void initState() {
    super.initState();
    _selectedExchange = widget.defaultExchange;
    _loadCredentials(_selectedExchange);
  }

  @override
  void dispose() {
    _keyController.dispose();
    _secretController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  void _loadCredentials(String ex) {
    _keyController.clear();
    _secretController.clear();
    _passphraseController.clear();
    _hasKeys = false;

    widget.trackerProvider.getCredentials(ex).then((creds) {
      if (creds != null && mounted) {
        setState(() {
          _keyController.text = creds['api_key'] ?? '';
          _secretController.text = creds['api_secret'] ?? '';
          _passphraseController.text = creds['api_passphrase'] ?? '';
          _hasKeys = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isKucoin = _selectedExchange.toLowerCase() == 'kucoin';

    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      title: const Text('Configuración API Exchanges', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              dropdownColor: AppColors.surface,
              value: _selectedExchange,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Selecciona Exchange',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
              ),
              items: const ['Binance', 'KuCoin', 'BingX'].map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() => _selectedExchange = val);
                  _loadCredentials(val);
                }
              },
            ),
            const SizedBox(height: 12),
            const Text(
              'Ingresa tus credenciales de solo lectura (permiso "General") para poder importar tu historial.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _keyController,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'API Key',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _secretController,
              obscureText: true,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'API Secret',
                labelStyle: TextStyle(color: AppColors.textSecondary),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
              ),
            ),
            if (isKucoin) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _passphraseController,
                obscureText: true,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'API Passphrase',
                  labelStyle: TextStyle(color: AppColors.textSecondary),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.border)),
                ),
              ),
            ],
            if (_hasKeys) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.bull.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: AppColors.bull, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Credenciales de $_selectedExchange configuradas.', style: const TextStyle(color: AppColors.bull, fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_hasKeys)
          TextButton(
            onPressed: () async {
              await widget.trackerProvider.deleteCredentials(_selectedExchange);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Credenciales de $_selectedExchange eliminadas.')));
            },
            child: const Text('Eliminar', style: TextStyle(color: AppColors.bear)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.background,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () async {
            final key = _keyController.text.trim();
            final secret = _secretController.text.trim();
            final pass = _passphraseController.text.trim();

            if (key.isEmpty || secret.isEmpty || (isKucoin && pass.isEmpty)) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Todos los campos son obligatorios.')));
              return;
            }

            await widget.trackerProvider.saveCredentials(
              _selectedExchange,
              key,
              secret,
              passphrase: isKucoin ? pass : null,
            );
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(backgroundColor: AppColors.bull, content: Text('¡Credenciales de $_selectedExchange guardadas con éxito!')),
            );
          },
          child: const Text('Guardar'),
        )
      ],
    );
  }
}
