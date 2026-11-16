import 'package:flutter/material.dart';

/// Cierra las ayudas del mouse al abrir o cerrar una pantalla, ventana u hoja
/// (0.16.3). En la web, si se tocaba algo con su ayuda visible y se abría otra
/// cosa encima, la ayuda se quedaba pegada en la pantalla. Va una sola vez en cada
/// MaterialApp, no botón por botón.
class TooltipCleaner extends NavigatorObserver {
  static void clear() => Tooltip.dismissAllToolTips();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => clear();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => clear();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => clear();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => clear();
}
