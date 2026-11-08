import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

class ImageHelper {
  static final ImagePicker _picker = ImagePicker();

  /// Captura foto desde la cámara con optimización automática
  static Future<String?> pickFromCamera() async {
    return _pickAndSaveImage(ImageSource.camera);
  }

  /// Selecciona foto desde la galería con optimización automática
  static Future<String?> pickFromGallery() async {
    return _pickAndSaveImage(ImageSource.gallery);
  }

  /// Foto elegida como bytes (la web no tiene archivos locales: se sube a la nube)
  static Future<({Uint8List bytes, String? mimeType})?> pickBytes(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(source: source, maxWidth: 1200, maxHeight: 1200, imageQuality: 82);
      if (picked == null) return null;
      return (bytes: await picked.readAsBytes(), mimeType: picked.mimeType);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _pickAndSaveImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80, // Optimización a ~100-150KB
      );

      if (pickedFile == null) return null;

      // En la Web, las imágenes se manejan mediante Blob URLs sin acceso al sistema de archivos local
      if (kIsWeb) {
        return pickedFile.path;
      }

      // Obtener directorio persistente de la app
      final appDir = await getApplicationDocumentsDirectory();
      final photosDir = Directory(p.join(appDir.path, 'product_photos'));
      if (!await photosDir.exists()) {
        await photosDir.create(recursive: true);
      }

      // Nombre único con UUID y extensión original
      final extension = p.extension(pickedFile.path).isNotEmpty
          ? p.extension(pickedFile.path)
          : '.jpg';
      final fileName = 'prod_${const Uuid().v4()}$extension';
      final savedPath = p.join(photosDir.path, fileName);

      // Copiar archivo al almacenamiento persistente de Stockealo
      final savedFile = await File(pickedFile.path).copy(savedPath);
      return savedFile.path;
    } catch (e) {
      return null;
    }
  }

  /// Eliminar foto si el producto es eliminado
  static Future<void> deleteImage(String? path) async {
    if (path == null || path.isEmpty || kIsWeb) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
