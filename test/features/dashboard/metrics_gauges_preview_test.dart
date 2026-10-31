import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/core/design/segmented_gauge.dart';
import 'package:stockealo/core/theme/app_theme.dart';
import 'package:stockealo/features/dashboard/presentation/widgets/dashboard_metrics_grid.dart';

const _summary = <String, dynamic>{
  'periodTotal': 84000.0,
  'periodProfit': 31500.0,
  'profitMargin': 37.5,
  'averageTicket': 12000.0,
  'totalDebt': 5000.0,
  'periodCount': 7,
  'totalProducts': 15,
  'lowStock': 1,
  'outOfStock': 1,
  'debtCollectedMonth': 7500.0,
  'salesReference': 120000.0,
  'salesReferenceLabel': 'de tu día normal',
};

Future<void> _pump(WidgetTester tester, GlobalKey key, {required double width, bool showProfit = true, Brightness brightness = Brightness.light}) async {
  tester.view.physicalSize = Size(width * 2, 1400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.build(brightness),
    home: Scaffold(
      body: RepaintBoundary(
        key: key,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DashboardMetricsGrid(
            summary: _summary,
            period: 'today',
            showProfit: showProfit,
            onInventoryTap: () {},
          ),
        ),
      ),
    ),
  ));
  await tester.pump(const Duration(seconds: 1));
}

Future<void> _snapshot(WidgetTester tester, GlobalKey key, String name) async {
  final out = Platform.environment['PREVIEW_OUT'];
  if (out == null) return;
  await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$out/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    final loader = FontLoader('Inter');
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(rootBundle.load('assets/fonts/inter/Inter-$w.ttf'));
    }
    await loader.load();
  });

  testWidgets('celular: medidor pequeño y las referencias en el texto', (tester) async {
    final key = GlobalKey();
    await _pump(tester, key, width: 390);
    expect(find.byType(SegmentedGauge), findsNWidgets(4));
    expect(find.text('70% de tu día normal'), findsOneWidget);
    expect(find.text('Cobrado 60% este mes'), findsOneWidget);
    expect(find.text('2 por reponer'), findsOneWidget);
    await _snapshot(tester, key, 'gauges_phone');
  });

  testWidgets('web: medidor grande', (tester) async {
    final key = GlobalKey();
    await _pump(tester, key, width: 1100);
    expect(find.byType(SegmentedGauge), findsNWidgets(4));
    await _snapshot(tester, key, 'gauges_web');
  });

  testWidgets('el cajero no ve el medidor de ganancia', (tester) async {
    final key = GlobalKey();
    await _pump(tester, key, width: 390, showProfit: false, brightness: Brightness.dark);
    expect(find.byType(SegmentedGauge), findsNWidgets(3));
    expect(find.text('••••'), findsOneWidget);
    await _snapshot(tester, key, 'gauges_phone_dark_cashier');
  });
}
