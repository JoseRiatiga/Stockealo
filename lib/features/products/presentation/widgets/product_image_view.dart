import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget placeholder = Container(
      width: width,
      height: height,
      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: iconSize,
              color: isDark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
            ),
            if (placeholderText != null) ...[
              const SizedBox(height: 8),
              Text(
                placeholderText!,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
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
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              width: width,
              height: height,
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFF059669),
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
      final file = File(path);
      if (file.existsSync()) {
        return _wrapRadius(
          Image.file(
            file,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, __, ___) => placeholder,
          ),
        );
      }
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
