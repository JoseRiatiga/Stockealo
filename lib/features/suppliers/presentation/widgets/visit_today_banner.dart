import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../business/models/business.dart';
import '../screens/suppliers_screen.dart';
import '../../data/supplier_repository.dart';
import '../../models/supplier.dart';

/// "Hoy pasa X": aparece el día de visita de un proveedor, con el pedido a un toque.
/// No ocupa espacio si nadie pasa hoy.
class VisitTodayBanner extends StatefulWidget {
  final Business business;
  final String? userName;
  final EdgeInsetsGeometry padding;

  const VisitTodayBanner({super.key, required this.business, this.userName, this.padding = EdgeInsets.zero});

  @override
  State<VisitTodayBanner> createState() => _VisitTodayBannerState();
}

class _VisitTodayBannerState extends State<VisitTodayBanner> {
  List<Supplier> _today = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant VisitTodayBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.business.id != widget.business.id) _load();
  }

  Future<void> _load() async {
    try {
      final list = await SupplierRepository.instance.visitingOn(widget.business.id, DateTime.now());
      if (mounted) setState(() => _today = list);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_today.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final names = _today.map((s) => s.name).toList();
    final who = names.length == 1 ? names.first : '${names.sublist(0, names.length - 1).join(', ')} y ${names.last}';
    return Padding(
      padding: widget.padding,
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.sm, AppSpace.md),
        decoration: BoxDecoration(
          color: c.infoSoft,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            Icon(Icons.event_available_outlined, color: c.info),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hoy pasa $who', style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
                  Text('Revisa qué pedirle antes de que llegue.', style: TextStyle(color: c.inkMuted, fontSize: 12)),
                ],
              ),
            ),
            TextButton(
              // El pedido vive en Proveedores y entradas: el aviso solo lleva allá
              onPressed: () => SuppliersScreen.open(context, business: widget.business, userName: widget.userName),
              child: const Text('Ver proveedor'),
            ),
          ],
        ),
      ),
    );
  }
}
