import 'package:flutter/material.dart';

import 'core/services/supabase_service.dart';
import 'core/theme/app_theme.dart';
import 'store_web/store_page.dart';

/// Tienda pública de un negocio (solo web, en stockealo.online/tienda/<slug>).
/// Es una app aparte y no necesita cuenta.
///   flutter run -d chrome -t lib/main_store.dart --web-browser-flag=--disable-web-security
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
