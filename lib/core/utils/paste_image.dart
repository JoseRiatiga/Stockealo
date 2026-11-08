import 'dart:typed_data';

import 'paste_image_stub.dart' if (dart.library.js_interop) 'paste_image_web.dart' as impl;

/// Escucha Ctrl+V con una imagen copiada (solo en la web). Devuelve una función para
/// dejar de escuchar. En el celular no hace nada.
typedef PastedImage = ({Uint8List bytes, String mimeType});

void Function() listenForPastedImages(void Function(PastedImage image) onImage) =>
    impl.listenForPastedImages(onImage);

bool get canPasteImages => impl.canPasteImages;
