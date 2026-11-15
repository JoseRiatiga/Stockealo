import 'package:flutter/material.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/status_pill.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../../store/data/online_store_service.dart';
import '../../data/product_templates.dart';

/// Tarjeta de Productos (0.16.0, fase 2a): «Arma tu inventario de licorera». Sale
/// mientras el negocio no haya cargado una plantilla ni la haya cerrado.
class ProductTemplateCard extends StatefulWidget {
  final Business business;
  final VoidCallback onApplied;
  const ProductTemplateCard({super.key, required this.business, required this.onApplied});

  @override
  State<ProductTemplateCard> createState() => _ProductTemplateCardState();
}

class _ProductTemplateCardState extends State<ProductTemplateCard> {
  bool _show = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.business.id;
    final show = await ProductTemplate.applied(id) == null && !await ProductTemplate.dismissed(id);
    if (mounted) setState(() => _show = show);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    final c = context.colors;
    final suggested = ProductTemplate.suggestedFor(widget.business.icon);
    return AppCard(
      onTap: () async {
        if (await ProductTemplateSheet.show(context, business: widget.business)) {
          widget.onApplied();
          _load();
        }
      },
      child: Row(
        children: [
          Icon(suggested?.icon ?? Icons.auto_awesome_outlined, color: c.accent),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suggested == null ? 'Arma tu inventario con una plantilla' : 'Arma tu inventario de ${suggested.label.toLowerCase()}',
                  style: AppText.body(context, weight: FontWeight.w600),
                ),
                Text(
                  suggested == null
                      ? 'Categorías y variantes listas para tu tipo de negocio.'
                      : 'Categorías${suggested.preset != null ? ', ${suggested.preset!.label.toLowerCase()}' : ''}'
                          '${suggested.adult ? ' y el aviso +18' : ''}, listos.',
                  style: AppText.small(context, color: c.inkMuted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'No mostrar más',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () async {
              await ProductTemplate.dismiss(widget.business.id);
              _load();
            },
          ),
        ],
      ),
    );
  }
}

/// «¿Qué tipo de negocio es?» y después revisar lo que se carga. Devuelve true si cargó.
class ProductTemplateSheet {
  static Future<bool> show(BuildContext context, {required Business business}) async {
    final suggested = ProductTemplate.suggestedFor(business.icon);
    final options = [
      if (suggested != null) suggested,
      for (final t in ProductTemplate.all)
        if (t != suggested) t,
    ];
    final picked = await AppSheet.show<ProductTemplate>(
      context: context,
      title: '¿Qué tipo de negocio es?',
      subtitle: 'Te armamos las categorías y variantes de tu tipo de negocio. No crea productos ni toca los que ya tienes.',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final t in options)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: AppCard(
                borderColor: t == suggested ? ctx.colors.accent : null,
                onTap: () => Navigator.pop(ctx, t),
                child: Row(
                  children: [
                    Icon(t.icon, color: ctx.colors.accent),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: AppSpace.sm,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(t.label, style: AppText.body(ctx, weight: FontWeight.w700)),
                              if (t == suggested) const StatusPill('Sugerida', tone: AppTone.accent, compact: true),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(t.summary, style: AppText.small(ctx, color: ctx.colors.inkMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (picked == null || !context.mounted) return false;
    return _review(context, business, picked);
  }

  static Future<bool> _review(BuildContext context, Business business, ProductTemplate t) async {
    final chosen = {...t.categories};
    var adult = t.adult;
    final ok = await AppSheet.show<bool>(
      context: context,
      title: t.label,
      subtitle: 'Quita lo que no te sirva. Solo se agrega lo que falte.',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final c = ctx.colors;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Categorías', style: AppText.body(ctx, weight: FontWeight.w600)),
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.xs + 2,
                runSpacing: AppSpace.xs + 2,
                children: [
                  for (final cat in t.categories)
                    FilterChip(
                      label: Text(cat),
                      selected: chosen.contains(cat),
                      onSelected: (v) => setLocal(() => v ? chosen.add(cat) : chosen.remove(cat)),
                    ),
                ],
              ),
              if (t.preset != null) ...[
                const SizedBox(height: AppSpace.lg),
                Text(
                  t.preset!.secondName == 'Color' ? t.preset!.attributeName : '${t.preset!.attributeName} y ${t.preset!.secondName.toLowerCase()}',
                  style: AppText.body(ctx, weight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  'Al crear un producto con variantes, toca «${t.preset!.label}» y salen ${t.preset!.values.join(', ')}.',
                  style: AppText.small(ctx, color: c.inkMuted),
                ),
              ],
              if (t.usesBrand) ...[
                const SizedBox(height: AppSpace.md),
                Text('Cada producto puede llevar su marca, y en la tienda se filtra por marca.',
                    style: AppText.small(ctx, color: c.inkMuted)),
              ],
              const SizedBox(height: AppSpace.md),
              if (t.adult)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Aviso +18 en la tienda', style: AppText.body(ctx)),
                  subtitle: Text('Al entrar preguntamos «¿Tienes 18 años o más?»', style: AppText.small(ctx)),
                  value: adult,
                  onChanged: (v) => setLocal(() => adult = v),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.storefront_outlined),
                title: Text('Plantilla de la tienda', style: AppText.body(ctx)),
                subtitle: Text('${StoreTemplate.label(t.storeTemplate)}: queda sugerida en Tienda en línea', style: AppText.small(ctx)),
              ),
              const SizedBox(height: AppSpace.md),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cargar plantilla')),
            ],
          );
        },
      ),
    );
    if (ok != true) return false;
    final added = await t.apply(business.id, categories: [for (final c in t.categories) if (chosen.contains(c)) c]);
    // El aviso +18 de una tienda que ya existe (sin internet o sin tienda, queda para
    // cuando la cree: Tienda en línea lo enciende solo para estos tipos)
    if (t.adult && adult) {
      try {
        final store = await OnlineStoreService.instance.getMine(business.id);
        if (store != null && !store.look.adult) {
          await OnlineStoreService.instance.saveLook(businessId: business.id, look: store.look.copyWith(adult: true));
        }
      } catch (_) {}
    }
    if (context.mounted) {
      AppToast.showSuccess(
        context,
        added == 0 ? 'Plantilla cargada. Ya tenías esas categorías.' : 'Plantilla cargada: $added ${added == 1 ? 'categoría nueva' : 'categorías nuevas'}.',
      );
    }
    return true;
  }
}
