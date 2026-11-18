import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/features/home/navigation/app_pane.dart';

/// 0.16.7, decisión E1: en el computador, el detalle se abre a la derecha y el menú
/// sigue a la vista; en el celular se abre como siempre.
void main() {
  late int menuTaps;

  Widget wide(Widget place) => MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              SizedBox(width: 200, child: TextButton(onPressed: () => menuTaps++, child: const Text('Menú Vender'))),
              Expanded(child: AppPaneHost(home: place)),
            ],
          ),
        ),
      );

  setUp(() => menuTaps = 0);

  testWidgets('el detalle se abre en el panel y el menú sigue a la vista y se puede tocar', (tester) async {
    late BuildContext placeContext;
    await tester.pumpWidget(wide(Builder(builder: (c) {
      placeContext = c;
      return const Text('Lugar Productos');
    })));
    expect(AppPane.isOpen, isFalse);

    AppPane.open(placeContext, (_) => const Scaffold(body: Text('Detalle')));
    await tester.pumpAndSettle();
    expect(find.text('Detalle'), findsOneWidget);
    expect(AppPane.depth.value, 1);
    await tester.tap(find.text('Menú Vender'));
    expect(menuTaps, 1, reason: 'el menú sigue funcionando con el panel abierto');

    expect(await AppPane.closeAll(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Detalle'), findsNothing);
    expect(AppPane.depth.value, 0);
  });

  testWidgets('con el panel vacío los toques llegan al lugar de atrás', (tester) async {
    var taps = 0;
    await tester.pumpWidget(wide(Center(child: TextButton(onPressed: () => taps++, child: const Text('Botón del lugar')))));
    await tester.tap(find.text('Botón del lugar'));
    expect(taps, 1);
  });

  testWidgets('una ventana dentro del detalle se cierra sola, sin cerrar el detalle', (tester) async {
    late BuildContext placeContext;
    await tester.pumpWidget(wide(Builder(builder: (c) {
      placeContext = c;
      return const Text('Lugar');
    })));
    AppPane.open(
      placeContext,
      (ctx) => Scaffold(
        body: TextButton(
          onPressed: () => showDialog<void>(
            context: ctx,
            builder: (d) => AlertDialog(content: TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cerrar ventana'))),
          ),
          child: const Text('Abrir ventana'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir ventana'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cerrar ventana'));
    await tester.pumpAndSettle();
    expect(find.text('Abrir ventana'), findsOneWidget, reason: 'el detalle sigue abierto');
    expect(AppPane.depth.value, 1);
    AppPane.clear();
    await tester.pumpAndSettle();
  });

  testWidgets('con cambios sin guardar, ir a otro lugar no cierra la pantalla', (tester) async {
    late BuildContext placeContext;
    await tester.pumpWidget(wide(Builder(builder: (c) {
      placeContext = c;
      return const Text('Lugar');
    })));
    AppPane.open(placeContext, (_) => const PopScope(canPop: false, child: Scaffold(body: Text('Entrada a medias'))));
    await tester.pumpAndSettle();
    expect(await AppPane.closeAll(), isFalse);
    await tester.pumpAndSettle();
    expect(find.text('Entrada a medias'), findsOneWidget);
    AppPane.clear();
    await tester.pumpAndSettle();
    expect(AppPane.depth.value, 0, reason: 'cerrar sin preguntar (cambio de negocio) sí la cierra');
  });

  testWidgets('en el celular (sin panel) se abre como siempre, a pantalla completa', (tester) async {
    late BuildContext placeContext;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      placeContext = c;
      return const Scaffold(body: Text('Lugar'));
    })));
    AppPane.open(placeContext, (_) => const Scaffold(body: Text('Detalle')));
    await tester.pumpAndSettle();
    expect(find.text('Detalle'), findsOneWidget);
    expect(find.text('Lugar'), findsNothing, reason: 'tapa la pantalla, como antes');
    expect(AppPane.depth.value, 0);
  });

  testWidgets('al pasar de computador a celular, lo abierto en el panel no se pierde', (tester) async {
    final hostKey = GlobalKey();
    var wideLayout = true;
    late StateSetter setLayout;
    late BuildContext placeContext;
    Widget host() => AppPaneHost(
          key: hostKey,
          home: Builder(builder: (c) {
            placeContext = c;
            return const Text('Lugar');
          }),
        );
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        setLayout = setState;
        return Scaffold(
          body: wideLayout ? Row(children: [const SizedBox(width: 200), Expanded(child: host())]) : host(),
        );
      }),
    ));
    AppPane.open(placeContext, (_) => const Scaffold(body: Text('Entrada a medias')));
    await tester.pumpAndSettle();
    setLayout(() => wideLayout = false);
    await tester.pumpAndSettle();
    expect(find.text('Entrada a medias'), findsOneWidget);
    expect(AppPane.depth.value, 1);
    AppPane.clear();
    await tester.pumpAndSettle();
  });
}
