import 'dart:async';
import 'package:flutter/material.dart';
import '../services/cloud_api_service.dart';
import '../theme/app_colors.dart';

class CloudEngineStatusPill extends StatefulWidget {
  const CloudEngineStatusPill({super.key});

  @override
  State<CloudEngineStatusPill> createState() => _CloudEngineStatusPillState();
}

class _CloudEngineStatusPillState extends State<CloudEngineStatusPill> {
  Timer? _pollTimer;
  bool _isLoading = false;
  bool _isOnline = false;
  String _workerStatus = 'checking';
  int _candlesCount = 0;
  int _symbolsCount = 0;
  int _tradesCount = 0;
  double? _workerLastSeenSeconds;
  String? _errorMessage;
  DateTime? _lastCheckedAt;

  @override
  void initState() {
    super.initState();
    _checkHealth();
    _pollTimer = Timer.periodic(const Duration(seconds: 35), (_) {
      _checkHealth();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkHealth() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final res = await CloudApiService.instance.checkHealth();
      if (!mounted) return;

      if (res['http_code'] == 200 && res['status'] == 'online') {
        setState(() {
          _isOnline = true;
          _workerStatus = res['worker_status'] ?? 'unknown';
          _candlesCount = (res['total_candles_stored'] as num?)?.toInt() ?? 0;
          _symbolsCount = (res['tracked_symbols_active'] as num?)?.toInt() ?? 0;
          _tradesCount = (res['total_trades_stored'] as num?)?.toInt() ?? 0;
          _workerLastSeenSeconds =
              (res['worker_last_seen_seconds'] as num?)?.toDouble();
          _errorMessage = null;
          _lastCheckedAt = DateTime.now();
          _isLoading = false;
        });
      } else {
        setState(() {
          _isOnline = false;
          _workerStatus = 'offline';
          _errorMessage = res['message']?.toString() ??
              'Sin comunicación con el servicio de datos';
          _lastCheckedAt = DateTime.now();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isOnline = false;
        _workerStatus = 'offline';
        _errorMessage = e.toString();
        _lastCheckedAt = DateTime.now();
        _isLoading = false;
      });
    }
  }

  String _formatK(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(0)}k';
    }
    return count.toString();
  }

  String _formatCommas(int number) {
    final str = number.toString();
    final reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    return str.replaceAllMapped(reg, (Match m) => '${m[1]},');
  }

  Color _getStatusColor() {
    if (_workerStatus == 'checking') return AppColors.textMuted;
    if (!_isOnline) return AppColors.bear;
    if (_workerStatus == 'online') return AppColors.bull;
    if (_workerStatus == 'stalled') return Colors.amber;
    return AppColors.bear;
  }

  String _getStatusText() {
    if (_workerStatus == 'checking') return 'Sincronizando...';
    if (!_isOnline) return 'Datos: Modo Local';
    if (_workerStatus == 'online') {
      return _candlesCount > 0
          ? 'Datos en Línea (${_formatK(_candlesCount)})'
          : 'Datos en Línea';
    }
    if (_workerStatus == 'stalled') return 'Ingesta en Espera';
    return 'Ingesta Pausada';
  }

  void _showDiagnosticDialog() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final statusColor = _getStatusColor();
            final url = CloudApiService.instance.baseUrl;

            return AlertDialog(
              backgroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                    color: statusColor.withValues(alpha: 0.4), width: 1.5),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.cloud_done_outlined,
                        color: statusColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Estado del Servicio de Datos',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Sincronización de series históricas y registro operativo',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close,
                        color: AppColors.textSecondary, size: 20),
                    onPressed: () => Navigator.pop(dialogCtx),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: statusColor.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: statusColor,
                                boxShadow: [
                                  BoxShadow(
                                    color: statusColor.withValues(alpha: 0.6),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _isOnline
                                    ? (_workerStatus == 'online'
                                        ? 'Servicio de Datos y Sincronización Activos'
                                        : 'Servidor Conectado • Sincronización en Espera')
                                    : 'Sin Conexión con el Servidor Central',
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (_isLoading)
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.primary),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildMetricRow(
                        icon: Icons.link,
                        label: 'Punto de Acceso',
                        value: url,
                        valueColor: AppColors.primary,
                      ),
                      const Divider(color: AppColors.border, height: 16),
                      _buildMetricRow(
                        icon: Icons.storage,
                        label: 'Motor de Series Temporales',
                        value: _isOnline ? 'Activo (En línea)' : 'Desconectado',
                        valueColor:
                            _isOnline ? AppColors.bull : AppColors.bear,
                      ),
                      const Divider(color: AppColors.border, height: 16),
                      _buildMetricRow(
                        icon: Icons.candlestick_chart,
                        label: 'Registros Históricos de Mercado',
                        value: _isOnline
                            ? '${_formatCommas(_candlesCount)} velas'
                            : '0',
                        valueColor: AppColors.bull,
                      ),
                      const Divider(color: AppColors.border, height: 16),
                      _buildMetricRow(
                        icon: Icons.show_chart,
                        label: 'Mercados en Seguimiento Continuo',
                        value:
                            _isOnline ? '$_symbolsCount pares activos' : '0',
                        valueColor: AppColors.textPrimary,
                      ),
                      const Divider(color: AppColors.border, height: 16),
                      _buildMetricRow(
                        icon: Icons.receipt_long,
                        label: 'Operaciones Respaldadas',
                        value: _isOnline
                            ? '$_tradesCount transacciones'
                            : '0',
                        valueColor: AppColors.textPrimary,
                      ),
                      const Divider(color: AppColors.border, height: 16),
                      _buildMetricRow(
                        icon: Icons.sync,
                        label: 'Frecuencia de Actualización',
                        value: _workerLastSeenSeconds != null
                            ? 'hace ${_workerLastSeenSeconds!.toStringAsFixed(1)}s'
                            : (_isOnline ? 'Sincronizado' : 'No disponible'),
                        valueColor: _workerStatus == 'online'
                            ? AppColors.bull
                            : Colors.amber,
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.bear.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.bear.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  color: AppColors.bear, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                      color: AppColors.bear, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (_lastCheckedAt != null) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Última verificación: ${_lastCheckedAt!.hour.toString().padLeft(2, '0')}:${_lastCheckedAt!.minute.toString().padLeft(2, '0')}:${_lastCheckedAt!.second.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 10),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Actualizar Estado'),
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.primary),
                  onPressed: () async {
                    await _checkHealth();
                    setDialogState(() {});
                  },
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.card,
                    foregroundColor: AppColors.textPrimary,
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cerrar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMetricRow({
    required IconData icon,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style:
                const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
        Text(
          value,
          style: TextStyle(
              color: valueColor, fontWeight: FontWeight.bold, fontSize: 12),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _getStatusColor();
    final statusText = _getStatusText();

    return Tooltip(
      message: 'Estado del servicio de datos e historial (clic para ver detalles)',
      waitDuration: const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _showDiagnosticDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: statusColor.withValues(alpha: 0.35), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor,
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.8),
                        blurRadius: 5,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
