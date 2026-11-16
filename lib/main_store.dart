import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/services/supabase_service.dart';
import 'core/theme/app_theme.dart';
import 'store_web/store_page.dart';
import 'store_web/clean_url_stub.dart' if (dart.library.js_interop) 'store_web/clean_url_web.dart';
import 'core/l10n/app_locale.dart';
import 'core/services/error_reporter.dart';

/// Tienda pública de un negocio (solo web, en stockealo.online/tienda/<slug>).
/// Es una app aparte y no necesita cuenta.
///   flutter run -d chrome -t lib/main_store.dart --web-browser-flag=--disable-web-security
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Errores al panel de administración (0.16.0, fase 5)
  ErrorReporter.instance.install('tienda');
  // Fechas en español (las pantallas usan DateFormat con 'es_CO')
  await initializeDateFormatting('es_CO', null);
  await SupabaseService.instance.initialize();
  // Se lee la dirección completa ANTES de limpiarla: el producto compartido (?p=) y de
  // dónde llegó (?src=qr) se perderían al dejar solo /tienda/<slug> (0.16.0)
  final uri = Uri.base;
  final slug = slugFromUri(uri);
  final shared = sharedProductFromUri(uri);
  final source = sourceFromUri(uri);
  if (slug != null) showCleanStoreUrl(slug);
  runApp(StoreApp(slug: slug, sharedProductId: shared, source: source));
}

class StoreApp extends StatelessWidget {
  final String? slug;
  final String? sharedProductId;
  final String? source;
  const StoreApp({super.key, this.slug, this.sharedProductId, this.source});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
          locale: AppLocale.locale,
          supportedLocales: AppLocale.supported,
          localizationsDelegates: AppLocale.delegates,
      title: 'Tienda',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: StorePage(slug: slug, sharedProductId: sharedProductId, source: source),
    );
  }
}
