import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_tokens.dart';

class ProductImageView extends StatelessWidget {
  final String? imagePath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final double iconSize;
  final String? placeholderText;

  const ProductImageView({
    super.key,
    required this.imagePath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.iconSize = 32,
    this.placeholderText,
  });

  @override
  Widget build(BuildContext context) {

    Widget placeholder = Container(
      width: width,
      height: height,
      color: context.colors.surfaceMuted,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: iconSize,
              color: context.colors.inkFaint,
            ),
            if (placeholderText != null) ...[
              const SizedBox(height: 8),
              Text(
                placeholderText!,
                style: TextStyle(
                  fontSize: AppText.sizeSmall,
                  color: context.colors.inkMuted,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (imagePath == null || imagePath!.trim().isEmpty) {
      return _wrapRadius(placeholder);
    }

    final path = imagePath!.trim();

    // 1. Imagen desde la Nube (URL Web de Supabase Storage) o Blob en Web
    if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('blob:')) {
      return _wrapRadius(
        Image.network(
          path,
          width: width,
          height: height,
          fit: fit,
          gaplessPlayback: true,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              width: width,
              height: height,
              color: context.colors.surfaceMuted,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.colors.accent,
                  ),
                ),
              ),
            );
          },
          errorBuilder: (_, __, ___) => placeholder,
        ),
      );
    }

    // 2. Archivo Local en la memoria del dispositivo (solo en plataformas con sistema de archivos)
    if (!kIsWeb) {
      try {
        final file = path.startsWith('file://')
            ? File.fromUri(Uri.parse(path))
            : File(path);
        if (file.existsSync()) {
          return _wrapRadius(
            Image.file(
              file,
              width: width,
              height: height,
              fit: fit,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => placeholder,
            ),
          );
        }
      } catch (_) {}
    }

    // 3. Fallback si no existe en local ni es URL
    return _wrapRadius(placeholder);
  }

  Widget _wrapRadius(Widget child) {
    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: child);
    }
    return child;
  }
}
