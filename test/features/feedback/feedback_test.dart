import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/feedback/data/feedback_service.dart';
import 'package:stockealo/features/feedback/presentation/feedback_screen.dart';

/// Ajustes › Ayuda › Sugerencias y fallos (0.12.0)
void main() {
  test('cada mensaje se lee de su fila con estado y respuesta', () {
    final f = AppFeedback.fromRow({
      'id': 'f1',
      'user_email': 'ana@x.com',
      'business_name': 'Lavadero Brillo',
      'kind': 'FALLO',
      'area': 'Ventas',
      'message': 'Al cobrar se cerró la app',
      'status': 'RESUELTO',
      'admin_reply': 'Ya quedó arreglado en la 0.12.1',
      'created_at': '2026-11-10T14:00:00Z',
    });
    expect(f.kindLabel, 'Algo no funciona');
    expect(f.statusLabel, 'Resuelto');
    expect(f.adminReply, contains('arreglado'));
  });

  test('cada error del servidor tiene un mensaje claro', () {
    expect(FeedbackService.errorMessage('PostgrestException: too_many_feedback'), contains('10 mensajes'));
    expect(FeedbackService.errorMessage('message_too_short'), contains('al menos 3'));
    expect(FeedbackService.errorMessage('message_too_long'), contains('2000'));
    expect(FeedbackService.errorMessage('timeout'), contains('conexión'));
  });

  for (final width in [360.0, 1200.0]) {
    testWidgets('la pantalla de sugerencias se ve bien a ${width.toInt()} px', (tester) async {
      tester.view.physicalSize = Size(width, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.build(Brightness.light), home: const FeedbackScreen()));
      await tester.pump();
      expect(find.text('Algo no funciona'), findsOneWidget);
      expect(find.text('Tengo una idea'), findsOneWidget);
      expect(find.text('Lo que he enviado'), findsOneWidget);
      await tester.tap(find.text('Tengo una idea'));
      await tester.pump();
      expect(find.text('Qué te gustaría que hiciera Stockealo.'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Todavía no has enviado nada.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
