import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Lo que dice un color en Stockealo. Cada estado tiene el suyo, igual para todos
/// los negocios; el color del negocio ([AppTone.accent]) solo marca lo activo.
enum AppTone { neutral, success, warning, danger, info, accent }

/// Colores de un tono: fondo suave, texto que se lee sobre ese fondo y el color
/// fuerte (puntos, íconos, barras).
class ToneColors {
  final Color soft;
  final Color text;
  final Color strong;

  const ToneColors(this.soft, this.text, this.strong);

  factory ToneColors.of(BuildContext context, AppTone tone) {
    final c = context.colors;
    return switch (tone) {
      AppTone.neutral => ToneColors(c.surfaceMuted, c.inkMuted, c.inkFaint),
      AppTone.success => ToneColors(c.successSoft, c.success, c.success),
      AppTone.warning => ToneColors(c.warningSoft, c.warning, c.warning),
      AppTone.danger => ToneColors(c.dangerSoft, c.danger, c.danger),
      AppTone.info => ToneColors(c.infoSoft, c.info, c.info),
      AppTone.accent => ToneColors(
          Color.alphaBlend(c.accent.withValues(alpha: 0.12), c.surface),
          c.ink,
          c.accent,
        ),
    };
  }
}

/// Pastilla de estado: «● Caja abierta», «Quedan 4», «Sin stock», «Por confirmar».
/// [dot] pone el puntito de color delante; [compact] la hace más baja para filas.
class StatusPill extends StatelessWidget {
  final String label;
  final AppTone tone;
  final bool dot;
  final bool compact;
  final IconData? icon;

  const StatusPill(
    this.label, {
    super.key,
    this.tone = AppTone.neutral,
    this.dot = false,
    this.compact = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final t = ToneColors.of(context, tone);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? AppSpace.sm : 10, vertical: compact ? 2 : AppSpace.xs + 1),
      decoration: BoxDecoration(color: t.soft, borderRadius: BorderRadius.circular(AppRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(width: 7, height: 7, decoration: BoxDecoration(color: t.strong, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ] else if (icon != null) ...[
            Icon(icon, size: 14, color: t.text),
            const SizedBox(width: AppSpace.xs),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption(context, weight: FontWeight.w600, color: t.text),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cambio frente al periodo anterior, al lado de una cifra: «↑ 12 %», «↓ 4 %», «+5».
class DeltaPill extends StatelessWidget {
  final String label;
  final AppTone tone;

  const DeltaPill(this.label, {super.key, this.tone = AppTone.success});

  @override
  Widget build(BuildContext context) {
    final t = ToneColors.of(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: t.soft, borderRadius: BorderRadius.circular(AppRadius.small)),
      child: Text(label, style: AppText.caption(context, weight: FontWeight.w700, color: t.text)),
    );
  }
}

/// Título pequeño en mayúsculas que separa grupos: «DÍA A DÍA», «INVENTARIO».
class SectionLabel extends StatelessWidget {
  final String text;
  final EdgeInsetsGeometry padding;

  const SectionLabel(this.text, {super.key, this.padding = const EdgeInsets.fromLTRB(AppSpace.sm, AppSpace.md, AppSpace.sm, AppSpace.xs)});

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Text(
          text.toUpperCase(),
          style: AppText.caption(context, weight: FontWeight.w700, color: context.colors.inkFaint).copyWith(letterSpacing: 0.8),
        ),
      );
}

/// Mini gráfico de barras de una tarjeta: las barras viejas en gris y las últimas
/// [highlight] en color, para que lo reciente salte a la vista.
class MiniBars extends StatelessWidget {
  final List<double> values;
  final int highlight;
  final Color? color;

  /// Color de las barras viejas (sobre el color del negocio, blanco suave)
  final Color? dimColor;
  final double height;

  const MiniBars({super.key, required this.values, this.highlight = 3, this.color, this.dimColor, this.height = 36});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final max = values.fold<double>(0, (m, v) => v > m ? v : m);
    final strong = color ?? c.accent;
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < values.length; i++) ...[
              if (i > 0) const SizedBox(width: 3),
              Expanded(
                child: FractionallySizedBox(
                  heightFactor: max <= 0 ? 0.04 : (values[i] / max).clamp(0.04, 1.0),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: i >= values.length - highlight ? strong : (dimColor ?? c.line),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
