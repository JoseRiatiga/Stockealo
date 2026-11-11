import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Celular (Android e iOS): el mismo lector de la cámara analiza la foto
Future<bool> photoBarcodeAvailable() async => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

Future<({String code, String? format})?> readPhotoBarcode(XFile file) async {
  if (!await photoBarcodeAvailable()) return null;
  final controller = MobileScannerController();
  try {
    final capture = await controller.analyzeImage(file.path);
    final found = capture?.barcodes.where((b) => (b.rawValue ?? '').isNotEmpty).firstOrNull;
    if (found == null) return null;
    return (code: found.rawValue!, format: _format(found.format));
  } finally {
    await controller.dispose();
  }
}

String? _format(BarcodeFormat f) => switch (f) {
      BarcodeFormat.ean13 => 'EAN-13',
      BarcodeFormat.ean8 => 'EAN-8',
      BarcodeFormat.upcA => 'UPC-A',
      BarcodeFormat.code128 => 'Code 128',
      BarcodeFormat.qrCode => 'QR',
      _ => null,
    };
