import 'package:flutter/material.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/design/content_width.dart';
import '../../../../core/design/pro_crown.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../pro/data/pro_service.dart';
import '../../../pro/presentation/screens/pro_screen.dart';
import '../../data/business_repository.dart';
import '../../models/business.dart';

/// Ajustes › Tu negocio › Módulos: todo lo que ofrece Stockealo, qué hace, si
/// está encendido y en qué pestaña está. Es el único lugar donde se enciende el
/// arqueo de caja. No repite las funciones de cada módulo: solo dice dónde viven.
class ModulesScreen extends StatefulWidget {
  final Business business;
  final bool canEdit;

  const ModulesScreen({super.key, required this.business, required this.canEdit});

  static Future<void> open(BuildContext context, {required Business business, required bool canEdit}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ModulesScreen(business: business, canEdit: canEdit)));

  @override
  State<ModulesScreen> createState() => _ModulesScreenState();
}

class _ModulesScreenState extends State<ModulesScreen> {
  late bool _cash = widget.business.cashRegisterEnabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    ProService.instance.refresh(widget.business.id);
  }

  Future<void> _setCash(bool on) async {
    setState(() {
      _cash = on;
      _saving = true;
    });
    try {
      await BusinessRepository.instance.updateBusiness(id: widget.business.id, cashRegisterEnabled: on);
      if (mounted) {
        AppToast.showSuccess(context, on ? 'Caja encendida: la encuentras en el menú, en Caja.' : 'Caja apagada.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _cash = !on);
        AppToast.showError(context, 'No se pudo guardar: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _module({
    required IconData icon,
    required String title,
    required String what,
    required String where,
    required String status,
    bool on = true,
    bool pro = false,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: AppCard(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: on ? c.accent : c.inkFaint),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: c.ink))),
                      if (pro) ...[const SizedBox(width: AppSpace.xs), const ProCrown(size: 15)],
                    ],
                  ),
                  Text(what, style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted)),
                  const SizedBox(height: 2),
                  Text('$status · $where',
                      style: TextStyle(fontSize: AppText.sizeCaption, fontWeight: FontWeight.w600, color: on ? c.success : c.inkFaint)),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(title: const Text('Módulos')),
      body: ContentWidth(
        child: ValueListenableBuilder<ProStatus>(
          valueListenable: ProService.instance.status,
          builder: (context, pro, _) => ListView(
            padding: const EdgeInsets.all(AppSpace.lg),
            children: [
              Text('Todo lo que puedes usar en ${widget.business.name} y dónde lo encuentras.',
                  style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted)),
              const SizedBox(height: AppSpace.md),
              _module(
                icon: Icons.point_of_sale_outlined,
                title: 'Caja (arqueo)',
                what: 'Abre el turno con una base, registra entradas y salidas y cierra contando el dinero.',
                where: 'Caja, en el menú',
                status: _cash ? 'Encendida' : 'Apagada',
                on: _cash,
                trailing: Switch(
                  value: _cash,
                  onChanged: widget.canEdit && !_saving ? _setCash : null,
                ),
              ),
              _module(
                icon: Icons.view_kanban_outlined,
                title: 'Servicios',
                what: 'Para lavaderos, barberías y talleres: tablero, asistencia, comisiones y precios por servicio.',
                where: pro.services ? 'Servicios, en el menú' : 'incluido en Pro Servicios',
                status: pro.services ? 'Activo' : 'No incluido en tu plan',
                on: pro.services,
                pro: true,
                onTap: pro.services ? null : () => ProScreen.open(context, widget.business),
              ),
              _module(
                icon: Icons.storefront_outlined,
                title: 'Tienda en línea',
                what: 'Tu catálogo con carrito; los pedidos te llegan por WhatsApp.',
                where: 'Tienda en línea, en el menú',
                status: pro.active ? 'Incluida en tu plan' : 'Con Stockealo Pro',
                on: pro.active,
                pro: true,
                onTap: pro.active ? null : () => ProScreen.open(context, widget.business),
              ),
              _module(
                icon: Icons.move_to_inbox_outlined,
                title: 'Proveedores y entradas',
                what: 'Pedidos por WhatsApp, mercancía que llega y lo que debes a cada proveedor.',
                where: 'Clientes y proveedores, en el menú',
                status: 'Siempre disponible',
              ),
              _module(
                icon: Icons.menu_book_outlined,
                title: 'Catálogos',
                what: 'Catálogo en PDF e historias para compartir tus productos.',
                where: 'Productos › Catálogo',
                status: 'Siempre disponible',
              ),
              _module(
                icon: Icons.request_quote_outlined,
                title: 'Cotizaciones',
                what: 'Proformas para tus clientes que luego conviertes en venta.',
                where: 'Ventas › Cotizaciones',
                status: 'Siempre disponible',
              ),
              _module(
                icon: Icons.insert_chart_outlined_outlined,
                title: 'Reportes',
                what: 'Ganancias del periodo y descargas en Excel.',
                where: 'pestaña Reportes',
                status: 'Dueño y administradores',
              ),
              if (!widget.canEdit)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.sm),
                  child: Text('Solo el dueño o un administrador pueden encender o apagar módulos.',
                      style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
