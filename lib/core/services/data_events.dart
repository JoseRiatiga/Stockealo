import 'package:flutter/foundation.dart';

/// Avisa a las pantallas abiertas que cambiaron datos locales.
///
/// Inicio, Inventario y Ventas viven en pestañas que no se cierran: una venta
/// hecha desde una no recargaba las otras, que mostraban stock y totales viejos.
class DataEvents {
  static final DataEvents instance = DataEvents._();
  DataEvents._();

  /// Sube cada vez que se registra o se anula una venta en este dispositivo
  final ValueNotifier<int> salesVersion = ValueNotifier<int>(0);

  void salesChanged() => salesVersion.value++;
}
