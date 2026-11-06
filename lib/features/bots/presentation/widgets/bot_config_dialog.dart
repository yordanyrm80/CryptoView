import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/bot_models.dart';
import '../../providers/bots_provider.dart';

Future<void> showBotConfigDialog(
    BuildContext context, BotsProvider provider) async {
  final webhookCtrl = TextEditingController(
      text: provider.ajustes?.discordWebhookUrl ?? '');
  bool notifyBuys = provider.ajustes?.notificarCompras ?? true;
  bool notifySells = provider.ajustes?.notificarVentas ?? true;
  bool notifyPlateau = provider.ajustes?.notificarAlertasMeseta ?? true;

  // Intentar refrescar ajustes actuales en segundo plano
  provider.obtenerAjustesSistema().then((ajustes) {
    if (ajustes != null && webhookCtrl.text.isEmpty) {
      webhookCtrl.text = ajustes.discordWebhookUrl;
    }
  });

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModalState) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.notifications_active_outlined,
                color: AppColors.primary, size: 20),
            SizedBox(width: 10),
            Text(
              'Notificaciones Operativas de la Flota',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.cloud_done_outlined,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sincronizado a través de la API Central: ${provider.baseUrl}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'CANAL DE ALERTAS (WEBHOOK)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: webhookCtrl,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'URL de Webhook (Discord / Canal de Alertas)',
                    hintText: 'https://discord.com/api/webhooks/...',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  activeThumbColor: AppColors.primary,
                  title: const Text('Notificar aperturas de tramo (Compras)',
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 13)),
                  value: notifyBuys,
                  onChanged: (v) => setModalState(() => notifyBuys = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  activeThumbColor: AppColors.bull,
                  title: const Text('Notificar cierres con beneficio (Ventas)',
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 13)),
                  value: notifySells,
                  onChanged: (v) => setModalState(() => notifySells = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  activeThumbColor: Colors.amber,
                  title: const Text(
                      'Alertas de gestión de liquidez y exposición',
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 13)),
                  value: notifyPlateau,
                  onChanged: (v) => setModalState(() => notifyPlateau = v),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await provider.guardarAjustesSistema(
                AjustesMotorBots(
                  discordWebhookUrl: webhookCtrl.text.trim(),
                  notificarCompras: notifyBuys,
                  notificarVentas: notifySells,
                  notificarAlertasMeseta: notifyPlateau,
                ),
              );
              final ok = await provider.probarWebhookDiscord();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Mensaje de prueba enviado a Discord correctamente.'
                        : 'No se pudo entregar el mensaje de prueba a Discord.'),
                    backgroundColor: ok ? AppColors.bull : AppColors.bear,
                  ),
                );
              }
            },
            icon: const Icon(Icons.send_outlined,
                size: 15, color: AppColors.primary),
            label: const Text('Probar Webhook',
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await provider.guardarAjustesSistema(
                AjustesMotorBots(
                  discordWebhookUrl: webhookCtrl.text.trim(),
                  notificarCompras: notifyBuys,
                  notificarVentas: notifySells,
                  notificarAlertasMeseta: notifyPlateau,
                ),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Preferencias de notificación actualizadas en la API central.'
                        : 'No se pudieron guardar las preferencias en la API central.'),
                    backgroundColor: ok ? AppColors.bull : AppColors.bear,
                  ),
                );
              }
            },
            child: const Text('Guardar Cambios',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ),
  );
}
