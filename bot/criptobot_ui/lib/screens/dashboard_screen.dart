import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/bot_models.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../theme/app_theme.dart';
import 'create_bot_dialog.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _wsService = WebSocketService();
  final _formatterMoneda = NumberFormat.currency(locale: 'en_US', symbol: r'$', decimalDigits: 2);
  final List<String> _registrosEnVivo = [];

  MetricasGlobales? _metricas;
  List<ResumenBot> _bots = [];
  Map<String, List<TramoModel>> _tramosPorBot = {};
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    _iniciarWebSocket();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    final metricas = await ApiService.obtenerMetricasGlobales();
    final bots = await ApiService.listarBots();

    final Map<String, List<TramoModel>> mapaTramos = {};
    for (final bot in bots) {
      final tramos = await ApiService.obtenerTramos(bot.idBot);
      mapaTramos[bot.idBot] = tramos;
    }

    if (mounted) {
      setState(() {
        _metricas = metricas;
        _bots = bots;
        _tramosPorBot = mapaTramos;
        _cargando = false;
      });
    }
  }

  void _iniciarWebSocket() {
    _wsService.conectar();
    _wsService.eventos.listen((evento) {
      if (mounted) {
        final hora = DateFormat('HH:mm:ss').format(DateTime.now());
        final tipo = evento['evento'] ?? evento['event'] ?? 'INFO';
        String mensaje = '[$hora] $tipo';

        if (tipo == 'TRAMO_COMPRADO') {
          mensaje = '[$hora] 🟢 COMPRA: Tramo T${evento['indice_tramo']} a \$${evento['precio_compra']} (${evento['bot_id']})';
        } else if (tipo == 'TRAMO_VENDIDO') {
          mensaje = '[$hora] 💰 VENTA: Tramo T${evento['indice_tramo']} Ganancia +${evento['beneficio_usdt']} USDT!';
        } else if (tipo == 'LATIDO_MERCADO') {
          return;
        }

        setState(() {
          _registrosEnVivo.insert(0, mensaje);
          if (_registrosEnVivo.length > 30) {
            _registrosEnVivo.removeLast();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _wsService.dispose();
    super.dispose();
  }

  void _mostrarDialogoConfiguracionSistema() async {
    final hostController = TextEditingController(text: ApiService.baseUrl);
    final webhookController = TextEditingController();
    bool discordHabilitado = true;

    final ajustes = await ApiService.obtenerAjustesSistema();
    if (ajustes != null) {
      discordHabilitado = ajustes.discordHabilitado;
      if (ajustes.discordConfigurado) {
        webhookController.text = ajustes.discordWebhookEnmascarado;
      }
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppTheme.fondoTarjeta,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppTheme.bordeTarjeta),
            ),
            title: const Row(
              children: [
                Icon(Icons.tune, color: AppTheme.azulCyan),
                SizedBox(width: 8),
                Text('Ajustes del Sistema y Alertas', style: TextStyle(color: AppTheme.textoPrincipal, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('CONEXIÓN SERVIDOR / TAILSCALE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textoSecundario, letterSpacing: 0.8)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: hostController,
                    style: const TextStyle(color: AppTheme.textoPrincipal, fontSize: 13),
                    decoration: const InputDecoration(
                      labelText: 'API Host Base URL',
                      hintText: 'http://127.0.0.1:8000',
                      filled: true,
                      fillColor: AppTheme.fondoPrincipal,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Divider(color: AppTheme.bordeTarjeta),
                  const SizedBox(height: 10),
                  const Text('NOTIFICACIONES DISCORD (MÓVIL / DESKTOP)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textoSecundario, letterSpacing: 0.8)),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Activar Alertas Discord', style: TextStyle(color: AppTheme.textoPrincipal, fontSize: 13)),
                    value: discordHabilitado,
                    activeThumbColor: AppTheme.azulCyan,
                    onChanged: (val) => setDialogState(() => discordHabilitado = val),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: webhookController,
                    style: const TextStyle(color: AppTheme.textoPrincipal, fontSize: 12),
                    decoration: InputDecoration(
                      labelText: 'Discord Webhook URL',
                      hintText: 'https://discord.com/api/webhooks/...',
                      helperText: (ajustes != null && ajustes.discordConfigurado) ? 'Webhook guardado en PostgreSQL' : 'Pega la URL de tu canal Discord',
                      helperStyle: TextStyle(color: (ajustes != null && ajustes.discordConfigurado) ? AppTheme.verdeGanancia : AppTheme.textoSecundario, fontSize: 11),
                      filled: true,
                      fillColor: AppTheme.fondoPrincipal,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.azulCyan,
                        side: const BorderSide(color: AppTheme.azulCyan),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.notifications_active, size: 16),
                      label: const Text('Enviar Alerta de Prueba a Discord', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final ok = await ApiService.probarNotificacion(channel: 'discord');
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(ok ? '¡Alerta de prueba enviada a Discord con éxito!' : 'Error enviando alerta de prueba. Verifica la URL.'),
                            backgroundColor: ok ? AppTheme.verdeSuave : AppTheme.rojoPerdida,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar', style: TextStyle(color: AppTheme.textoSecundario)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.azulCyan),
                onPressed: () async {
                  final navigator = Navigator.of(ctx);
                  final messenger = ScaffoldMessenger.of(context);
                  final nuevoHost = hostController.text.trim();
                  if (nuevoHost.isNotEmpty) {
                    await ApiService.configurarHost(nuevoHost);
                  }

                  final nuevoWebhook = webhookController.text.trim();
                  final urlParaEnviar = (nuevoWebhook.startsWith('http') && !nuevoWebhook.contains('...')) ? nuevoWebhook : null;
                  await ApiService.actualizarAjustesSistema(
                    discordWebhookUrl: urlParaEnviar,
                    discordEnabled: discordHabilitado,
                  );

                  navigator.pop();
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Ajustes guardados correctamente.'),
                      backgroundColor: AppTheme.verdeSuave,
                    ),
                  );
                  _cargarDatos();
                  _iniciarWebSocket();
                },
                child: const Text('Guardar Ajustes', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _mostrarDialogoTransaccionCapital(ResumenBot bot, bool esDeposito) {
    final controller = TextEditingController();
    final motivoController = TextEditingController(text: esDeposito ? 'Inyección de capital' : 'Retiro de beneficios');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.fondoTarjeta,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppTheme.bordeTarjeta),
        ),
        title: Row(
          children: [
            Icon(esDeposito ? Icons.add_circle : Icons.remove_circle, color: esDeposito ? AppTheme.verdeGanancia : AppTheme.amarilloAdvertencia),
            const SizedBox(width: 8),
            Text(
              esDeposito ? 'Depositar Capital USDT' : 'Retirar Capital Libre',
              style: const TextStyle(color: AppTheme.textoPrincipal, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bot objetivo: ${bot.idBot} (${bot.simbolo})',
              style: const TextStyle(color: AppTheme.azulCyan, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Saldo disponible: ${_formatterMoneda.format(bot.usdtDisponible)} USDT',
              style: const TextStyle(color: AppTheme.textoSecundario, fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: AppTheme.textoPrincipal),
              decoration: const InputDecoration(
                labelText: 'Monto en USDT',
                prefixText: r'$ ',
                filled: true,
                fillColor: AppTheme.fondoPrincipal,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: motivoController,
              style: const TextStyle(color: AppTheme.textoPrincipal),
              decoration: const InputDecoration(
                labelText: 'Nota / Motivo',
                filled: true,
                fillColor: AppTheme.fondoPrincipal,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar', style: TextStyle(color: AppTheme.textoSecundario)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: esDeposito ? AppTheme.verdeGanancia : AppTheme.amarilloAdvertencia),
            onPressed: () async {
              final monto = double.tryParse(controller.text.trim()) ?? 0.0;
              if (monto <= 0) return;

              Navigator.pop(ctx);
              bool ok;
              if (esDeposito) {
                ok = await ApiService.depositarCapital(bot.idBot, monto, motivo: motivoController.text.trim());
              } else {
                ok = await ApiService.retirarCapital(bot.idBot, monto, motivo: motivoController.text.trim());
              }

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? 'Operación ejecutada con éxito' : 'Error en la operación'),
                    backgroundColor: ok ? AppTheme.verdeSuave : AppTheme.rojoPerdida,
                  ),
                );
                _cargarDatos();
              }
            },
            child: Text(
              esDeposito ? 'Confirmar Depósito' : 'Confirmar Retiro',
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.candlestick_chart, color: AppTheme.azulCyan),
            const SizedBox(width: 8),
            const Flexible(
              child: Text(
                'CRIPTOBOT',
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.verdeSuave.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.verdeGanancia, width: 0.8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.vpn_lock, size: 11, color: AppTheme.verdeGanancia),
                  SizedBox(width: 3),
                  Text('Local / Tailscale', style: TextStyle(color: AppTheme.verdeGanancia, fontSize: 10, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active, color: AppTheme.azulCyan),
            tooltip: 'Ajustes y Alertas Discord',
            onPressed: _mostrarDialogoConfiguracionSistema,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.textoSecundario),
            tooltip: 'Actualizar Datos',
            onPressed: _cargarDatos,
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: AppTheme.textoSecundario),
            tooltip: 'Configuración Servidor',
            onPressed: _mostrarDialogoConfiguracionSistema,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: AppTheme.azulCyan))
          : RefreshIndicator(
              onRefresh: _cargarDatos,
              color: AppTheme.azulCyan,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _construirTarjetasMetricasGlobales(),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'ESTRATEGIA ACTIVA (BOTS)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: AppTheme.textoSecundario,
                          ),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.add, size: 16, color: AppTheme.azulCyan),
                          label: const Text('Nuevo Bot', style: TextStyle(color: AppTheme.azulCyan, fontSize: 12)),
                          onPressed: () async {
                            final creado = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => const CreateBotDialog(),
                            );
                            if (creado == true) _cargarDatos();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._bots.map((bot) => _construirTarjetaBot(bot)),
                    const SizedBox(height: 24),
                    const Text(
                      'REGISTRO DE EVENTOS EN VIVO (WEBSOCKET)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: AppTheme.textoSecundario,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _construirRegistroEnVivo(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _construirTarjetasMetricasGlobales() {
    final equidad = _metricas?.equidadTotalUsdt ?? 0.0;
    final flujoCaja = _metricas?.flujoCajaTotalUsdt ?? 0.0;
    final tasaAcierto = _metricas?.tasaAciertoPct ?? 0.0;
    final operaciones = _metricas?.operacionesCerradas ?? 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final esPantallaAncha = constraints.maxWidth > 600;
        return GridView.count(
          crossAxisCount: esPantallaAncha ? 4 : 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: esPantallaAncha ? 2.2 : 1.5,
          children: [
            _itemMetrica('EQUIDAD TOTAL', _formatterMoneda.format(equidad), Icons.account_balance_wallet, AppTheme.azulCyan),
            _itemMetrica('FLUJO CAJA EXTRAÍDO', _formatterMoneda.format(flujoCaja), Icons.payments, AppTheme.verdeGanancia),
            _itemMetrica('TASA DE ACIERTO', '${tasaAcierto.toStringAsFixed(1)}%', Icons.check_circle_outline, AppTheme.verdeGanancia),
            _itemMetrica('OPERACIONES CERRADAS', operaciones.toString(), Icons.swap_horiz, AppTheme.amarilloAdvertencia),
          ],
        );
      },
    );
  }

  Widget _itemMetrica(String titulo, String valor, IconData icono, Color colorAcento) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.fondoTarjeta,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.bordeTarjeta),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(titulo, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.textoSecundario, letterSpacing: 0.5)),
              Icon(icono, size: 16, color: colorAcento),
            ],
          ),
          Text(valor, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorAcento)),
        ],
      ),
    );
  }

  Widget _construirTarjetaBot(ResumenBot bot) {
    final tramos = _tramosPorBot[bot.idBot] ?? [];
    final estaCorriendo = bot.estado == 'RUNNING';
    final estaDetenido = bot.estado == 'STOPPED';
    final estaPausado = bot.estado == 'PAUSED';

    final esFlagship = bot.idBot == 'apex_titan_btc';
    final nombreVisual = esFlagship ? 'Apex Titan' : bot.idBot;

    Color colorEstado = Colors.grey;
    String textoEstado = bot.estado;
    if (estaCorriendo) {
      colorEstado = AppTheme.verdeGanancia;
      textoEstado = 'ACTIVO (RUNNING)';
    } else if (estaPausado) {
      colorEstado = AppTheme.amarilloAdvertencia;
      textoEstado = 'PAUSADO';
    } else if (estaDetenido) {
      colorEstado = AppTheme.rojoPerdida;
      textoEstado = 'DETENIDO (STOPPED)';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.fondoTarjeta,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: estaCorriendo ? AppTheme.verdeGanancia.withValues(alpha: 0.6) : AppTheme.bordeTarjeta,
          width: estaCorriendo ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(nombreVisual, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textoPrincipal)),
                      if (esFlagship) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.azulCyan.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppTheme.azulCyan, width: 0.8),
                          ),
                          child: const Text('OFICIAL FLAGSHIP', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppTheme.azulCyan)),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: bot.simulacionDryRun ? Colors.blueGrey.withValues(alpha: 0.3) : AppTheme.verdeSuave,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          bot.simulacionDryRun ? 'DRY-RUN' : 'LIVE KUCOIN',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: bot.simulacionDryRun ? Colors.cyanAccent : AppTheme.verdeGanancia),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colorEstado.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: colorEstado, width: 0.8),
                        ),
                        child: Text(
                          textoEstado,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colorEstado),
                        ),
                      ),
                      if (bot.nombreSubcuenta != null && bot.nombreSubcuenta!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.purpleAccent, width: 0.8),
                          ),
                          child: Text(
                            'SUB: ${bot.nombreSubcuenta}',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.purpleAccent),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('${bot.simbolo} • ${bot.nombreEstrategia}', style: const TextStyle(fontSize: 12, color: AppTheme.textoSecundario)),
                ],
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.verdeGanancia,
                      side: const BorderSide(color: AppTheme.verdeGanancia),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Depositar', style: TextStyle(fontSize: 11)),
                    onPressed: () => _mostrarDialogoTransaccionCapital(bot, true),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.amarilloAdvertencia,
                      side: const BorderSide(color: AppTheme.amarilloAdvertencia),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    icon: const Icon(Icons.arrow_upward, size: 14),
                    label: const Text('Retirar', style: TextStyle(fontSize: 11)),
                    onPressed: () => _mostrarDialogoTransaccionCapital(bot, false),
                  ),
                  const SizedBox(width: 8),
                  if (estaDetenido) ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.verdeGanancia,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      ),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Iniciar Bot', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        await ApiService.iniciarBot(bot.idBot);
                        _cargarDatos();
                      },
                    ),
                  ] else if (estaCorriendo) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.amarilloAdvertencia,
                        side: const BorderSide(color: AppTheme.amarilloAdvertencia),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      icon: const Icon(Icons.pause, size: 14),
                      label: const Text('Pausar', style: TextStyle(fontSize: 11)),
                      onPressed: () async {
                        await ApiService.pausarBot(bot.idBot);
                        _cargarDatos();
                      },
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.rojoPerdida,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      icon: const Icon(Icons.stop, size: 16),
                      label: const Text('Detener', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () async {
                        await ApiService.detenerBot(bot.idBot);
                        _cargarDatos();
                      },
                    ),
                  ] else if (estaPausado) ...[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.verdeGanancia,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: const Text('Reanudar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () async {
                        await ApiService.reanudarBot(bot.idBot);
                        _cargarDatos();
                      },
                    ),
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.rojoPerdida,
                        side: const BorderSide(color: AppTheme.rojoPerdida),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      icon: const Icon(Icons.stop, size: 14),
                      label: const Text('Detener', style: TextStyle(fontSize: 11)),
                      onPressed: () async {
                        await ApiService.detenerBot(bot.idBot);
                        _cargarDatos();
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),

          // Plateau & Capital Injection Alert Banner
          if (bot.recomendadaInyeccion) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      bot.consejoInyeccion.isNotEmpty
                          ? bot.consejoInyeccion
                          : 'Alerta de Fase Meseta: El bot ha consumido sus tramos base. Se sugiere activar tramos de suelo o desplegar Bot Gemelo.',
                      style: const TextStyle(color: Colors.amber, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),
          const Divider(color: AppTheme.bordeTarjeta, height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _infoColumna('Equidad Total', _formatterMoneda.format(bot.equidadActualUsdt), AppTheme.azulCyan),
              _infoColumna('USDT Disponible', _formatterMoneda.format(bot.usdtDisponible), AppTheme.verdeGanancia),
              _infoColumna('Invertido Activo', _formatterMoneda.format(bot.montoInvertidoUsdt), AppTheme.textoPrincipal),
              _infoColumna('Ganancia Realizada', _formatterMoneda.format(bot.beneficioRealizadoUsdt), AppTheme.verdeGanancia),
              _infoColumna('Tramos Activos', '${bot.tramosActivos} tramos', AppTheme.amarilloAdvertencia),
            ],
          ),
          const SizedBox(height: 16),
          const Text('ESCALERA DE TRAMOS QUANTUM', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textoSecundario)),
          const SizedBox(height: 8),
          _construirEscaleraTramos(tramos),
        ],
      ),
    );
  }

  Widget _infoColumna(String titulo, String valor, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: const TextStyle(fontSize: 11, color: AppTheme.textoSecundario)),
        const SizedBox(height: 4),
        Text(valor, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _construirEscaleraTramos(List<TramoModel> tramos) {
    if (tramos.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.fondoPrincipal,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Text('Sin tramos abiertos en este momento. Esperando señal de entrada...', style: TextStyle(fontSize: 12, color: AppTheme.textoSecundario)),
        ),
      );
    }

    return Column(
      children: tramos.map((t) {
        final esActivo = t.estado == 'ACTIVO' || t.estado == 'ACTIVE';
        final esSuelo = t.indiceTramo >= 5;
        final colorTramo = esSuelo ? Colors.purpleAccent : AppTheme.azulCyan;

        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.fondoPrincipal,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: esActivo ? colorTramo.withValues(alpha: 0.5) : AppTheme.bordeTarjeta,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: esActivo ? colorTramo.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      esSuelo ? 'SUELO T${t.indiceTramo}' : 'T${t.indiceTramo}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: esActivo ? colorTramo : Colors.grey),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('Compra: \$${t.precioCompra.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, color: AppTheme.textoPrincipal)),
                ],
              ),
              Row(
                children: [
                  Text('TP Objetivo: \$${t.precioObjetivoVenta.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, color: AppTheme.verdeGanancia)),
                  const SizedBox(width: 12),
                  Text('\$${t.presupuestoAsignado.toStringAsFixed(0)} USDT', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textoSecundario)),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _construirRegistroEnVivo() {
    return Container(
      height: 180,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.fondoTarjeta,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.bordeTarjeta),
      ),
      child: _registrosEnVivo.isEmpty
          ? const Center(
              child: Text('Canal WebSocket activo. Esperando eventos del motor...', style: TextStyle(fontSize: 12, color: AppTheme.textoSecundario)),
            )
          : ListView.builder(
              itemCount: _registrosEnVivo.length,
              itemBuilder: (ctx, i) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  _registrosEnVivo[i],
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: AppTheme.textoPrincipal),
                ),
              ),
            ),
    );
  }
}
