import 'dart:typed_data';

void Function() listenForPastedImages(void Function(({Uint8List bytes, String mimeType}) image) onImage) => () {};

bool get canPasteImages => false;
