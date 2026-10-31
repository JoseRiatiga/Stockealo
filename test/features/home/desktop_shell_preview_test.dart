import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/home/presentation/widgets/app_header_bar.dart';
import 'package:stockealo/features/home/presentation/widgets/app_sidebar_pro.dart';

/// Vista previa de escritorio (solo se guarda si se pasa PREVIEW_OUT)
Future<void> _loadInter() async {
  final loader = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$w.ttf'));
  }
  await loader.load();
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('barra lateral y encabezado de escritorio (${brightness.name})', (tester) async {
      await tester.runAsync(_loadInter);
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final key = GlobalKey();
      final business = Business(id: 'b1', userId: 'u1', name: 'Tienda Olinda', color: '#BE185D', icon: 'mascotas', createdAt: DateTime(2026));
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.build(brightness),
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            body: Row(
              children: [
                AppSidebarPro(
                  selectedIndex: 1,
                  onItemSelected: (_) {},
                  activeBusiness: business,
                  userName: 'Olinda Pérez',
                  userRole: 'OWNER',
                  onSelectBusiness: () {},
                  onLogout: () {},
                ),
                Expanded(
                  child: Column(
                    children: [
                      AppHeaderBar(
                        title: 'Inventario',
                        subtitle: 'Productos, stock y precios',
                        alertCount: 3,
                        onQuickSale: () {},
                        onSearchTap: () {},
                        onNotificationsTap: () {},
                      ),
                      const Expanded(child: SizedBox()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Inventario'), findsWidgets);
      expect(find.text('Tienda Olinda'), findsOneWidget);
      expect(tester.takeException(), isNull);

      final out = Platform.environment['PREVIEW_OUT'];
      if (out != null) {
        await tester.runAsync(() async {
          final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$out/desktop_${brightness.name}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
    });
  }
}
