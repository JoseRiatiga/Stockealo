import 'package:flutter/material.dart';

/// Panel de contenido (0.16.7, decisión E1): en el computador, pantallas como el
/// detalle de un producto, Editar producto, Promociones, Entrada de mercancía, la
/// vista previa de la tienda, Equipo y Módulos se abren a la derecha y el menú
/// lateral sigue a la vista. En el celular (sin panel) se abren como siempre.
///
/// Es opcional: solo va al panel lo que se abre con [AppPane.push] u [AppPane.open].
/// Lo que esas pantallas abran adentro con `Navigator.of(context)` también queda en
/// el panel. Ventanas (`showDialog`) siguen en la raíz, sobre toda la app.
class AppPane {
  AppPane._();

  static final navigatorKey = GlobalKey<NavigatorState>(debugLabel: 'panel');

  /// Pantallas abiertas en el panel (0 = se ve el lugar del menú)
  static final depth = ValueNotifier<int>(0);

  static bool get isOpen => depth.value > 0;

  /// Abre [route] en el panel si hay panel; si no, como siempre
  static Future<T?> push<T extends Object?>(BuildContext context, Route<T> route) {
    final pane = navigatorKey.currentState;
    if (pane != null && _fromAppOrPane(context, pane)) return pane.push(route);
    return Navigator.of(context).push(route);
  }

  /// Se abre en el panel solo desde la app principal (el menú y sus lugares) o desde
  /// el mismo panel. Desde otra pantalla completa o una ventana quedaría escondido
  /// detrás: ahí se abre como siempre.
  static bool _fromAppOrPane(BuildContext context, NavigatorState pane) {
    final nav = Navigator.maybeOf(context);
    if (identical(nav, pane)) return true;
    final route = ModalRoute.of(context);
    return route == null || route.isFirst;
  }

  static Future<T?> open<T extends Object?>(BuildContext context, WidgetBuilder builder) =>
      push<T>(context, MaterialPageRoute<T>(builder: builder));

  /// Cierra lo abierto respetando «cambios sin guardar». false = una pantalla pidió
  /// quedarse (por ejemplo, una entrada de mercancía a medias): no se cambia de lugar.
  static Future<bool> closeAll() async {
    final pane = navigatorKey.currentState;
    if (pane == null) return true;
    while (depth.value > 0) {
      final before = depth.value;
      await pane.maybePop();
      if (depth.value >= before) return false;
    }
    return true;
  }

  /// Cierra todo sin preguntar: cambio de negocio, «Ver como», cerrar sesión
  static void clear() => navigatorKey.currentState?.popUntil((r) => r.isFirst);
}

/// Pone el panel sobre [home] (la columna derecha: encabezado y lugar del menú)
class AppPaneHost extends StatefulWidget {
  final Widget home;
  const AppPaneHost({super.key, required this.home});

  @override
  State<AppPaneHost> createState() => _AppPaneHostState();
}

class _AppPaneHostState extends State<AppPaneHost> {
  late final _observer = _DepthObserver();

  @override
  void dispose() {
    // Sin panel (pasó a celular o se cerró la sesión): nada queda contado
    AppPane.depth.value = 0;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Con una pantalla en el panel, el lugar de atrás no recibe el foco (Tab)
        ValueListenableBuilder<int>(
          valueListenable: AppPane.depth,
          builder: (context, d, child) => ExcludeFocus(excluding: d > 0, child: child!),
          child: widget.home,
        ),
        Positioned.fill(
          child: ValueListenableBuilder<int>(
            valueListenable: AppPane.depth,
            // Vacío no se toca: los toques llegan al lugar de atrás
            builder: (context, d, child) => IgnorePointer(
              ignoring: d == 0,
              child: NavigatorPopHandler<Object?>(
                enabled: d > 0,
                // Atrás del sistema (Android en tablet) cierra primero el panel
                onPopWithResult: (_) => AppPane.navigatorKey.currentState?.maybePop(),
                child: child!,
              ),
            ),
            child: LayoutBuilder(
              // Las pantallas del panel miden su ancho, no el de toda la ventana
              builder: (context, box) => MediaQuery(
                data: MediaQuery.of(context).copyWith(size: Size(box.maxWidth, box.maxHeight)),
                child: Navigator(
                  key: AppPane.navigatorKey,
                  observers: [_observer],
                  onGenerateInitialRoutes: (_, __) => [_EmptyRoute()],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// La base del panel: transparente y sin contenido
class _EmptyRoute extends PageRouteBuilder<void> {
  _EmptyRoute()
      : super(
          opaque: false,
          transitionDuration: Duration.zero,
          pageBuilder: (_, __, ___) => const SizedBox.shrink(),
        );
}

/// Cuenta las pantallas del panel (no la base ni ventanas o menús)
class _DepthObserver extends NavigatorObserver {
  static bool _counts(Route<dynamic> r) => r is PageRoute && r is! _EmptyRoute;

  void _add(int delta) => AppPane.depth.value = (AppPane.depth.value + delta).clamp(0, 1 << 20);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_counts(route)) _add(1);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_counts(route)) _add(-1);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_counts(route)) _add(-1);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _add((newRoute != null && _counts(newRoute) ? 1 : 0) - (oldRoute != null && _counts(oldRoute) ? 1 : 0));
  }
}
