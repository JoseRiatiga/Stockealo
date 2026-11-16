import 'package:flutter/material.dart';

import '../../../core/design/status_pill.dart';
import 'activity_repository.dart';

/// Un movimiento del equipo listo para mostrar en Inicio (0.16.1): título corto, un
/// renglón de detalle, el valor a la derecha y una etiqueta. Sale del texto que ya se
/// guarda, así que sirve también para los movimientos viejos.
///
/// «Ajustó test: M · Negro: 1 → 5, S · Azul: 0 → 5, … (queda 30) · Nuevo lote» queda:
///   título «Ajustó el stock de test» · detalle «M · Negro: 1 → 5, S · Azul: 0 → 5 y 4 más
///   · queda 30» · valor «+29» · etiqueta «Nuevo lote».
class ActivityLine {
  final String title;
  final String? detail;
  final String? value;

  /// El valor es una subida (verde) o una bajada (rojo); null = neutro
  final bool? valueUp;
  final String? tag;
  final IconData icon;
  final AppTone tone;

  const ActivityLine({
    required this.title,
    this.detail,
    this.value,
    this.valueUp,
    this.tag,
    required this.icon,
    required this.tone,
  });

  /// Cuántos elementos de una lista se muestran antes de «y N más»
  static const listShown = 2;

  factory ActivityLine.of(ActivityEntry e) {
    var s = e.summary.trim().replaceAll(RegExp(r'\s+'), ' ');
    final parts = <String>[];
    String? value, tag;
    bool? up;

    // «… (queda 30) · motivo»: el motivo es la etiqueta
    final adjust = e.action == ActivityAction.stockAdjust || e.action == ActivityAction.shrinkage;
    if (adjust) {
      final i = s.lastIndexOf(') · ');
      if (i > 0) {
        tag = s.substring(i + 4).trim();
        s = s.substring(0, i + 1);
      }
    }
    String? left;
    final queda = RegExp(r'\s*\(queda (\d+)\)$').firstMatch(s);
    if (queda != null) {
      left = 'queda ${queda.group(1)}';
      s = s.substring(0, queda.start);
    }

    // «… por $25.000 (mixto)»: el valor a la derecha y la forma de pago en el detalle
    String? method;
    final pay = RegExp(r'\s*\(([a-záéíóúñ ]+)\)$').firstMatch(s);
    if (pay != null && RegExp(r' por \$').hasMatch(s)) {
      method = _capital(pay.group(1)!);
      s = s.substring(0, pay.start);
    }
    final por = RegExp(r' por (\$\s?[\d.,]+)').firstMatch(s);
    if (por != null) {
      value = por.group(1);
      s = (s.substring(0, por.start) + s.substring(por.end)).trim();
    }

    // «Creó test2: $2.000, 10 en stock»
    final created = RegExp(r'^(Creó .+?): (\$\s?[\d.,]+), (.+)$').firstMatch(s);
    String title;
    if (created != null) {
      title = created.group(1)!;
      value ??= created.group(2);
      parts.add(created.group(3)!);
    } else {
      // «Vendió 1 × test (S · Verde)»: la variante va al detalle
      final variant = RegExp(r'^((?:Vendió|Devolvió) \d+ × .+?) \((.+)\)$').firstMatch(s);
      if (variant != null) {
        title = variant.group(1)!;
        parts.add(variant.group(2)!);
      } else {
        final colon = s.indexOf(': ');
        if (colon > 0 && colon <= 48) {
          title = s.substring(0, colon);
          parts.add(_shortList(s.substring(colon + 2)));
        } else {
          title = s;
        }
      }
    }
    if (adjust && title.startsWith('Ajustó ')) title = 'Ajustó el stock de ${title.substring(7)}';
    if (method != null) parts.add(method);
    if (left != null) parts.add(left);

    // El ajuste muestra cuánto subió o bajó
    final diff = e.data?['diff'];
    if (adjust && diff is num && diff != 0) {
      value = diff > 0 ? '+${diff.toInt()}' : '−${diff.abs().toInt()}';
      up = diff > 0;
    }

    final (icon, tone) = _look(e.action);
    return ActivityLine(
      title: title,
      detail: parts.where((p) => p.trim().isNotEmpty).join(' · ').ifEmptyNull,
      value: value,
      valueUp: up,
      tag: tag,
      icon: icon,
      tone: tone,
    );
  }

  /// «a, b, c, d» → «a, b y 2 más» (sin cortar dentro de un elemento)
  static String _shortList(String text) {
    final items = text.split(', ');
    if (items.length <= listShown + 1) return text;
    return '${items.take(listShown).join(', ')} y ${items.length - listShown} más';
  }

  static String _capital(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static (IconData, AppTone) _look(String action) => switch (action) {
        ActivityAction.sale || ActivityAction.serviceSale => (Icons.shopping_cart_outlined, AppTone.success),
        ActivityAction.debtPayment => (Icons.payments_outlined, AppTone.success),
        ActivityAction.saleCancel => (Icons.block_outlined, AppTone.danger),
        ActivityAction.stockAdjust => (Icons.tune_outlined, AppTone.info),
        ActivityAction.shrinkage => (Icons.remove_circle_outline, AppTone.warning),
        ActivityAction.purchase || ActivityAction.supplierChange || ActivityAction.supplierPayment =>
          (Icons.local_shipping_outlined, AppTone.info),
        ActivityAction.priceChange => (Icons.sell_outlined, AppTone.info),
        ActivityAction.cashOpen || ActivityAction.cashClose => (Icons.point_of_sale_outlined, AppTone.accent),
        ActivityAction.staffChange ||
        ActivityAction.memberJoin ||
        ActivityAction.memberAdd ||
        ActivityAction.memberRemove ||
        ActivityAction.roleChange =>
          (Icons.group_outlined, AppTone.neutral),
        ActivityAction.authorize => (Icons.verified_user_outlined, AppTone.accent),
        ActivityAction.goalChange => (Icons.flag_outlined, AppTone.accent),
        _ => (Icons.inventory_2_outlined, AppTone.neutral),
      };
}

extension on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}
