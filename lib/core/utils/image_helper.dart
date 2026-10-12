import 'dart:io';
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

  static Future<String?> _pickAndSaveImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80, // Optimización a ~100-150KB
      );

      if (pickedFile == null) return null;

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
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
