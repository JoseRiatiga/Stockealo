import 'dart:io' show File;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../../core/theme/app_tokens.dart';

/// Tocar la prenda en la foto del producto y tomar ese color. Funciona igual en el
/// celular y en el computador. Devuelve el color o null si se cancela.
class PhotoColorPicker extends StatefulWidget {
  final String photoPath;
  const PhotoColorPicker({super.key, required this.photoPath});

  static Future<Color?> show(BuildContext context, String photoPath) =>
      showDialog<Color>(context: context, builder: (_) => PhotoColorPicker(photoPath: photoPath));

  /// Promedio de un cuadrito de 5×5 alrededor del punto: un solo píxel puede caer
  /// en una costura o una sombra
  @visibleForTesting
  static Color sampleAround(ByteData rgba, int width, int height, int x, int y, {int radius = 2}) {
    var r = 0, g = 0, b = 0, n = 0;
    for (var dy = -radius; dy <= radius; dy++) {
      for (var dx = -radius; dx <= radius; dx++) {
        final px = (x + dx).clamp(0, width - 1);
        final py = (y + dy).clamp(0, height - 1);
        final i = (py * width + px) * 4;
        r += rgba.getUint8(i);
        g += rgba.getUint8(i + 1);
        b += rgba.getUint8(i + 2);
        n++;
      }
    }
    return Color.fromARGB(255, r ~/ n, g ~/ n, b ~/ n);
  }

  @override
  State<PhotoColorPicker> createState() => _PhotoColorPickerState();
}

class _PhotoColorPickerState extends State<PhotoColorPicker> {
  Uint8List? _bytes;
  ByteData? _pixels;
  int _w = 0, _h = 0;
  String? _error;
  Offset? _tap; // 0..1 dentro de la imagen
  Color? _picked;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Uint8List> _readBytes(String path) async {
    if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('blob:')) {
      final res = await http.get(Uri.parse(path));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      return res.bodyBytes;
    }
    if (kIsWeb) throw Exception('sin archivo');
    final file = path.startsWith('file://') ? File.fromUri(Uri.parse(path)) : File(path);
    return file.readAsBytes();
  }

  Future<void> _load() async {
    try {
      final bytes = await _readBytes(widget.photoPath);
      // Una versión pequeña basta para tomar el color y es rápida en celulares sencillos
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 480);
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _pixels = data;
        _w = frame.image.width;
        _h = frame.image.height;
      });
    } catch (e) {
      debugPrint('Color desde la foto: $e');
      if (mounted) setState(() => _error = 'No pudimos abrir la foto. Revisa tu conexión o elige el color de la paleta.');
    }
  }

  void _onTap(Offset local, Size box) {
    final px = _pixels;
    if (px == null) return;
    final rel = Offset((local.dx / box.width).clamp(0.0, 1.0), (local.dy / box.height).clamp(0.0, 1.0));
    final color = PhotoColorPicker.sampleAround(
      px,
      _w,
      _h,
      (rel.dx * (_w - 1)).round(),
      (rel.dy * (_h - 1)).round(),
    );
    setState(() {
      _tap = rel;
      _picked = color;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget body;
    if (_error != null) {
      body = Text(_error!, style: TextStyle(color: c.inkMuted));
    } else if (_bytes == null) {
      body = const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()));
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Toca la parte de la prenda que tiene el color.',
            style: TextStyle(fontSize: 13, color: c.inkMuted),
          ),
          const SizedBox(height: AppSpace.sm),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
            child: AspectRatio(
              aspectRatio: _w / _h,
              child: LayoutBuilder(builder: (context, box) {
                final size = Size(box.maxWidth, box.maxHeight);
                return GestureDetector(
                  onTapDown: (d) => _onTap(d.localPosition, size),
                  onPanUpdate: (d) => _onTap(d.localPosition, size),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.control),
                          child: Image.memory(_bytes!, fit: BoxFit.fill, gaplessPlayback: true),
                        ),
                      ),
                      if (_tap != null)
                        Positioned(
                          left: _tap!.dx * size.width - 14,
                          top: _tap!.dy * size.height - 14,
                          child: IgnorePointer(
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _picked,
                                border: Border.all(color: Colors.white, width: 3),
                                boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 4)],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      );
    }
    return AlertDialog(
      title: const Text('Color de la foto'),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: body)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _picked == null ? null : () => Navigator.pop(context, _picked),
          child: const Text('Usar este color'),
        ),
      ],
    );
  }
}
