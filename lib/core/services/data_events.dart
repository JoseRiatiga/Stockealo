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

  /// Sube cada vez que se abre o se cierra la caja (la pastilla del encabezado la escucha)
  final ValueNotifier<int> cashVersion = ValueNotifier<int>(0);

  void cashChanged() => cashVersion.value++;

  /// Sube cada vez que cambia un producto, su stock o una categoría (0.16.4).
  /// Antes Vender, Inicio y Stock seguían con el nombre, precio o stock viejos
  /// hasta recargar la página.
  final ValueNotifier<int> productsVersion = ValueNotifier<int>(0);

  void productsChanged() => productsVersion.value++;

  /// Sube cada vez que cambia un cliente o su deuda: abonos y fiados (0.16.4)
  final ValueNotifier<int> customersVersion = ValueNotifier<int>(0);

  void customersChanged() => customersVersion.value++;
}
