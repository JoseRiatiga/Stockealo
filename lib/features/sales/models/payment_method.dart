import 'dart:convert';

import 'package:flutter/material.dart';

/// LAS formas de pago de Stockealo. Todo nombre, ícono o lista de formas de pago
/// sale de aquí (Vender, Ventas, Caja, reportes, actividad y comprobantes).
abstract final class PaymentMethod {
  static const cash = 'EFECTIVO';
  static const nequi = 'NEQUI';
  static const transfer = 'TRANSFERENCIA';
  static const card = 'TARJETA';
  static const credit = 'FIADO';

  /// Parte en una forma y parte en otra (no incluye fiado)
  static const mixed = 'MIXTO';

  /// En el orden en que se ofrecen al cobrar
  static const forSale = [cash, nequi, transfer, card, credit, mixed];

  /// Las que se pueden combinar en un pago mixto
  static const forMixed = [cash, nequi, transfer, card];

  static String label(String? code) => switch ((code ?? '').toUpperCase()) {
        cash || '' => 'Efectivo',
        nequi => 'Nequi',
        transfer => 'Transferencia',
        card => 'Tarjeta',
        credit => 'Fiado',
        mixed => 'Mixto',
        final other => other[0] + other.substring(1).toLowerCase(),
      };

  /// En minúscula, para frases («pagó en efectivo», «por transferencia»)
  static String phrase(String? code) => switch ((code ?? '').toUpperCase()) {
        cash || '' => 'en efectivo',
        nequi => 'por Nequi',
        transfer => 'por transferencia',
        card => 'con tarjeta',
        credit => 'fiado',
        mixed => 'en pago mixto',
        final other => other.toLowerCase(),
      };

  static IconData icon(String? code) => switch ((code ?? '').toUpperCase()) {
        nequi => Icons.phone_iphone_outlined,
        transfer => Icons.account_balance_outlined,
        card => Icons.credit_card_outlined,
        credit => Icons.assignment_outlined,
        mixed => Icons.call_split_outlined,
        _ => Icons.payments_outlined,
      };

  /// Cuánto entró por cada medio en un pago mixto, guardado como texto
  static String encodeSplit(Map<String, double> split) =>
      jsonEncode({for (final e in split.entries) if (e.value > 0) e.key: e.value});

  static Map<String, double> decodeSplit(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {for (final e in map.entries) e.key: (e.value as num).toDouble()};
    } catch (_) {
      return const {};
    }
  }

  /// Lo que una venta aportó a cada medio (el mixto se reparte según su detalle)
  static Map<String, double> amounts(String method, double total, String? split) {
    if (method.toUpperCase() != mixed) return {method.toUpperCase(): total};
    final parts = decodeSplit(split);
    return parts.isEmpty ? {mixed: total} : parts;
  }
}
