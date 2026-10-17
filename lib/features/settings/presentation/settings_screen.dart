import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/settings_provider.dart';
import '../../exchanges/presentation/exchanges_screen.dart';
import '../../tracker/providers/tracker_provider.dart';
import '../../watchlist/providers/watchlist_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  static const List<Map<String, dynamic>> buyColorPalette = [
    {'name': 'Verde Neón', 'hex': '#00E676', 'color': Color(0xFF00E676)},
    {'name': 'Esmeralda', 'hex': '#10B981', 'color': Color(0xFF10B981)},
    {'name': 'Lima', 'hex': '#76FF03', 'color': Color(0xFF76FF03)},
    {'name': 'Menta', 'hex': '#00BFA5', 'color': Color(0xFF00BFA5)},
    {'name': 'Cyan', 'hex': '#00E5FF', 'color': Color(0xFF00E5FF)},
    {'name': 'Amarillo', 'hex': '#FFD700', 'color': Color(0xFFFFD700)},
    {'name': 'Blanco', 'hex': '#FFFFFF', 'color': Color(0xFFFFFFFF)},
  ];

  static const List<Map<String, dynamic>> sellColorPalette = [
    {'name': 'Rojo Brillante', 'hex': '#FF5252', 'color': Color(0xFFFF5252)},
    {'name': 'Carmesí', 'hex': '#E53935', 'color': Color(0xFFE53935)},
    {'name': 'Rubí', 'hex': '#FF1744', 'color': Color(0xFFFF1744)},
    {'name': 'Naranja Neón', 'hex': '#FF6D00', 'color': Color(0xFFFF6D00)},
    {'name': 'Coral', 'hex': '#FF5722', 'color': Color(0xFFFF5722)},
    {'name': 'Rosa Neón', 'hex': '#FF4081', 'color': Color(0xFFFF4081)},
    {'name': 'Púrpura', 'hex': '#E040FB', 'color': Color(0xFFE040FB)},
  ];

  static const List<Map<String, dynamic>> priceColorPalette = [
    {'name': 'Cyan Eléctrico', 'hex': '#00E5FF', 'color': Color(0xFF00E5FF)},
    {'name': 'Amarillo Oro', 'hex': '#FFD700', 'color': Color(0xFFFFD700)},
    {'name': 'Naranja', 'hex': '#FF9100', 'color': Color(0xFFFF9100)},
    {'name': 'Verde Neón', 'hex': '#00E676', 'color': Color(0xFF00E676)},
    {'name': 'Blanco', 'hex': '#FFFFFF', 'color': Color(0xFFFFFFFF)},
    {'name': 'Lavanda', 'hex': '#EA80FC', 'color': Color(0xFFEA80FC)},
  ];

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<SettingsProvider>(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.settings, color: AppColors.primary, size: 20),
            SizedBox(width: 8),
            Text(
              'Configuración General',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
            icon: const Icon(Icons.restore, size: 16),
            label: const Text('Valores por defecto', style: TextStyle(fontSize: 12)),
            onPressed: () async {
              await settingsProvider.resetToDefaults();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: AppColors.primary,
                    content: Text('Colores y configuraciones restaurados a valores iniciales.'),
                  ),
                );
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Live Preview Card
                _buildLivePreviewCard(settingsProvider),
                const SizedBox(height: 20),

                // 2. Buy Lines Color Section
                _buildColorSection(
                  context: context,
                  title: 'Líneas de Compras en el Gráfico',
                  subtitle: 'Color utilizado para destacar tus compras abiertas e históricas',
                  icon: Icons.shopping_cart,
                  currentColorHex: settingsProvider.buyLineColorHex,
                  currentColor: settingsProvider.buyLineColor,
                  palette: buyColorPalette,
                  isVisible: settingsProvider.showBuyLines,
                  onVisibilityChanged: (val) => settingsProvider.setShowBuyLines(val),
                  onColorSelected: (hex) => settingsProvider.setBuyLineColor(hex),
                ),
                const SizedBox(height: 16),

                // 3. Sell Lines Color Section
                _buildColorSection(
                  context: context,
                  title: 'Líneas de Ventas en el Gráfico',
                  subtitle: 'Color utilizado para destacar órdenes de venta y cierres',
                  icon: Icons.sell,
                  currentColorHex: settingsProvider.sellLineColorHex,
                  currentColor: settingsProvider.sellLineColor,
                  palette: sellColorPalette,
                  isVisible: settingsProvider.showSellLines,
                  onVisibilityChanged: (val) => settingsProvider.setShowSellLines(val),
                  onColorSelected: (hex) => settingsProvider.setSellLineColor(hex),
                ),
                const SizedBox(height: 16),

                // 4. Current Price Line Section
                _buildColorSection(
                  context: context,
                  title: 'Línea de Precio Actual en el Gráfico',
                  subtitle: 'Línea horizontal en vivo que sigue el precio de mercado actual',
                  icon: Icons.timeline,
                  currentColorHex: settingsProvider.currentPriceColorHex,
                  currentColor: settingsProvider.currentPriceColor,
                  palette: priceColorPalette,
                  isVisible: settingsProvider.showCurrentPriceLine,
                  onVisibilityChanged: (val) => settingsProvider.setShowCurrentPriceLine(val),
                  onColorSelected: (hex) => settingsProvider.setCurrentPriceColor(hex),
                ),
                const SizedBox(height: 16),

                // 5. User Drawings Visibility
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.edit_road, color: AppColors.primary, size: 20),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Mis Líneas Guardadas (Trazos Manuales)',
                              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Muestra u oculta todas tus líneas horizontales y mediciones en el gráfico',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: settingsProvider.showDrawings,
                        activeColor: AppColors.primary,
                        onChanged: (val) => settingsProvider.setShowDrawings(val),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 5. Quick Link to Exchanges
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.currency_exchange, color: AppColors.primary, size: 24),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Gestión de Exchanges & API Keys',
                              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Configura claves de KuCoin, Binance, BingX y montos de compra manuales',
                              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.surface,
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.arrow_forward, size: 14),
                        label: const Text('Abrir', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ExchangesScreen()),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // 6. Database Backup & Restore Section
                _buildBackupSection(context, settingsProvider),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackupSection(BuildContext context, SettingsProvider settingsProvider) {
    final backups = settingsProvider.backupFiles;
    final isBusy = settingsProvider.isBackupBusy;
    final daysSince = settingsProvider.daysSinceLastBackup;
    final isOverdue = settingsProvider.isBackupOverdue;

    String statusLabel;
    if (daysSince == null) {
      statusLabel = 'Aún no has descargado ninguna salva mensual';
    } else if (daysSince == 0) {
      statusLabel = 'Última salva realizada: Hoy';
    } else if (daysSince == 1) {
      statusLabel = 'Última salva realizada: Hace 1 día';
    } else {
      statusLabel = 'Última salva realizada: Hace $daysSince días';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOverdue ? Colors.amber.withValues(alpha: 0.7) : AppColors.border,
          width: isOverdue ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.storage_rounded, color: Colors.blueAccent, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Copias de Seguridad (Local & Servidor Cloud)',
                      style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Guarda y restaura salvas manuales de tu base de datos local y del servidor de Oracle Cloud',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Banner de estado / recordatorio mensual (30 días)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isOverdue
                  ? Colors.amber.withValues(alpha: 0.12)
                  : AppColors.bull.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isOverdue
                    ? Colors.amber.withValues(alpha: 0.5)
                    : AppColors.bull.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isOverdue ? Icons.warning_amber_rounded : Icons.verified_user_rounded,
                  color: isOverdue ? Colors.amber : AppColors.bull,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isOverdue
                        ? '$statusLabel · Recomendado hacer una salva mensual.'
                        : '$statusLabel · Respaldo al día (ciclo de 30 días).',
                    style: TextStyle(
                      color: isOverdue ? Colors.amber : AppColors.bull,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: isBusy
                    ? null
                    : () async {
                        final path = await settingsProvider.createBackup();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: path != null ? AppColors.bull : AppColors.bear,
                              content: Text(
                                path != null
                                    ? 'Copia de seguridad local (.db) guardada con éxito.'
                                    : (settingsProvider.backupMessage ?? 'Error al crear salva.'),
                              ),
                            ),
                          );
                        }
                      },
                icon: isBusy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded, size: 16),
                label: Text(
                  isBusy ? 'Procesando...' : 'Crear Salva Local (.db)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: isBusy
                    ? null
                    : () async {
                        final path = await settingsProvider.downloadCloudBackup(includeCandles: false);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: path != null ? AppColors.bull : AppColors.bear,
                              content: Text(
                                path != null
                                    ? 'Respaldo del Servidor Cloud (.json.gz) descargado a tu PC.'
                                    : (settingsProvider.backupMessage ?? 'Error descargando respaldo cloud.'),
                              ),
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.cloud_download_rounded, size: 16),
                label: const Text(
                  'Descargar Salva Servidor Cloud',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => settingsProvider.openBackupsFolder(),
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: const Text('Abrir Carpeta', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 12),
          Text(
            'Salvas Disponibles (${backups.length}):',
            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          if (backups.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
              ),
              child: const Text(
                'No hay copias de seguridad guardadas en la carpeta de respaldos. Pulsa "Crear Salva" para generar una.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: backups.length,
              itemBuilder: (ctx, index) {
                final file = backups[index];
                final filename = file.path.split(Platform.pathSeparator).last;
                final isCloud = filename.endsWith('.json.gz') || filename.endsWith('.json');
                DateTime? modDate;
                int sizeBytes = 0;
                try {
                  modDate = file.lastModifiedSync();
                  sizeBytes = file.lengthSync();
                } catch (_) {}

                final sizeStr = sizeBytes < 1024 * 1024
                    ? '${(sizeBytes / 1024).toStringAsFixed(1)} KB'
                    : '${(sizeBytes / (1024 * 1024)).toStringAsFixed(2)} MB';

                final dateFormatted = modDate != null
                    ? '${modDate.day.toString().padLeft(2, '0')}/${modDate.month.toString().padLeft(2, '0')}/${modDate.year} ${modDate.hour.toString().padLeft(2, '0')}:${modDate.minute.toString().padLeft(2, '0')}:${modDate.second.toString().padLeft(2, '0')}'
                    : '';

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isCloud ? Icons.cloud_done_outlined : Icons.archive_outlined,
                        color: isCloud ? Colors.cyanAccent : Colors.blueAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              filename,
                              style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$dateFormatted · $sizeStr',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.withValues(alpha: 0.15),
                          foregroundColor: Colors.orange,
                          side: const BorderSide(color: Colors.orange, width: 0.8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          minimumSize: const Size(60, 30),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onPressed: isBusy ? null : () => _confirmRestore(context, file, filename, dateFormatted, settingsProvider),
                        icon: const Icon(Icons.restore, size: 13),
                        label: const Text('Restaurar', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppColors.textMuted, size: 18),
                        tooltip: 'Eliminar salva',
                        onPressed: isBusy ? null : () => _confirmDeleteBackup(context, file, filename, settingsProvider),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _confirmRestore(
    BuildContext context,
    File file,
    String filename,
    String dateStr,
    SettingsProvider settingsProvider,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
            SizedBox(width: 8),
            Text('Restaurar Salva', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '¿Deseas restaurar la base de datos a este punto de respaldo?',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Archivo: $filename', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('Fecha de salva: $dateStr', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Nota de seguridad: Antes de restaurar se creará automáticamente una copia preventiva del estado actual.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final success = await settingsProvider.restoreBackup(file.path);
              if (context.mounted) {
                if (success) {
                  await Provider.of<TrackerProvider>(context, listen: false).loadData();
                  await Provider.of<WatchlistProvider>(context, listen: false).reloadWatchlistState();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      backgroundColor: AppColors.bull,
                      content: Text('¡Base de datos restaurada con éxito! Todos los datos fueron recargados.'),
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppColors.bear,
                      content: Text(settingsProvider.backupMessage ?? 'Error al restaurar.'),
                    ),
                  );
                }
              }
            },
            child: const Text('Sí, Restaurar', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteBackup(
    BuildContext context,
    File file,
    String filename,
    SettingsProvider settingsProvider,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text('Eliminar Salva', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text('¿Deseas eliminar permanentemente el archivo $filename?', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.bear,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await settingsProvider.deleteBackup(file.path);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: AppColors.surface,
                    content: Text('Archivo de respaldo eliminado.'),
                  ),
                );
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  Widget _buildLivePreviewCard(SettingsProvider settingsProvider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0E11),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.remove_red_eye, color: AppColors.primary, size: 16),
                  SizedBox(width: 6),
                  Text('Vista Previa de Líneas en el Gráfico', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
              Text('ETH/USDT', style: TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 14),

          // Preview Line: Sell
          if (settingsProvider.showSellLines)
            _buildSampleLine(
              label: 'VENTA: \$2,258.65 (0.1963 ETH)',
              color: settingsProvider.sellLineColor,
            ),
          if (settingsProvider.showSellLines) const SizedBox(height: 10),

          // Preview Line: Current Price
          if (settingsProvider.showCurrentPriceLine)
            _buildSampleLine(
              label: 'PRECIO ACTUAL: \$2,036.28',
              color: settingsProvider.currentPriceColor,
            ),
          if (settingsProvider.showCurrentPriceLine) const SizedBox(height: 10),

          // Preview Line: Buy
          if (settingsProvider.showBuyLines)
            _buildSampleLine(
              label: 'COMPRA: \$1,633.55 (0.2448 ETH)',
              color: settingsProvider.buyLineColor,
            ),
        ],
      ),
    );
  }

  Widget _buildSampleLine({required String label, required Color color}) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color, width: 0.8),
          ),
          child: Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: CustomPaint(
            painter: _DashedLinePainter(color: color),
            size: const Size(double.infinity, 2),
          ),
        ),
      ],
    );
  }

  Widget _buildColorSection({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required String currentColorHex,
    required Color currentColor,
    required List<Map<String, dynamic>> palette,
    required bool isVisible,
    required ValueChanged<bool> onVisibilityChanged,
    required ValueChanged<String> onColorSelected,
  }) {
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, color: currentColor, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    isVisible ? 'Visible' : 'Oculto',
                    style: TextStyle(
                      color: isVisible ? AppColors.bull : AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Switch(
                    value: isVisible,
                    activeColor: currentColor,
                    onChanged: onVisibilityChanged,
                  ),
                ],
              ),
            ],
          ),
          Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 12),

          // Palette chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: palette.map((item) {
              final String hex = item['hex'] as String;
              final Color col = item['color'] as Color;
              final String name = item['name'] as String;
              final bool isSelected = currentColorHex.toUpperCase() == hex.toUpperCase();

              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onColorSelected(hex),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? col.withValues(alpha: 0.25) : AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? col : AppColors.border,
                      width: isSelected ? 1.8 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: col,
                          shape: BoxShape.circle,
                          boxShadow: [
                            if (isSelected)
                              BoxShadow(color: col.withValues(alpha: 0.6), blurRadius: 6, spreadRadius: 1),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        name,
                        style: TextStyle(
                          color: isSelected ? Colors.white : AppColors.textSecondary,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;

    const dashWidth = 5.0;
    const dashSpace = 4.0;
    double startX = 0;

    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, size.height / 2),
        Offset(startX + dashWidth, size.height / 2),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) => oldDelegate.color != color;
}
