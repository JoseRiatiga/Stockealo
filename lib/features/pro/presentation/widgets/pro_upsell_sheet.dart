import 'package:flutter/material.dart';

import '../../../../core/design/primary_action_button.dart';
import '../../../../core/design/pro_crown.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../business/models/business.dart';
import '../../data/pro_service.dart';
import '../screens/pro_screen.dart';

/// Qué beneficio de Pro resaltar en la ventana
enum ProBenefit { onlineStore, debtCollection, catalogs, stockyAi }

/// Cómo se cerró la ventana de Pro
enum ProUpsellResult {
  /// El negocio ya tiene Pro (lo activó desde la ventana)
  pro,

  /// Eligió la opción gratis que ofrecía la ventana
  alternative,

  /// "Ahora no" o la cerró
  dismissed,
}

/// Ventana que se abre desde abajo al tocar algo de Stockealo Pro: dice qué es,
/// muestra los beneficios y lleva a los planes, sin sacar al dueño de lo que hacía.
class ProUpsellSheet extends StatefulWidget {
  final Business business;
  final String title;
  final String message;
  final ProBenefit highlight;

  /// Opción gratis (por ejemplo, "Descargar la versión gratis"); null = solo "Ahora no"
  final String? alternativeLabel;

  const ProUpsellSheet({
    super.key,
    required this.business,
    required this.title,
    required this.message,
    required this.highlight,
    this.alternativeLabel,
  });

  static Future<ProUpsellResult> show(
    BuildContext context, {
    required Business business,
    required String title,
    required String message,
    required ProBenefit highlight,
    String? alternativeLabel,
  }) async {
    final choice = await showModalBottomSheet<_Choice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => ProUpsellSheet(
        business: business,
        title: title,
        message: message,
        highlight: highlight,
        alternativeLabel: alternativeLabel,
      ),
    );
    if (choice == _Choice.alternative) return ProUpsellResult.alternative;
    if ((choice == _Choice.plans || choice == _Choice.code) && context.mounted) {
      await ProScreen.open(context, business, focusCode: choice == _Choice.code);
      final status = await ProService.instance.refresh(business.id);
      if (status.active) return ProUpsellResult.pro;
    }
    return ProUpsellResult.dismissed;
  }

  /// "Desde $2.000 / semana": el plan semanal o mensual más barato; null sin planes
  @visibleForTesting
  static String? priceFromText(List<ProPlan> plans) {
    final recurring = plans.where((p) => (p.period == 'week' || p.period == 'month') && p.price > 0).toList();
    if (recurring.isEmpty) return null;
    recurring.sort((a, b) => a.price.compareTo(b.price));
    final cheapest = recurring.first;
    return 'Desde ${CurrencyFormatter.formatIn(cheapest.price, cheapest.currency)} ${cheapest.perLabel}';
  }

  @override
  State<ProUpsellSheet> createState() => _ProUpsellSheetState();
}

enum _Choice { plans, code, alternative }

class _ProUpsellSheetState extends State<ProUpsellSheet> {
  String? _priceFrom;

  @override
  void initState() {
    super.initState();
    _loadPrice();
  }

  Future<void> _loadPrice() async {
    try {
      final plans = await ProService.instance.plans(widget.business.currency);
      final text = ProUpsellSheet.priceFromText(plans);
      if (mounted && text != null) setState(() => _priceFrom = text);
    } catch (_) {
      // Sin conexión la ventana se muestra sin precio
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: c.inkMuted),
                ),
              ),
              const Center(child: ProCrown(size: 40)),
              const SizedBox(height: AppSpace.sm),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.ink),
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.4, color: c.inkMuted),
              ),
              const SizedBox(height: AppSpace.lg),
              Container(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: c.line),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < proBenefits.length; i++)
                      _benefit(c, proBenefits[i], highlighted: i == widget.highlight.index),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                'Todo lo demás sigue gratis.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: c.inkFaint),
              ),
              const SizedBox(height: AppSpace.lg),
              if (_priceFrom != null) ...[
                Text(
                  _priceFrom!,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink),
                ),
                const SizedBox(height: AppSpace.sm),
              ],
              PrimaryActionButton(
                label: 'Ver planes',
                icon: Icons.workspace_premium_outlined,
                onPressed: () => Navigator.pop(context, _Choice.plans),
              ),
              const SizedBox(height: AppSpace.xs),
              if (widget.alternativeLabel != null)
                TextButton(
                  onPressed: () => Navigator.pop(context, _Choice.alternative),
                  child: Text(widget.alternativeLabel!),
                )
              else
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(foregroundColor: c.inkMuted),
                  child: const Text('Ahora no'),
                ),
              TextButton(
                onPressed: () => Navigator.pop(context, _Choice.code),
                style: TextButton.styleFrom(foregroundColor: c.inkMuted),
                child: const Text('Ya tengo un código'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _benefit(StockealoColors c, (IconData, String, String) b, {required bool highlighted}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 1),
      padding: EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: highlighted ? AppSpace.md : AppSpace.sm),
      decoration: highlighted
          ? BoxDecoration(color: c.successSoft, borderRadius: BorderRadius.circular(AppRadius.control))
          : null,
      child: Row(
        crossAxisAlignment: highlighted ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Icon(b.$1, size: 22, color: highlighted ? c.accent : c.inkMuted),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.$2, style: TextStyle(fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500, color: c.ink)),
                // Solo el beneficio de lo que tocaste lleva la explicación
                if (highlighted) Text(b.$3, style: TextStyle(fontSize: 13, color: c.inkMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
