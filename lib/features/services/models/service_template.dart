/// Plantillas por tipo de negocio de servicios (0.12.0).
///
/// Stockealo da la plantilla y el negocio solo elige su tipo: de aquí salen los
/// nombres que se ven en pantalla (cómo se llama cada trabajo, qué dato lo
/// identifica, cómo se llaman los estados) y los servicios de ejemplo. Ninguna
/// pantalla escribe "moto" ni "placa" a mano.
library;

/// Qué dato identifica cada trabajo
enum IdentifierKind { plate, serial, none }

/// Tipo de vehículo de un lavadero (el precio cambia según el tipo)
class VehicleKind {
  final String code;
  final String label;

  const VehicleKind(this.code, this.label);
}

/// Servicio de ejemplo: precio único o un precio por tipo de vehículo
class TemplateExample {
  final String name;
  final int minutes;
  final double commissionPct;

  /// Precio cuando la plantilla no tiene tipos de vehículo
  final double price;

  /// Precio por tipo de vehículo; un tipo que no aparece no se ofrece
  final Map<String, double> prices;

  const TemplateExample(this.name, this.minutes, this.commissionPct, {this.price = 0, this.prices = const {}});
}

class ServiceTemplate {
  final String code;

  /// Nombre del tipo de negocio ("Lavadero de motos y carros")
  final String label;

  /// Cómo se llama cada trabajo ("Vehículo", "Cliente", "Equipo")
  final String unit;
  final String unitPlural;

  /// El trabajo es masculino o femenino ("el vehículo listo", "la orden lista")
  final bool feminine;

  final IdentifierKind identifier;

  /// "En proceso" con el nombre del negocio ("Lavando", "Atendiendo")
  final String inProgress;

  /// Tipos de vehículo (solo el lavadero); vacío = un solo precio
  final List<VehicleKind> vehicleKinds;

  final List<TemplateExample> examples;

  const ServiceTemplate({
    required this.code,
    required this.label,
    required this.unit,
    required this.unitPlural,
    this.feminine = false,
    required this.identifier,
    required this.inProgress,
    this.vehicleKinds = const [],
    this.examples = const [],
  });

  bool get usesIdentifier => identifier != IdentifierKind.none;
  bool get usesVehicleKinds => vehicleKinds.isNotEmpty;

  /// "Placa", "Serial" o null
  String? get identifierLabel => switch (identifier) {
        IdentifierKind.plate => 'Placa',
        IdentifierKind.serial => 'Serial',
        IdentifierKind.none => null,
      };

  String get readyLabel => feminine ? 'Lista' : 'Listo';
  String get deliveredLabel => feminine ? 'Entregada' : 'Entregado';
  String get waitingLabel => 'En espera';

  /// Trabajo con algunos servicios terminados y otros esperando
  String get partialLabel => 'A medias';

  /// "la moto", "la camioneta" pero "el carro"
  static bool vehicleFeminine(String? code) => code == 'MOTO' || code == 'CAMIONETA';

  String vehicleLabel(String? code) =>
      vehicleKinds.firstWhere((k) => k.code == code, orElse: () => VehicleKind(code ?? '', code ?? '')).label;

  // ---------------------------------------------------------------------------
  // Plantillas
  // ---------------------------------------------------------------------------

  static const lavadero = ServiceTemplate(
    code: 'LAVADERO',
    label: 'Lavadero de motos y carros',
    unit: 'Vehículo',
    unitPlural: 'Vehículos',
    identifier: IdentifierKind.plate,
    inProgress: 'Lavando',
    vehicleKinds: [VehicleKind('MOTO', 'Moto'), VehicleKind('CARRO', 'Carro'), VehicleKind('CAMIONETA', 'Camioneta')],
    examples: [
      TemplateExample('Lavado sencillo', 20, 40, prices: {'MOTO': 10000, 'CARRO': 20000, 'CAMIONETA': 25000}),
      TemplateExample('Lavado completo', 35, 40, prices: {'MOTO': 15000, 'CARRO': 30000, 'CAMIONETA': 35000}),
      TemplateExample('Lavado y polichado', 50, 40, prices: {'MOTO': 25000, 'CARRO': 45000, 'CAMIONETA': 55000}),
      TemplateExample('Desengrase de motor', 25, 40, prices: {'MOTO': 12000, 'CARRO': 20000, 'CAMIONETA': 25000}),
      TemplateExample('Lavado de casco', 10, 40, prices: {'MOTO': 5000}),
      TemplateExample('Aspirado', 15, 40, prices: {'CARRO': 8000, 'CAMIONETA': 10000}),
    ],
  );

