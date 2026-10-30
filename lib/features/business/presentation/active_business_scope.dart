import 'package:flutter/widgets.dart';
import '../data/business_repository.dart';
import '../models/business.dart';

/// Punto único de acceso al negocio activo desde la interfaz.
///
/// Se monta una vez sobre toda la app (MaterialApp.builder) y expone el
/// notificador de [BusinessRepository], que sigue siendo la fuente de verdad.
class ActiveBusinessScope extends InheritedNotifier<ValueNotifier<Business?>> {
  ActiveBusinessScope({super.key, required super.child})
      : super(notifier: BusinessRepository.instance.activeBusinessNotifier);

  /// Negocio activo; el widget que lo lee se reconstruye cuando cambia.
  static Business? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ActiveBusinessScope>()?.notifier?.value;

  /// Lectura puntual (callbacks, initState), sin reconstruir al cambiar.
  static Business? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ActiveBusinessScope>()?.notifier?.value ??
      BusinessRepository.instance.currentActiveBusiness;
}

/// Para pantallas que recargan sus datos cuando se cambia de negocio.
mixin ActiveBusinessAware<T extends StatefulWidget> on State<T> {
  /// Se llama cada vez que cambia el negocio activo
  void onActiveBusinessChanged();

  @override
  void initState() {
    super.initState();
    BusinessRepository.instance.activeBusinessNotifier.addListener(_handleActiveBusinessChange);
  }

  @override
  void dispose() {
    BusinessRepository.instance.activeBusinessNotifier.removeListener(_handleActiveBusinessChange);
    super.dispose();
  }

  void _handleActiveBusinessChange() {
    if (mounted) onActiveBusinessChanged();
  }
}
