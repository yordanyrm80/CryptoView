import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/bot_models.dart';
import '../../providers/bots_provider.dart';

class BotOrdersEventsDialog extends StatefulWidget {
  final ResumenBot bot;
  final BotsProvider provider;

  const BotOrdersEventsDialog({
    Key? key,
    required this.bot,
    required this.provider,
  }) : super(key: key);

  @override
  State<BotOrdersEventsDialog> createState() => _BotOrdersEventsDialogState();
}

class _BotOrdersEventsDialogState extends State<BotOrdersEventsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _currencyFmt = NumberFormat.currency(locale: 'en_US', symbol: '\$');
  final _dateFmt = DateFormat('yyyy-MM-dd HH:mm:ss');

  bool _loading = true;
  List<OrdenEjecutadaBot> _ordenes = [];
  List<EventoAuditoriaBot> _eventos = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _cargarDatos();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() => _loading = true);
    final ordenesFuture = widget.provider.obtenerOrdenesBot(widget.bot.idBot);
    final eventosFuture = widget.provider.obtenerEventosBot(widget.bot.idBot);

    final resultados = await Future.wait([ordenesFuture, eventosFuture]);
    if (mounted) {
      setState(() {
        _ordenes = resultados[0] as List<OrdenEjecutadaBot>;
        _eventos = resultados[1] as List<EventoAuditoriaBot>;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Row(
        children: [
          const Icon(Icons.history_edu_outlined, color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Historial Operativo · ${widget.bot.idBot}',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${widget.bot.simbolo} • ${widget.bot.simulacionDryRun ? "Modo Simulación" : "Modo En Vivo"}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18, color: AppColors.textSecondary),
            tooltip: 'Actualizar',
            onPressed: _cargarDatos,
          ),
        ],
      ),
      content: SizedBox(
        width: 640,
        height: 440,
        child: Column(
          children: [
            Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: AppColors.primary,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                tabs: [
                  Tab(text: 'Órdenes Ejecutadas (${_ordenes.length})'),
                  Tab(text: 'Bitácora de Eventos (${_eventos.length})'),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildTabOrdenes(),
                        _buildTabEventos(),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar', style: TextStyle(color: AppColors.textSecondary)),
        ),
      ],
    );
  }

  Widget _buildTabOrdenes() {
    if (_ordenes.isEmpty) {
      return const Center(
        child: Text(
          'Sin órdenes ejecutadas aún.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _ordenes.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
      itemBuilder: (ctx, i) {
        final o = _ordenes[i];
        final isBuy = o.side == 'BUY';
        final color = isBuy ? AppColors.bull : Colors.amber;

        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          leading: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Text(
              o.side,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Precio: ${_currencyFmt.format(o.precio)}',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${o.cantidad.toStringAsFixed(6)} ${o.simbolo.split("/").first}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
          subtitle: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Fee: ${_currencyFmt.format(o.comision)} USDT • ${o.estado}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                ),
              ),
              Text(
                _dateFmt.format(o.fechaCreacion.toLocal()),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabEventos() {
    if (_eventos.isEmpty) {
      return const Center(
        child: Text(
          'Sin eventos registrados en la bitácora.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _eventos.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
      itemBuilder: (ctx, i) {
        final ev = _eventos[i];
        Color evColor = AppColors.primary;
        if (ev.tipoEvento == 'BUY') evColor = AppColors.bull;
        if (ev.tipoEvento == 'SELL') evColor = Colors.amber;
        if (ev.tipoEvento == 'PAUSED' || ev.tipoEvento == 'STOPPED') evColor = AppColors.bear;

        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          leading: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: evColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: evColor.withValues(alpha: 0.4)),
            ),
            child: Text(
              ev.tipoEvento,
              style: TextStyle(
                color: evColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          title: Text(
            ev.detalles,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
          ),
          subtitle: Text(
            _dateFmt.format(ev.fecha.toLocal()),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5),
          ),
        );
      },
    );
  }
}
