import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/services/supabase_service.dart';
import 'core/theme/app_theme.dart';
import 'store_web/store_page.dart';

/// Tienda pública de un negocio (solo web, en stockealo.online/tienda/<slug>).
/// Es una app aparte y no necesita cuenta.
///   flutter run -d chrome -t lib/main_store.dart --web-browser-flag=--disable-web-security
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fechas en español (las pantallas usan DateFormat con 'es_CO')
  await initializeDateFormatting('es_CO', null);
  await SupabaseService.instance.initialize();
  runApp(const StoreApp());
}

class StoreApp extends StatelessWidget {
  const StoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tienda',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: StorePage(slug: slugFromUri(Uri.base)),
    );
  }
}
