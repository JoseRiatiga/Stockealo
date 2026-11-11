import 'package:image_picker/image_picker.dart';

import 'photo_barcode_io.dart' if (dart.library.js_interop) 'photo_barcode_web.dart' as impl;

/// Lee el código de barras (o QR) de una foto. En la web usa el lector que traen
/// Chrome y Edge; en el celular, el de la cámara. En Windows no se puede: ahí se
/// usa el lector USB o se escribe a mano.
class PhotoBarcode {
  PhotoBarcode._();

  /// Se puede leer desde una foto en este equipo
  static Future<bool> get available => impl.photoBarcodeAvailable();

  /// El código encontrado y su formato, o null si no hay ninguno
  static Future<({String code, String? format})?> read(XFile file) => impl.readPhotoBarcode(file);
}
