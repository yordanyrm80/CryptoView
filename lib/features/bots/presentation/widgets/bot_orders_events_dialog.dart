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
    final media = MediaQuery.of(context).size;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
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
        width: (media.width * 0.92).clamp(300.0, 640.0),
        height: (media.height * 0.68).clamp(320.0, 440.0),
        child: Column(
          children: [
            Container(
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: media.width < 480,
                indicatorColor: AppColors.primary,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                tabs: [
                  Tab(
                    text: _ordenes.any((o) => o.estaAbierta)
                        ? 'Órdenes (${_ordenes.where((o) => o.estaAbierta).length} abiertas · ${_ordenes.length})'
                        : 'Órdenes (${_ordenes.length})',
                  ),
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
          'Sin órdenes registradas aún.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      );
    }

    final sorted = List<OrdenEjecutadaBot>.from(_ordenes)
      ..sort((a, b) {
        if (a.estaAbierta != b.estaAbierta) return a.estaAbierta ? -1 : 1;
        return b.fechaCreacion.compareTo(a.fechaCreacion);
      });

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
      itemBuilder: (ctx, i) {
        final o = sorted[i];
        final isBuy = o.side == 'BUY';
        final sideColor = isBuy ? AppColors.bull : Colors.amber;
        final baseCoin = o.simbolo.contains('/') ? o.simbolo.split('/').first : o.simbolo;
        final notionalUsdt = o.precio * o.cantidad;

        final Color statusColor;
        final String statusLabel;
        if (o.estaAbierta) {
          statusColor = Colors.cyanAccent;
          statusLabel = 'EN LIBRO';
        } else if (o.estaCancelada) {
          statusColor = AppColors.textSecondary;
          statusLabel = 'CANCELADA';
        } else {
          statusColor = AppColors.bull;
          statusLabel = 'EJECUTADA';
        }

        final trancheTag = o.indiceTramo != null ? 'T${o.indiceTramo} · ' : '';
        final detailText = o.estaAbierta
            ? '$trancheTag${o.tipoOrden} en KuCoin · \$${notionalUsdt.toStringAsFixed(2)}'
            : (o.estaCancelada
                ? '$trancheTag${o.tipoOrden} expirada/cancelada'
                : '$trancheTag${o.tipoOrden} · Fee: ${_currencyFmt.format(o.comision)} USDT');

        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          leading: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: sideColor.withValues(alpha: o.estaCancelada ? 0.08 : 0.16),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: sideColor.withValues(alpha: o.estaCancelada ? 0.25 : 0.5),
                  ),
                ),
                child: Text(
                  o.side,
                  style: TextStyle(
                    color: o.estaCancelada ? AppColors.textSecondary : sideColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                statusLabel,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Precio: ${_currencyFmt.format(o.precio)}',
                style: TextStyle(
                  color: o.estaCancelada ? AppColors.textSecondary : AppColors.textPrimary,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  decoration: o.estaCancelada ? TextDecoration.lineThrough : null,
                ),
              ),
              Text(
                '${o.cantidad.toStringAsFixed(6)} $baseCoin',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      detailText,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: o.estaAbierta ? Colors.cyanAccent : AppColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _dateFmt.format((o.fechaEjecucion ?? o.fechaCreacion).toLocal()),
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
              if (o.motivo != null && o.motivo!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    o.motivo!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
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
        if (ev.tipoEvento == 'ORDER_PLACED') evColor = Colors.cyanAccent;
        if (ev.tipoEvento == 'ORDER_EXPIRED') evColor = Colors.orangeAccent;
        if (ev.tipoEvento == 'CAPITAL_SYNC') evColor = Colors.purpleAccent;
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
