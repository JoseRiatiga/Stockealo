import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/design/app_pagination.dart';
import 'package:stockealo/core/design/glass_surface.dart';
import 'package:stockealo/core/theme/app_theme.dart';

Widget _app(Widget child, {bool disableAnimations = false}) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  group('GlassSurface', () {
    testWidgets('dibuja el cristal con desenfoque', (tester) async {
      await tester.pumpWidget(_app(const GlassSurface(child: Text('Inicio'))));
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('Inicio'), findsOneWidget);
    });

    testWidgets('queda sólida si el sistema pide reducir animaciones', (tester) async {
      await tester.pumpWidget(_app(const GlassSurface(child: Text('Inicio')), disableAnimations: true));
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.text('Inicio'), findsOneWidget);
    });
  });

  group('AppPagination', () {
    testWidgets('no se muestra si todo cabe en una página', (tester) async {
      await tester.pumpWidget(_app(AppPagination(currentPage: 1, totalPages: 1, onPageChanged: (_) {})));
      expect(find.byType(IconButton), findsNothing);
      expect(find.textContaining('Página'), findsNothing);
    });

    testWidgets('la versión compacta muestra la página y avanza', (tester) async {
      int? requested;
      await tester.pumpWidget(_app(AppPagination(
        currentPage: 2,
        totalPages: 3,
        compact: true,
        onPageChanged: (p) => requested = p,
      )));
      expect(find.text('2 / 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Página siguiente'));
      expect(requested, 3);
      await tester.tap(find.byTooltip('Página anterior'));
      expect(requested, 1);
    });

    testWidgets('en la última página no deja avanzar', (tester) async {
      int? requested;
      await tester.pumpWidget(_app(AppPagination(
        currentPage: 3,
        totalPages: 3,
        onPageChanged: (p) => requested = p,
      )));
      expect(find.text('Página 3 de 3'), findsOneWidget);
      await tester.tap(find.text('Siguiente'));
      expect(requested, isNull);
      await tester.tap(find.text('Anterior'));
      expect(requested, 2);
    });
  });
}
