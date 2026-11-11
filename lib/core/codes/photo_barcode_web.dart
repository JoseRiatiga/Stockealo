import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:image_picker/image_picker.dart';
import 'package:web/web.dart' as web;

/// Web: el lector de códigos que traen Chrome y Edge (BarcodeDetector)
Future<bool> photoBarcodeAvailable() async => web.window.has('BarcodeDetector');

@JS('BarcodeDetector')
extension type _Detector._(JSObject _) implements JSObject {
  external _Detector();
  external JSPromise<JSArray<_Detected>> detect(web.ImageBitmap image);
}

extension type _Detected._(JSObject _) implements JSObject {
  external String get rawValue;
  external String get format;
}

Future<({String code, String? format})?> readPhotoBarcode(XFile file) async {
  if (!await photoBarcodeAvailable()) return null;
  final bytes = await file.readAsBytes();
  final blob = web.Blob([bytes.toJS].toJS);
  final bitmap = await web.window.createImageBitmap(blob).toDart;
  final found = (await _Detector().detect(bitmap).toDart).toDart;
  if (found.isEmpty) return null;
  final first = found.first;
  return (code: first.rawValue, format: _format(first.format));
}

String? _format(String f) => switch (f) {
      'ean_13' => 'EAN-13',
      'ean_8' => 'EAN-8',
      'upc_a' => 'UPC-A',
      'code_128' => 'Code 128',
      'qr_code' => 'QR',
      _ => null,
    };
