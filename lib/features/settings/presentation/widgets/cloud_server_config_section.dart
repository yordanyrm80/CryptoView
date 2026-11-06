import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/services/cloud_api_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/settings_provider.dart';

class CloudServerConfigSection extends StatefulWidget {
  const CloudServerConfigSection({super.key});

  @override
  State<CloudServerConfigSection> createState() =>
      _CloudServerConfigSectionState();
}

class _CloudServerConfigSectionState extends State<CloudServerConfigSection> {
  late TextEditingController _urlController;
  late TextEditingController _tokenController;
  bool _obscureToken = true;
  bool _isTesting = false;
  Map<String, dynamic>? _testResult;
  String? _testErrorMessage;
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    _urlController = TextEditingController(text: settings.cloudApiUrl);
    _tokenController = TextEditingController(text: settings.cloudApiToken);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isDirty) {
      final settings = Provider.of<SettingsProvider>(context);
      if (_urlController.text != settings.cloudApiUrl) {
        _urlController.text = settings.cloudApiUrl;
      }
      if (_tokenController.text != settings.cloudApiToken) {
        _tokenController.text = settings.cloudApiToken;
      }
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _runHealthTest() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
      _testErrorMessage = null;
    });

    final res = await CloudApiService.instance.checkHealth(
      testUrl: _urlController.text.trim(),
      testToken: _tokenController.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      _isTesting = false;
      if (res['status'] == 'online') {
        _testResult = res;
      } else {
        _testErrorMessage = res['message'] ??
            'Error de respuesta HTTP ${res['http_code'] ?? 'desconocido'}.';
      }
    });
  }

  Future<void> _saveSettings(SettingsProvider settings) async {
    final cleanUrl = _urlController.text.trim().replaceAll(RegExp(r'/+$'), '');
    final cleanToken = _tokenController.text.trim();

    if (cleanUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.bear,
          content: Text('La URL del servidor no puede estar vacía.'),
        ),
      );
      return;
    }

    await settings.saveCloudApiCredentials(cleanUrl, cleanToken);
    setState(() {
      _isDirty = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.bull,
          content: Text('Ajustes del Servidor Cloud guardados correctamente.'),
        ),
      );
    }
  }

  void _restoreDefaults(SettingsProvider settings) {
    setState(() {
      _urlController.text = SettingsProvider.defaultCloudApiUrl;
      _tokenController.text = SettingsProvider.defaultCloudApiToken;
      _isDirty = true;
      _testResult = null;
      _testErrorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.cloud_sync_rounded,
                    color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Servicio de Datos e Historial en Tiempo Real',
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Sincronización continua de series históricas, registro de operaciones y respaldos remotos',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Campo URL del Servidor
          const Text(
            'URL del Servidor Cloud (HTTPS):',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _urlController,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontFamily: 'monospace'),
            onChanged: (_) => setState(() => _isDirty = true),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surface,
              hintText: 'https://129-146-110-196.sslip.io',
              hintStyle:
                  const TextStyle(color: AppColors.textMuted, fontSize: 12),
              prefixIcon: const Icon(Icons.dns_rounded,
                  color: AppColors.primary, size: 18),
              suffixIcon: IconButton(
                icon: const Icon(Icons.restart_alt_rounded,
                    color: AppColors.textMuted, size: 18),
                tooltip: 'Restablecer URL por defecto',
                onPressed: () {
                  setState(() {
                    _urlController.text = SettingsProvider.defaultCloudApiUrl;
                    _isDirty = true;
                  });
                },
              ),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.primary)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 14),

          // Campo Token de Acceso
          const Text(
            'Clave Secreta de Acceso (X-API-Key):',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _tokenController,
            obscureText: _obscureToken,
            style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontFamily: 'monospace'),
            onChanged: (_) => setState(() => _isDirty = true),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surface,
              hintText: 'Token secreto de 256 bits...',
              hintStyle:
                  const TextStyle(color: AppColors.textMuted, fontSize: 12),
              prefixIcon: const Icon(Icons.vpn_key_rounded,
                  color: AppColors.primary, size: 18),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureToken
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.textMuted,
                  size: 18,
                ),
                tooltip: _obscureToken ? 'Mostrar token' : 'Ocultar token',
                onPressed: () =>
                    setState(() => _obscureToken = !_obscureToken),
              ),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.primary)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 16),

          // Botonera de acciones
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isTesting ? null : _runHealthTest,
                icon: _isTesting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.wifi_tethering_rounded, size: 16),
                label: Text(
                  _isTesting ? 'Probando...' : 'Probar Conexión',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.bull,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _saveSettings(settings),
                icon: const Icon(Icons.save_rounded, size: 16),
                label: const Text(
                  'Guardar Ajustes',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.border),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _restoreDefaults(settings),
                icon: const Icon(Icons.restore_rounded, size: 16),
                label: const Text('Restaurar Oficial',
                    style: TextStyle(fontSize: 12)),
              ),
            ],
          ),

          // Caja de Diagnóstico / Estado en Vivo
          if (_testResult != null || _testErrorMessage != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _testResult != null
                    ? AppColors.bull.withValues(alpha: 0.12)
                    : AppColors.bear.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _testResult != null
                      ? AppColors.bull.withValues(alpha: 0.4)
                      : AppColors.bear.withValues(alpha: 0.4),
                ),
              ),
              child: _testResult != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle_rounded,
                                color: AppColors.bull, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              '¡Conexión Exitosa con el Servidor Cloud!',
                              style: TextStyle(
                                  color: AppColors.bull,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.bull.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('ONLINE',
                                  style: TextStyle(
                                      color: AppColors.bull,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '• Base de Datos: ${_testResult!['database'] ?? 'Conectada'}\n'
                          '• Worker 24/7: ${_testResult!['worker_status'] ?? 'online'} (último reporte hace ${_testResult!['worker_last_seen_seconds'] ?? 0}s)\n'
                          '• Monedas Monitoreadas: ${_testResult!['tracked_symbols_active'] ?? 0}\n'
                          '• Velas en TimescaleDB: ${_testResult!['total_candles_stored'] ?? 0}\n'
                          '• Órdenes Almacenadas: ${_testResult!['total_trades_stored'] ?? 0}',
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              height: 1.5),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.error_outline_rounded,
                                color: AppColors.bear, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Error de Conexión',
                              style: TextStyle(
                                  color: AppColors.bear,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'No fue posible comunicarse con el servidor:\n$_testErrorMessage\n\n'
                          'Verifica que la URL empiece por https:// y que el token coincida con el servidor.',
                          style: const TextStyle(
                              color: AppColors.bear, fontSize: 12, height: 1.4),
                        ),
                      ],
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
