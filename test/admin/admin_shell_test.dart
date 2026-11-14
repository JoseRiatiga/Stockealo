import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/admin/admin_shell.dart';
import 'package:stockealo/core/theme/app_theme.dart';

/// Re-diseño del panel admin: menú en grupos como el de la app y barra de arriba con Ctrl K
void main() {
  for (final size in const [Size(1300, 820), Size(390, 820)]) {
    testWidgets('marco del panel a ${size.width.toInt()} px', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: RepaintBoundary(key: key, child: AdminShell(email: 'admin@x.com', onSignOut: () {})),
      ));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      if (size.width >= 900) {
        expect(find.text('OPERACIÓN'), findsOneWidget);
        expect(find.text('INGRESOS'), findsOneWidget);
        expect(find.text('Ctrl K'), findsOneWidget);
      }
      final out = Platform.environment['PREVIEW_OUT'];
      if (out != null) {
        await tester.runAsync(() async {
          final image = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$out/admin_${size.width.toInt()}.png').writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
    });
  }
}
