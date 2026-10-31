import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/auth/presentation/widgets/stocky_mascot.dart';

void main() {
  testWidgets('la ardilla se dibuja en sus seis estados', (tester) async {
    tester.view.physicalSize = const Size(1240, 1000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(Brightness.light),
      // Sin animaciones: así la imagen sale igual cada vez
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: RepaintBoundary(
          key: key,
          child: Container(
            color: const Color(0xFFF6F3EC),
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final (state, look) in [
                  (StockyState.idle, 0.0),
                  (StockyState.trackingEmail, 1.0),
                  (StockyState.coveringEyes, 0.0),
                  (StockyState.loading, 0.0),
                  (StockyState.success, 0.0),
                  (StockyState.error, 0.0),
                ])
                  StockyMascot(size: 180, state: state, lookProgress: look),
                for (final s in [56.0, 40.0, 28.0]) StockyMascot(size: s),
              ],
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(StockyMascot), findsNWidgets(9));

    final out = Platform.environment['PREVIEW_OUT'];
    if (out != null) {
      await tester.runAsync(() async {
        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File('$out/squirrel_states.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  });
}
