import 'package:web/web.dart' as web;

/// Dirección limpia de la tienda (0.16.0): el 404 del sitio convierte
/// /tienda/<slug> en /tienda/?t=<slug>; aquí se vuelve a dejar /tienda/<slug> en la
/// barra, sin recargar, para que el cliente copie y comparta la dirección bonita.
/// Primera vez en esta visita (fase 4): la pestaña recuerda lo ya contado y una
/// recarga no vuelve a sumar
bool firstTimeThisVisit(String key) {
  try {
    final store = web.window.sessionStorage;
    if (store.getItem(key) != null) return false;
    store.setItem(key, '1');
    return true;
  } catch (_) {
    return true;
  }
}

void showCleanStoreUrl(String slug) {
  try {
    final loc = web.window.location;
    if (!loc.search.contains('t=')) return;
    web.window.history.replaceState(null, '', '/tienda/$slug${loc.hash}');
  } catch (_) {}
}

/// La sede que eligió quien compra (0.18.3): se recuerda en este navegador
String? savedStoreBranch(String slug) {
  try {
    return web.window.localStorage.getItem('store_branch_$slug');
  } catch (_) {
    return null;
  }
}

void saveStoreBranch(String slug, String branchId) {
  try {
    web.window.localStorage.setItem('store_branch_$slug', branchId);
  } catch (_) {}
}
