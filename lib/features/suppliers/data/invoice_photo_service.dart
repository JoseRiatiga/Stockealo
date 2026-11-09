import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';
import '../../products/data/product_image_service.dart';

/// Fotos de facturas de proveedores. A diferencia de las fotos de productos, van
/// a un depósito privado: solo el dueño y los administradores del negocio las
/// ven, con enlaces firmados que vencen en minutos.
class InvoicePhotoService {
  InvoicePhotoService._();
  static final instance = InvoicePhotoService._();

  static const bucket = 'purchase-invoices';

  SupabaseClient get _client {
    final client = SupabaseService.instance.client;
    if (client == null || client.auth.currentSession == null) {
      throw const ProductImageException('Necesitas iniciar sesión y tener internet para subir la foto.');
    }
    return client;
  }

  /// Sube la foto y devuelve su ruta en el depósito ("negocio/entrada.jpg")
  Future<String> upload({
    required String businessId,
    required String purchaseId,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    final client = _client;
    if (!await SupabaseService.instance.isCloudSyncEnabled()) {
      throw const ProductImageException(
        'Para guardar la foto de la factura activa la sincronización en Ajustes › Nube y respaldo.',
      );
    }
    if (!await SupabaseService.instance.ensureBusinessInCloud(businessId)) {
      throw const ProductImageException('Tu negocio todavía no está en la nube. Revisa tu conexión e inténtalo de nuevo.');
    }
    final type = ProductImageService.imageTypeOf(bytes) ?? mimeType;
    final ext = switch (type) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/jpeg' => 'jpg',
      _ => throw const ProductImageException('Ese archivo no es una imagen compatible (JPG, PNG o WebP).'),
    };
    if (bytes.length > 6000000) throw const ProductImageException('La imagen pesa más de 6 MB.');
    final path = '$businessId/$purchaseId.$ext';
    try {
      await client.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(upsert: true, contentType: type),
          );
    } catch (e) {
      debugPrint('Subir factura: $e');
      throw const ProductImageException('No se pudo subir la foto. Revisa tu conexión e inténtalo de nuevo.');
    }
    return path;
  }

  /// Enlace temporal para ver la foto (null si no hay conexión o permiso)
  Future<String?> viewUrl(String path) async {
    try {
      return await _client.storage.from(bucket).createSignedUrl(path, 600);
    } catch (e) {
      debugPrint('Ver factura: $e');
      return null;
    }
  }
}
