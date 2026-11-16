import 'dart:typed_data';

import 'paste_image_stub.dart' if (dart.library.js_interop) 'paste_image_web.dart' as impl;

/// Escucha Ctrl+V con una imagen copiada, o una imagen arrastrada a la ventana (solo
/// en la web). Devuelve una función para dejar de escuchar. En el celular no hace nada.
///
/// Si dos pantallas escuchan a la vez (la ficha del producto y, encima, el lector de
/// códigos), la imagen le llega solo a la última que empezó a escuchar: la que se ve.
typedef PastedImage = ({Uint8List bytes, String mimeType});

final _listeners = <void Function(PastedImage image)>[];

void Function() _listen(
  void Function(PastedImage image) onImage,
  void Function() Function(void Function(PastedImage image) onImage) source,
) {
  void handler(PastedImage image) {
    if (_listeners.isNotEmpty && identical(_listeners.last, handler)) onImage(image);
  }

  _listeners.add(handler);
  final stop = source(handler);
  return () {
    _listeners.remove(handler);
    stop();
  };
}

void Function() listenForPastedImages(void Function(PastedImage image) onImage) =>
    _listen(onImage, impl.listenForPastedImages);

/// Pegar con Ctrl+V y además soltar una imagen arrastrada (0.16.0, lector de códigos)
void Function() listenForPastedOrDroppedImages(void Function(PastedImage image) onImage) => _listen(onImage, (h) {
      final a = impl.listenForPastedImages(h), b = impl.listenForDroppedImages(h);
      return () {
        a();
        b();
      };
    });

bool get canPasteImages => impl.canPasteImages;
