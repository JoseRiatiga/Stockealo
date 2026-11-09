import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Quita el service worker y lo guardado en caché, y recarga la página para que
/// el navegador descargue la versión publicada
Future<void> clearCacheAndReload() async {
  try {
    final registrations = await web.window.navigator.serviceWorker.getRegistrations().toDart;
    for (final r in registrations.toDart) {
      await r.unregister().toDart;
    }
  } catch (_) {}
  try {
    final keys = await web.window.caches.keys().toDart;
    for (final k in keys.toDart) {
      await web.window.caches.delete(k.toDart).toDart;
    }
  } catch (_) {}
  web.window.location.reload();
}
