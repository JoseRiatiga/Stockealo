import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'status_pill.dart';

/// Tarjeta de cifra del diseño: título pequeño, número grande, cambio frente al
/// periodo anterior, una línea de detalle, un gráfico opcional y una acción al pie
/// («Ver ganancias ›»).
///
/// [filled] la pinta con el color del negocio (solo una por pantalla: «Ventas de hoy»).
class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String? trailing;
  final String? delta;
  final AppTone deltaTone;
  final String? detail;
  final Widget? chart;
  final String? actionLabel;
  final VoidCallback? onTap;
  final bool filled;

  /// Más pequeña, para las tarjetas de a dos del celular
  final bool compact;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    this.trailing,
    this.delta,
    this.deltaTone = AppTone.success,
    this.detail,
    this.chart,
    this.actionLabel,
    this.onTap,
    this.filled = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = filled ? c.onAccent : c.ink;
    final fgSoft = filled ? c.onAccent.withValues(alpha: 0.88) : c.inkMuted;
    final radius = BorderRadius.circular(AppRadius.card);
    return Semantics(
      container: true,
      label: '$title: $value',
      child: Material(
        color: filled ? c.accent : c.surface,
        shape: RoundedRectangleBorder(borderRadius: radius, side: filled ? BorderSide.none : BorderSide(color: c.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(compact ? AppSpace.md : AppSpace.lg + 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title,
                          style: (compact ? AppText.small : AppText.body)(context, weight: FontWeight.w600, color: fgSoft)),
                    ),
                    if (trailing != null) Text(trailing!, style: AppText.small(context, weight: FontWeight.w600, color: fgSoft)),
                  ],
                ),
                SizedBox(height: compact ? AppSpace.xs : AppSpace.sm),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  children: [
                    Text(value, style: compact ? AppText.heading(context, color: fg) : AppText.display(context, color: fg)),
                    if (delta != null && !filled) DeltaPill(delta!, tone: deltaTone),
                  ],
                ),
                if (delta != null && filled) ...[
                  const SizedBox(height: AppSpace.xs),
                  Text(delta!, style: AppText.small(context, color: fgSoft)),
                ],
                if (detail != null) ...[
                  const SizedBox(height: AppSpace.xs),
                  Text(detail!, style: AppText.small(context, color: fgSoft)),
                ],
                if (chart != null) ...[
                  const SizedBox(height: AppSpace.md),
                  chart!,
                ],
                if (actionLabel != null) ...[
                  const SizedBox(height: AppSpace.md),
                  Row(
                    children: [
                      Expanded(
                        child: Text(actionLabel!, style: AppText.small(context, weight: FontWeight.w600, color: filled ? fg : c.accent)),
                      ),
                      Icon(Icons.chevron_right_outlined, size: 18, color: filled ? fg : c.inkFaint),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Una fila de «Necesita atención»: ícono con el color del estado, qué pasa, un
/// detalle, la pastilla y una flecha. Al tocarla se abre su panel de solución.
/// [resolved] la pinta en verde («Resuelto»).
class AttentionRow extends StatelessWidget {
  final IconData icon;
  final AppTone tone;
  final String title;
  final String? detail;
  final String pill;
  final VoidCallback? onTap;
  final bool resolved;

  const AttentionRow({
    super.key,
    required this.icon,
    required this.tone,
    required this.title,
    this.detail,
    required this.pill,
    this.onTap,
    this.resolved = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = ToneColors.of(context, resolved ? AppTone.success : tone);
    final radius = BorderRadius.circular(AppRadius.control);
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: c.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 11),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: t.soft, borderRadius: BorderRadius.circular(AppRadius.tile)),
                child: Icon(resolved ? Icons.check_outlined : icon, size: 18, color: t.strong),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppText.body(context, weight: FontWeight.w600)),
                    if (detail != null) Text(detail!, style: AppText.small(context)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              StatusPill(resolved ? 'Resuelto' : pill, tone: resolved ? AppTone.success : tone),
              if (onTap != null) ...[
                const SizedBox(width: AppSpace.xs),
                Icon(Icons.chevron_right_outlined, size: 18, color: c.inkFaint),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
