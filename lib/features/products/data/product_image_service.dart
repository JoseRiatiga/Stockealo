import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/supabase_service.dart';

class ProductImageException implements Exception {
  final String message;
  const ProductImageException(this.message);
  @override
  String toString() => message;
}

/// Fotos de productos guardadas en la nube (Storage, carpeta del negocio).
/// En la web no hay archivos locales: la foto se sube en cuanto se elige o se pega.
class ProductImageService {
  ProductImageService._();
  static final instance = ProductImageService._();

  static const _bucket = 'product-images';

  SupabaseClient get _client {
    final client = SupabaseService.instance.client;
    if (client == null || client.auth.currentSession == null) {
      throw const ProductImageException('Necesitas iniciar sesión y tener internet para subir la foto.');
    }
    return client;
  }

  /// Antes de subir: el negocio tiene que existir en la nube (su carpeta y permisos)
  Future<void> _ensureBusiness(String businessId) async {
    if (!await SupabaseService.instance.isCloudSyncEnabled()) {
      throw const ProductImageException(
        'Para guardar fotos en la nube activa la sincronización en Ajustes › Nube y respaldo.',
      );
    }
    if (!await SupabaseService.instance.ensureBusinessInCloud(businessId)) {
      throw const ProductImageException('Tu negocio todavía no está en la nube. Revisa tu conexión e inténtalo de nuevo.');
    }
  }

  /// Sube una foto (elegida o pegada) y devuelve su dirección pública
  Future<String> uploadBytes({
    required String businessId,
    required String productId,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    final client = _client;
    await _ensureBusiness(businessId);
    final type = imageTypeOf(bytes) ?? mimeType;
    final ext = switch (type) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      'image/jpeg' => 'jpg',
      _ => throw const ProductImageException('Ese archivo no es una imagen compatible (JPG, PNG, WebP o GIF).'),
    };
    if (bytes.length > 6000000) throw const ProductImageException('La imagen pesa más de 6 MB.');
    final path = '$businessId/$productId.$ext';
    try {
      await client.storage.from(_bucket).uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(upsert: true, contentType: type),
          );
    } catch (e) {
      debugPrint('Subir foto: $e');
      throw const ProductImageException('No se pudo subir la foto. Revisa tu conexión e inténtalo de nuevo.');
    }
    final url = client.storage.from(_bucket).getPublicUrl(path);
    return '$url?t=${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Trae la foto desde un enlace (página del producto o imagen) y devuelve su dirección
  Future<String> importFromUrl({
    required String businessId,
    required String productId,
    required String url,
  }) async {
    final link = normalizeLink(url);
    if (link == null) throw const ProductImageException('Pega un enlace completo, que empiece por https://');
    final client = _client;
    await _ensureBusiness(businessId);
    await SupabaseService.instance.ensureFreshSession();
    try {
      final res = await client.functions.invoke(
        'product-image',
        body: {'business_id': businessId, 'product_id': productId, 'url': link},
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      final imageUrl = data['url'] as String?;
      if (imageUrl == null) throw const ProductImageException('No pudimos traer la foto de esa página.');
      return imageUrl;
    } on FunctionException catch (e) {
      final details = e.details is Map ? e.details as Map : const {};
      final code = details['error']?.toString() ?? '${e.details}';
      throw ProductImageException(errorMessage(code, store: details['store']?.toString()));
    } on ProductImageException {
      rethrow;
    } catch (e) {
      debugPrint('Foto desde enlace: $e');
      throw const ProductImageException('No pudimos traer la foto. Revisa tu conexión e inténtalo de nuevo.');
    }
  }

  /// Toma el enlace aunque venga dentro de un texto ("Mira esto: https://…")
  @visibleForTesting
  static String? normalizeLink(String raw) {
    final m = RegExp(r'https?://[^\s<>"]+', caseSensitive: false).firstMatch(raw.trim());
    if (m == null) return null;
    final uri = Uri.tryParse(m[0]!);
    if (uri == null || uri.host.isEmpty) return null;
    return uri.toString();
  }

  @visibleForTesting
  static String errorMessage(String code, {String? store}) => switch (code) {
        // La tienda pide "demuestra que no eres un robot": no se puede ni se debe saltar
        'store_blocked' => '${store ?? 'Esa tienda'} no deja que otros programas lean sus páginas. '
            'En el computador, recorta la foto con Windows + Shift + S y pégala aquí con Ctrl+V. '
            'En el celular, toma una captura de pantalla y súbela desde la galería.',
        'no_image' => 'Esa página no muestra una foto que podamos traer. Abre la imagen, copia su dirección '
            'y pégala, o guárdala y súbela desde la galería.',
        'fetch_failed' || 'blocked' => 'No pudimos abrir esa página: algunas tiendas no dejan que otros programas '
            'la lean. Copia la imagen y pégala, o guárdala y súbela desde la galería.',
        'too_large' => 'Esa imagen es demasiado pesada (más de 6 MB).',
        'unsupported_type' => 'Ese enlace no lleva a una imagen compatible (JPG, PNG, WebP o GIF).',
        'invalid_url' => 'Ese enlace no es válido. Debe empezar por https://',
        'daily_limit' => 'Llegaste al límite de fotos desde enlaces por hoy. Mañana puedes traer más.',
        'not_allowed' => 'Solo el dueño o un administrador pueden cambiar las fotos de los productos.',
        _ => 'No pudimos traer la foto. Inténtalo de nuevo.',
      };

  /// Tipo real de la imagen por sus primeros bytes; null si no es una imagen compatible
  @visibleForTesting
  static String? imageTypeOf(Uint8List b) {
    if (b.length < 12) return null;
    if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'image/jpeg';
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'image/gif';
    if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
      return 'image/webp';
    }
    return null;
  }
}
