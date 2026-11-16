import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// Toma una foto de lo que se ve dentro de un RepaintBoundary (0.16.0, fase 3)
Future<XFile> captureBoundary(GlobalKey key, {required String name, double pixelRatio = 3}) async {
  final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) throw StateError('No se pudo dibujar la imagen.');
  final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) throw StateError('No se pudo crear la imagen.');
  return XFile.fromData(data.buffer.asUint8List(), mimeType: 'image/png', name: name);
}

/// Abre el menú de compartir del celular (Instagram, WhatsApp, guardar…) con una o
/// varias imágenes. En la web las descarga. Funciona igual en Android, iPhone y web.
Future<void> shareImages(List<GlobalKey> keys, {required String baseName, String? text}) async {
  final clean = baseName.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
  final files = [
    for (var i = 0; i < keys.length; i++) await captureBoundary(keys[i], name: keys.length == 1 ? '$clean.png' : '${clean}_${i + 1}.png'),
  ];
  await Share.shareXFiles(files, text: text);
}
