import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/main.dart';

void main() {
  testWidgets('Stockealo smoke test', (WidgetTester tester) async {
    // Verificar que la app carga correctamente
    await tester.pumpWidget(const StockealoApp());
    expect(find.byType(StockealoApp), findsOneWidget);
    // Limpiar árbol de widgets para cancelar timers activos del render
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
