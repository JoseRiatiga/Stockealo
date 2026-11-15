import 'package:web/web.dart' as web;

/// Dirección limpia de la tienda (0.16.0): el 404 del sitio convierte
/// /tienda/<slug> en /tienda/?t=<slug>; aquí se vuelve a dejar /tienda/<slug> en la
/// barra, sin recargar, para que el cliente copie y comparta la dirección bonita.
void showCleanStoreUrl(String slug) {
  try {
    final loc = web.window.location;
    if (!loc.search.contains('t=')) return;
    web.window.history.replaceState(null, '', '/tienda/$slug${loc.hash}');
  } catch (_) {}
}
