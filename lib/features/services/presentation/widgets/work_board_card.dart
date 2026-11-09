import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../business/models/business.dart';
import '../../data/services_repository.dart';
import '../../models/service_models.dart';
import '../screens/work_board_screen.dart';

/// Tarjeta de Inicio para negocios de servicios: cuántas motos hay en cada estado
class WorkBoardCard extends StatefulWidget {
  final Business business;
  const WorkBoardCard({super.key, required this.business});

  @override
  State<WorkBoardCard> createState() => _WorkBoardCardState();
}

class _WorkBoardCardState extends State<WorkBoardCard> {
  Map<String, int> _counts = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant WorkBoardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.business.id != widget.business.id) _load();
  }

  Future<void> _load() async {
    try {
      final orders = await ServicesRepository.instance.getBoard(widget.business.id);
      final counts = <String, int>{};
      for (final o in orders) {
        counts[o.status] = (counts[o.status] ?? 0) + 1;
      }
      if (mounted) setState(() => _counts = counts);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final type = ServiceType.of(widget.business.serviceType);
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: c.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () async {
          await WorkBoardScreen.open(context, business: widget.business);
          _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: c.infoSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
                child: Icon(type.usesPlate ? Icons.two_wheeler_outlined : Icons.content_cut_rounded, color: c.info),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tablero', style: TextStyle(color: c.ink, fontWeight: FontWeight.w700, fontSize: 15)),
                    Text(
                      [
                        '${_counts[WorkOrder.waiting] ?? 0} en espera',
                        '${_counts[WorkOrder.inProgress] ?? 0} ${type.inProgress.toLowerCase()}',
                        '${_counts[WorkOrder.ready] ?? 0} listas',
                        '${_counts[WorkOrder.delivered] ?? 0} entregadas hoy',
                      ].join(' · '),
                      style: TextStyle(color: c.inkMuted, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}