  static const barberia = ServiceTemplate(
    code: 'BARBERIA',
    label: 'Barbería o peluquería',
    unit: 'Cliente',
    unitPlural: 'Clientes',
    identifier: IdentifierKind.none,
    inProgress: 'Atendiendo',
    examples: [
      TemplateExample('Corte', 30, 50, price: 15000),
      TemplateExample('Corte y barba', 45, 50, price: 22000),
      TemplateExample('Barba', 20, 50, price: 10000),
      TemplateExample('Cejas', 10, 50, price: 5000),
    ],
  );

  static const spa = ServiceTemplate(
    code: 'SPA',
    label: 'Spa o uñas',
    unit: 'Cliente',
    unitPlural: 'Clientes',
    identifier: IdentifierKind.none,
    inProgress: 'Atendiendo',
    examples: [
      TemplateExample('Manicure', 40, 40, price: 15000),
      TemplateExample('Pedicure', 50, 40, price: 18000),
      TemplateExample('Semipermanente', 60, 40, price: 35000),
    ],
  );

  static const taller = ServiceTemplate(
    code: 'TALLER',
    label: 'Taller',
    unit: 'Vehículo',
    unitPlural: 'Vehículos',
    identifier: IdentifierKind.plate,
    inProgress: 'En reparación',
    examples: [
      TemplateExample('Cambio de aceite', 30, 30, price: 15000),
      TemplateExample('Revisión general', 60, 30, price: 30000),
      TemplateExample('Ajuste de frenos', 40, 30, price: 20000),
    ],
  );

  static const tecnico = ServiceTemplate(
    code: 'TECNICO',
    label: 'Servicio técnico',
    unit: 'Equipo',
    unitPlural: 'Equipos',
    identifier: IdentifierKind.serial,
    inProgress: 'En reparación',
    examples: [
      TemplateExample('Diagnóstico', 30, 30, price: 20000),
      TemplateExample('Mantenimiento', 60, 30, price: 40000),
      TemplateExample('Cambio de pantalla', 60, 30, price: 60000),
    ],
  );

  static const lavanderia = ServiceTemplate(
    code: 'LAVANDERIA',
    label: 'Lavandería',
    unit: 'Pedido',
    unitPlural: 'Pedidos',
    identifier: IdentifierKind.none,
    inProgress: 'En proceso',
    examples: [
      TemplateExample('Lavado por kilo', 120, 20, price: 6000),
      TemplateExample('Lavado y planchado', 180, 20, price: 12000),
      TemplateExample('Planchado por prenda', 15, 20, price: 3000),
    ],
  );

  static const otro = ServiceTemplate(
    code: 'OTRO',
    label: 'Otro',
    unit: 'Orden',
    unitPlural: 'Órdenes',
    feminine: true,
    identifier: IdentifierKind.none,
    inProgress: 'En proceso',
  );

  static const all = [lavadero, barberia, spa, taller, tecnico, lavanderia, otro];

  /// Plantilla del negocio. Los códigos de la 0.11.0 siguen funcionando:
  /// "Lavadero de motos" pasó a "Lavadero de motos y carros".
  static ServiceTemplate of(String? code) {
    if (code == 'LAVADERO_MOTOS') return lavadero;
    return all.firstWhere((t) => t.code == code, orElse: () => otro);
  }
}
