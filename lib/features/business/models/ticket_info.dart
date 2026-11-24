import 'dart:convert';

import 'business.dart';

/// Lo que el negocio pone en sus tiquetes (0.15.0): NIT, dirección, teléfono y su
/// propia despedida. Se guarda en [Business.ticketInfo] como texto JSON.
class TicketInfo {
  final String? taxId;
  final String? address;
  final String? phone;

  /// Despedida propia, en lugar de «¡Gracias por tu compra!»
  final String? footer;

  const TicketInfo({this.taxId, this.address, this.phone, this.footer});

  static const empty = TicketInfo();

  /// Despedidas de siempre que la propia reemplaza; las de otros tiquetes (cierre de
  /// caja, cotización, orden de servicio) se quedan porque dicen algo útil
  static const genericClosings = {'¡Gracias por tu compra!', '¡Muchas gracias por tu pago!'};

  bool get isEmpty => taxId == null && address == null && phone == null && footer == null;

  static String? _clean(Object? v) {
    final t = '${v ?? ''}'.trim();
    return t.isEmpty ? null : t;
  }

  static TicketInfo of(Business? business) => decode(business?.ticketInfo);

  static TicketInfo decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return empty;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return TicketInfo(
        taxId: _clean(m['tax_id']),
        address: _clean(m['address']),
        phone: _clean(m['phone']),
        footer: _clean(m['footer']),
      );
    } catch (_) {
      return empty;
    }
  }

  /// null si no hay nada (el negocio vuelve al tiquete de siempre)
  String? encode() => isEmpty
      ? null
      : jsonEncode({
          if (taxId != null) 'tax_id': taxId,
          if (address != null) 'address': address,
          if (phone != null) 'phone': phone,
          if (footer != null) 'footer': footer,
        });

  /// Las líneas debajo del nombre del negocio: «NIT 900.123.456-7», la dirección y el teléfono
  List<String> get headerLines => [
        if (taxId != null) 'NIT $taxId',
        if (address != null) address!,
        if (phone != null) 'Tel. $phone',
      ];

  /// La despedida del tiquete: la propia si la hay y el tiquete trae una de las de siempre
  String closingFor(String docClosing) =>
      footer != null && genericClosings.contains(docClosing) ? footer! : docClosing;
}

/// La sede en el tiquete (0.18.1): solo cuando el negocio tiene sedes. Con dirección y
/// teléfono propios, reemplazan los del negocio en ese tiquete.
class TicketBranch {
  final String name;
  final String? address;
  final String? phone;
  const TicketBranch(this.name, {this.address, this.phone});

  /// [info] con la dirección y el teléfono de la sede, si los tiene
  TicketInfo over(TicketInfo info) => TicketInfo(
        taxId: info.taxId,
        address: (address ?? '').trim().isEmpty ? info.address : address!.trim(),
        phone: (phone ?? '').trim().isEmpty ? info.phone : phone!.trim(),
        footer: info.footer,
      );
}
