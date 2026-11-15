import 'package:flutter/material.dart';

import '../../../../core/design/status_pill.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../data/pro_service.dart';

/// Lo que puede necesitar un negocio y qué plan lo trae (0.15.0, punto 9)
enum ProNeed {
  store('Vender en línea con mi propia tienda', 'business'),
  debts('Cobrar fiados automáticamente', 'business'),
  catalogs('Catálogos con mi marca', 'business'),
  stocky('Más preguntas a Stocky', 'business'),
  services('Ofrecer servicios con más de 3 empleados, comisiones o reservas', 'services'),
  branches('Tener varias sedes o locales', 'services');

  final String label;

  /// El plan más barato que lo trae: 'business' (Pro) o 'services' (Pro Servicios)
  final String kind;
  const ProNeed(this.label, this.kind);

  /// El plan que conviene para lo que se marcó; null si no se marcó nada
  static String? suggest(Set<ProNeed> needs) {
    if (needs.isEmpty) return null;
    return needs.any((n) => n.kind == 'services') ? 'services' : 'business';
  }
}

/// «¿Qué necesitas para tu negocio?»: la persona marca lo que necesita y la app le dice
/// qué plan le sirve y por qué, en vez de que adivine.
class PlanFinder extends StatefulWidget {
  /// Al tocar el botón: el plan sugerido y lo que se marcó (para el mensaje o los planes)
  final void Function(String kind, Set<ProNeed> needs) onChoose;

  /// Con precios encendidos el botón lleva a los planes; si no, a escribir por WhatsApp
  final bool pricingVisible;

  const PlanFinder({super.key, required this.onChoose, required this.pricingVisible});

  @override
  State<PlanFinder> createState() => _PlanFinderState();
}

class _PlanFinderState extends State<PlanFinder> {
  final Set<ProNeed> _needs = {};

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final kind = ProNeed.suggest(_needs);
    final why = [for (final n in _needs) if (n.kind == kind) n.label.toLowerCase()];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final n in ProNeed.values)
          CheckboxListTile(
            value: _needs.contains(n),
            onChanged: (v) => setState(() => v == true ? _needs.add(n) : _needs.remove(n)),
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(n.label, style: AppText.body(context)),
          ),
        const SizedBox(height: AppSpace.sm),
        if (kind == null)
          Text('Marca lo que necesitas y te decimos qué plan te sirve.', style: AppText.small(context, color: c.inkMuted))
        else ...[
          Row(
            children: [
              Text('Te sirve', style: AppText.body(context, color: c.inkMuted)),
              const SizedBox(width: AppSpace.sm),
              StatusPill(proKindLabel(kind), tone: AppTone.accent),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Porque quieres ${why.join(', ')}.'
            '${_needs.contains(ProNeed.branches) ? ' Las sedes llegan pronto a Pro Servicios.' : ''}'
            '${kind == 'services' ? ' Pro Servicios trae todo lo de Pro.' : ''}',
            style: AppText.small(context),
          ),
          const SizedBox(height: AppSpace.md),
          FilledButton.icon(
            onPressed: () => widget.onChoose(kind, {..._needs}),
            icon: Icon(widget.pricingVisible ? Icons.arrow_downward_outlined : Icons.chat_outlined, size: 18),
            label: Text(widget.pricingVisible ? 'Ver ${proKindLabel(kind)}' : 'Preguntar por ${proKindLabel(kind)}'),
          ),
        ],
      ],
    );
  }
}
