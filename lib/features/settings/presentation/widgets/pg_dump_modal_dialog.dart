import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../providers/settings_provider.dart';

class PgDumpModalDialog extends StatefulWidget {
  final SettingsProvider settingsProvider;

  const PgDumpModalDialog({super.key, required this.settingsProvider});

  @override
  State<PgDumpModalDialog> createState() => _PgDumpModalDialogState();
}

class _PgDumpModalDialogState extends State<PgDumpModalDialog> {
  Timer? _pollingTimer;
  bool _isLoading = true;
  bool _isDownloading = false;
  String? _downloadingFilename;
  double _downloadProgress = 0.0;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  String? _statusError;
  Map<String, dynamic>? _statusData;

  @override
  void initState() {
    super.initState();
    _fetchStatus();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchStatus() async {
    final status = await widget.settingsProvider.checkPgDumpStatus();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _statusData = status;
      if (status.containsKey('error')) {
        _statusError = status['error'].toString();
      } else {
        _statusError = status['last_error'];
      }
    });

    final isRunning = status['is_running'] == true;
    if (isRunning) {
      if (_pollingTimer == null || !_pollingTimer!.isActive) {
        _pollingTimer?.cancel();
        _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
          _fetchStatus();
        });
      }
    } else {
      _pollingTimer?.cancel();
      _pollingTimer = null;
    }
  }

  Future<void> _triggerCreate() async {
    setState(() {
      _isLoading = true;
      _statusError = null;
    });
    final res = await widget.settingsProvider.triggerPgDumpCreation();
    if (!mounted) return;
    if (res.containsKey('error')) {
      setState(() {
        _isLoading = false;
        _statusError = res['error'].toString();
      });
    } else {
      await _fetchStatus();
    }
  }

  Future<void> _downloadFile(String filename) async {
    setState(() {
      _isDownloading = true;
      _downloadingFilename = filename;
      _downloadProgress = 0.0;
      _downloadedBytes = 0;
      _totalBytes = 0;
    });

    final savedPath = await widget.settingsProvider.downloadPgDumpFile(
      filename,
      onProgress: (progress, received, total) {
        if (mounted) {
          setState(() {
            _downloadProgress = progress;
            _downloadedBytes = received;
            _totalBytes = total;
          });
        }
      },
    );

    if (!mounted) return;
    setState(() {
      _isDownloading = false;
      _downloadingFilename = null;
    });

    if (savedPath != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.bull,
          content: Text('¡Descarga completada! Guardado en: $savedPath'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.bear,
          content: Text(widget.settingsProvider.backupMessage ??
              'Error en la descarga del volcado.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = _statusData?['is_running'] == true;
    final elapsedSeconds = _statusData?['elapsed_seconds'] ?? 0;
    final rawDumps = _statusData?['available_dumps'];
    final List<dynamic> dumps = (rawDumps is List) ? rawDumps : [];

    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.candlestick_chart_rounded,
                color: Colors.cyanAccent, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Respaldo Integral con Series de Mercado',
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16),
                ),
                SizedBox(height: 2),
                Text(
                  'Exportación completa comprimida de la base de datos de series temporales',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.textMuted, size: 20),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.border.withValues(alpha: 0.6)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.cyanAccent, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Genera una copia íntegra comprimida (.sql.gz) de la base de datos central en segundo plano. '
                        'Incluye la totalidad de las series históricas de velas, operaciones conciliadas y parámetros del sistema.',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11.5,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_statusError != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.bear.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: AppColors.bear.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.bear, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _statusError!,
                          style: const TextStyle(
                              color: AppColors.bear, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.cyanAccent),
                  ),
                )
              else if (isRunning) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Colors.blueAccent.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.cyanAccent),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Generando volcado en el servidor...',
                            style: TextStyle(
                                color: Colors.cyanAccent,
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5),
                          ),
                          const Spacer(),
                          Text(
                            '${elapsedSeconds}s transcurridos',
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(
                        backgroundColor: AppColors.surface,
                        color: Colors.cyanAccent,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'El respaldo se está procesando de forma asíncrona en el servidor (tiempo estimado: 25 a 40 segundos).',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (_isDownloading) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.bull.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.bull.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.downloading_rounded,
                              color: AppColors.bull, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Descargando: ${_downloadingFilename ?? ''}',
                              style: const TextStyle(
                                  color: AppColors.bull,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${(_downloadProgress * 100).toStringAsFixed(1)}%',
                            style: const TextStyle(
                                color: AppColors.bull,
                                fontWeight: FontWeight.bold,
                                fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _downloadProgress > 0 ? _downloadProgress : null,
                        backgroundColor: AppColors.surface,
                        color: AppColors.bull,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${(_downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB / ${(_totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB recibidos',
                        style: const TextStyle(
                            color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Volcados en el Servidor VPS (${dumps.length}):',
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh,
                        size: 16, color: AppColors.textSecondary),
                    tooltip: 'Refrescar estado',
                    onPressed: _fetchStatus,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (dumps.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.border.withValues(alpha: 0.4)),
                  ),
                  child: const Text(
                    'No hay volcados generados en el servidor todavía. Pulsa el botón inferior para iniciar uno.',
                    style:
                        TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                  ),
                )
              else
                ...dumps.map((d) {
                  final filename = d['filename']?.toString() ?? '';
                  final sizeMb = (d['size_mb'] as num?)?.toDouble() ?? 0.0;
                  final createdAt = d['created_at_utc']?.toString() ?? '';
                  String dateDisplay = createdAt;
                  try {
                    final dt = DateTime.parse(createdAt).toLocal();
                    dateDisplay =
                        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
                  } catch (_) {}

                  final isThisDownloading =
                      _isDownloading && _downloadingFilename == filename;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.file_present_rounded,
                            color: Colors.cyanAccent, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                filename,
                                style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$dateDisplay · ${sizeMb.toStringAsFixed(1)} MB',
                                style: const TextStyle(
                                    color: AppColors.textMuted, fontSize: 10.5),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                Colors.blueAccent.withValues(alpha: 0.2),
                            foregroundColor: Colors.cyanAccent,
                            side: const BorderSide(
                                color: Colors.cyanAccent, width: 0.8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 0),
                            minimumSize: const Size(60, 30),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6)),
                          ),
                          onPressed: (_isDownloading || isRunning)
                              ? null
                              : () => _downloadFile(filename),
                          icon: isThisDownloading
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.cyanAccent),
                                )
                              : const Icon(Icons.cloud_download, size: 14),
                          label: Text(
                            isThisDownloading ? 'Descargando...' : 'Descargar',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            side: const BorderSide(color: AppColors.border),
          ),
          onPressed: () => widget.settingsProvider.openBackupsFolder(),
          icon: const Icon(Icons.folder_open_outlined, size: 14),
          label: const Text('Carpeta Local', style: TextStyle(fontSize: 12)),
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2563EB),
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: (isRunning || _isDownloading) ? null : _triggerCreate,
          icon: isRunning
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.play_arrow_rounded, size: 16),
          label: Text(
            isRunning
                ? 'Generando en VPS...'
                : 'Generar Nuevo Volcado en Servidor',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
