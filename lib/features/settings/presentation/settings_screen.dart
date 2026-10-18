import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/settings_provider.dart';
import '../../exchanges/presentation/exchanges_screen.dart';
import '../../tracker/providers/tracker_provider.dart';
import '../../watchlist/providers/watchlist_provider.dart';
import '../../chart/providers/chart_provider.dart';
import '../../../core/services/cloud_api_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
                        activeThumbColor: AppColors.primary,
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

                // 6. Servidor Cloud & Motor de Datos 24/7
                const CloudServerConfigSection(),
                const SizedBox(height: 20),

                // 7. Database Backup & Restore Section
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
              // 1. Salva Ligera de Cuenta & Trades (.json.gz)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.bull,
                  foregroundColor: Colors.black,
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
                                    ? 'Salva de Cuenta & Trades (.json.gz) guardada con éxito en tu PC.'
                                    : (settingsProvider.backupMessage ?? 'Error descargando respaldo de cuenta.'),
                              ),
                            ),
                          );
                        }
                      },
                icon: isBusy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.bolt_rounded, size: 17, color: Colors.black),
                label: const Text(
                  'Salva Cuenta & Trades (.json.gz)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              // 2. Salva Completa con Velas de Mercado (TimescaleDB .sql.gz)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showPgDumpModal(context, settingsProvider),
                icon: const Icon(Icons.candlestick_chart_rounded, size: 17, color: Colors.white),
                label: const Text(
                  'Salva Completa con Velas (.sql.gz)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              // 3. Salva Solo Local SQLite (.db)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
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
                icon: const Icon(Icons.storage_rounded, size: 16, color: Colors.orange),
                label: const Text(
                  'Salva Local (.db)',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              // 4. Abrir Carpeta
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
                'No hay copias de seguridad guardadas en la carpeta de respaldos. Pulsa "Salva Cuenta & Trades" o "Salva Completa" para generar una.',
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
                final isSqlGz = filename.endsWith('.sql.gz');
                final isCloudJson = filename.endsWith('.json.gz') || filename.endsWith('.json');
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

                final badgeColor = isSqlGz
                    ? Colors.cyanAccent
                    : (isCloudJson ? AppColors.bull : Colors.orange);
                final badgeText = isSqlGz
                    ? 'TimescaleDB + Velas'
                    : (isCloudJson ? 'Cuenta & Trades' : 'SQLite Local');
                final itemIcon = isSqlGz
                    ? Icons.candlestick_chart_rounded
                    : (isCloudJson ? Icons.cloud_done_outlined : Icons.storage_rounded);

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSqlGz ? Colors.cyanAccent.withValues(alpha: 0.4) : AppColors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(itemIcon, color: badgeColor, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    filename,
                                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: badgeColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: badgeColor.withValues(alpha: 0.4), width: 0.7),
                                  ),
                                  child: Text(
                                    badgeText,
                                    style: TextStyle(color: badgeColor, fontSize: 9.5, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '$dateFormatted · $sizeStr',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (isSqlGz)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyanAccent.withValues(alpha: 0.15),
                            foregroundColor: Colors.cyanAccent,
                            side: const BorderSide(color: Colors.cyanAccent, width: 0.8),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                            minimumSize: const Size(60, 30),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onPressed: () => _showPgDumpRestoreGuide(context, filename),
                          icon: const Icon(Icons.terminal_rounded, size: 13),
                          label: const Text('Comando VPS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        )
                      else
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

  void _showPgDumpModal(BuildContext context, SettingsProvider settingsProvider) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _PgDumpModalDialog(settingsProvider: settingsProvider),
    );
  }

  void _showPgDumpRestoreGuide(BuildContext context, String filename) {
    final command = 'gunzip -c "$filename" | docker compose exec -T timescaledb psql -U cryptoview -d cryptoview_db';
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
            Icon(Icons.terminal_rounded, color: Colors.cyanAccent, size: 22),
            SizedBox(width: 8),
            Text(
              'Restaurar Volcado Completo',
              style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'El archivo "$filename" es un volcado físico comprimido (.sql.gz) de TimescaleDB con más de 7.5 millones de velas y todas las tablas.',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text(
              'Para restaurar todo el servidor VPS a partir de este volcado, conéctate por SSH a tu servidor y ejecuta en la carpeta del backend:',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
              ),
              child: SelectableText(
                command,
                style: const TextStyle(fontFamily: 'monospace', color: Colors.cyanAccent, fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 14),
            label: const Text('Copiar Comando'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: command));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  backgroundColor: AppColors.bull,
                  content: Text('Comando de restauración copiado al portapapeles.'),
                ),
              );
              Navigator.pop(ctx);
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.surface,
              side: const BorderSide(color: AppColors.border),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar', style: TextStyle(color: AppColors.textPrimary)),
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
              final trackerProvider = Provider.of<TrackerProvider>(context, listen: false);
              final watchlistProvider = Provider.of<WatchlistProvider>(context, listen: false);
              final chartProvider = Provider.of<ChartProvider>(context, listen: false);
              final messenger = ScaffoldMessenger.of(context);
              Navigator.pop(ctx);
              final success = await settingsProvider.restoreBackup(file.path);
              if (success) {
                await trackerProvider.loadData();
                await watchlistProvider.reloadWatchlistState();
                await chartProvider.loadChartData(
                  trackerProvider.activeExchange,
                  trackerProvider.activeSymbol,
                );
                messenger.showSnackBar(
                  const SnackBar(
                    backgroundColor: AppColors.bull,
                    content: Text('¡Base de datos restaurada con éxito! Operaciones, casamientos, gastos y dibujos recargados.'),
                  ),
                );
              } else {
                messenger.showSnackBar(
                  SnackBar(
                    backgroundColor: AppColors.bear,
                    content: Text(settingsProvider.backupMessage ?? 'Error al restaurar.'),
                  ),
                );
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
                    activeThumbColor: currentColor,
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


class CloudServerConfigSection extends StatefulWidget {
  const CloudServerConfigSection({super.key});

  @override
  State<CloudServerConfigSection> createState() => _CloudServerConfigSectionState();
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
        _testErrorMessage = res['message'] ?? 'Error de respuesta HTTP ${res['http_code'] ?? 'desconocido'}.';
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
                child: const Icon(Icons.cloud_sync_rounded, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Servidor Cloud & Motor de Datos 24/7',
                      style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Conexión centralizada con TimescaleDB en Oracle Cloud (velas, órdenes y respaldos)',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
            style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _urlController,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontFamily: 'monospace'),
            onChanged: (_) => setState(() => _isDirty = true),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surface,
              hintText: 'https://129-146-110-196.sslip.io',
              hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              prefixIcon: const Icon(Icons.dns_rounded, color: AppColors.primary, size: 18),
              suffixIcon: IconButton(
                icon: const Icon(Icons.restart_alt_rounded, color: AppColors.textMuted, size: 18),
                tooltip: 'Restablecer URL por defecto',
                onPressed: () {
                  setState(() {
                    _urlController.text = SettingsProvider.defaultCloudApiUrl;
                    _isDirty = true;
                  });
                },
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 14),

          // Campo Token de Acceso
          const Text(
            'Clave Secreta de Acceso (X-API-Key):',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _tokenController,
            obscureText: _obscureToken,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontFamily: 'monospace'),
            onChanged: (_) => setState(() => _isDirty = true),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColors.surface,
              hintText: 'Token secreto de 256 bits...',
              hintStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              prefixIcon: const Icon(Icons.vpn_key_rounded, color: AppColors.primary, size: 18),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureToken ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  color: AppColors.textMuted,
                  size: 18,
                ),
                tooltip: _obscureToken ? 'Mostrar token' : 'Ocultar token',
                onPressed: () => setState(() => _obscureToken = !_obscureToken),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isTesting ? null : _runHealthTest,
                icon: _isTesting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.wifi_tethering_rounded, size: 16),
                label: Text(
                  _isTesting ? 'Probando...' : 'Probar Conexión',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.bull,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _restoreDefaults(settings),
                icon: const Icon(Icons.restore_rounded, size: 16),
                label: const Text('Restaurar Oficial', style: TextStyle(fontSize: 12)),
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
                            const Icon(Icons.check_circle_rounded, color: AppColors.bull, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              '¡Conexión Exitosa con el Servidor Cloud!',
                              style: TextStyle(color: AppColors.bull, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.bull.withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('ONLINE', style: TextStyle(color: AppColors.bull, fontSize: 10, fontWeight: FontWeight.bold)),
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
                          style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, height: 1.5),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.error_outline_rounded, color: AppColors.bear, size: 18),
                            SizedBox(width: 8),
                            Text(
                              'Error de Conexión',
                              style: TextStyle(color: AppColors.bear, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'No fue posible comunicarse con el servidor:\n$_testErrorMessage\n\n'
                          'Verifica que la URL empiece por https:// y que el token coincida con el servidor.',
                          style: const TextStyle(color: AppColors.bear, fontSize: 12, height: 1.4),
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

class _PgDumpModalDialog extends StatefulWidget {
  final SettingsProvider settingsProvider;

  const _PgDumpModalDialog({required this.settingsProvider});

  @override
  State<_PgDumpModalDialog> createState() => _PgDumpModalDialogState();
}

class _PgDumpModalDialogState extends State<_PgDumpModalDialog> {
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
          content: Text(widget.settingsProvider.backupMessage ?? 'Error en la descarga del volcado.'),
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
            child: const Icon(Icons.candlestick_chart_rounded, color: Colors.cyanAccent, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Salva Completa con Velas',
                  style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                SizedBox(height: 2),
                Text(
                  'TimescaleDB pg_dump nativo (7.5M+ velas)',
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
                  border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.cyanAccent, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Genera un volcado físico comprimido (.sql.gz) de PostgreSQL/TimescaleDB directamente en el VPS. '
                        'No satura la memoria RAM de Python y captura los más de 7.5 millones de velas y todas las configuraciones.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5, height: 1.4),
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
                    border: Border.all(color: AppColors.bear.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.bear, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _statusError!,
                          style: const TextStyle(color: AppColors.bear, fontSize: 11.5),
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
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                  ),
                )
              else if (isRunning) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blueAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Generando volcado en el servidor...',
                            style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12.5),
                          ),
                          const Spacer(),
                          Text(
                            '${elapsedSeconds}s transcurridos',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
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
                        'pg_dump se está ejecutando asíncronamente en el VPS. Toma ~25 a 40 segundos.',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
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
                    border: Border.all(color: AppColors.bull.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.downloading_rounded, color: AppColors.bull, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Descargando: ${_downloadingFilename ?? ''}',
                              style: const TextStyle(color: AppColors.bull, fontWeight: FontWeight.bold, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${(_downloadProgress * 100).toStringAsFixed(1)}%',
                            style: const TextStyle(color: AppColors.bull, fontWeight: FontWeight.bold, fontSize: 12),
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
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
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
                    style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 16, color: AppColors.textSecondary),
                    tooltip: 'Refrescar estado',
                    onPressed: _fetchStatus,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
                    border: Border.all(color: AppColors.border.withValues(alpha: 0.4)),
                  ),
                  child: const Text(
                    'No hay volcados generados en el servidor todavía. Pulsa el botón inferior para iniciar uno.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
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

                  final isThisDownloading = _isDownloading && _downloadingFilename == filename;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.file_present_rounded, color: Colors.cyanAccent, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                filename,
                                style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5),
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$dateDisplay · ${sizeMb.toStringAsFixed(1)} MB',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent.withValues(alpha: 0.2),
                            foregroundColor: Colors.cyanAccent,
                            side: const BorderSide(color: Colors.cyanAccent, width: 0.8),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                            minimumSize: const Size(60, 30),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          onPressed: (_isDownloading || isRunning) ? null : () => _downloadFile(filename),
                          icon: isThisDownloading
                              ? const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                                )
                              : const Icon(Icons.cloud_download, size: 14),
                          label: Text(
                            isThisDownloading ? 'Bajando...' : 'Descargar',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: (isRunning || _isDownloading) ? null : _triggerCreate,
          icon: isRunning
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.play_arrow_rounded, size: 16),
          label: Text(
            isRunning ? 'Generando en VPS...' : 'Generar Nuevo Volcado en Servidor',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
