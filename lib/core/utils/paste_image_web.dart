import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

bool get canPasteImages => true;

void Function() listenForPastedImages(void Function(({Uint8List bytes, String mimeType}) image) onImage) {
  void handler(web.ClipboardEvent event) {
    final files = event.clipboardData?.files;
    if (files == null) return;
    for (var i = 0; i < files.length; i++) {
      final file = files.item(i);
      if (file == null || !file.type.startsWith('image/')) continue;
      // Es una imagen: que no termine además como texto dentro de un campo
      event.preventDefault();
      file.arrayBuffer().toDart.then((buffer) {
        onImage((bytes: buffer.toDart.asUint8List(), mimeType: file.type));
      });
      return;
    }
  }

  final listener = ((web.ClipboardEvent e) => handler(e)).toJS;
  web.document.addEventListener('paste', listener);
  return () => web.document.removeEventListener('paste', listener);
}

/// Una imagen arrastrada desde el computador y soltada sobre la ventana
void Function() listenForDroppedImages(void Function(({Uint8List bytes, String mimeType}) image) onImage) {
  // Sin esto el navegador abre la imagen en otra pestaña en vez de dejarla soltar
  final over = ((web.DragEvent e) => e.preventDefault()).toJS;
  final drop = ((web.DragEvent e) {
    e.preventDefault();
    final files = e.dataTransfer?.files;
    if (files == null) return;
    for (var i = 0; i < files.length; i++) {
      final file = files.item(i);
      if (file == null || !file.type.startsWith('image/')) continue;
      file.arrayBuffer().toDart.then((buffer) {
        onImage((bytes: buffer.toDart.asUint8List(), mimeType: file.type));
      });
      return;
    }
  }).toJS;
  web.document.addEventListener('dragover', over);
  web.document.addEventListener('drop', drop);
  return () {
    web.document.removeEventListener('dragover', over);
    web.document.removeEventListener('drop', drop);
  };
}
