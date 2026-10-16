import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ImageSourcePickerModal extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool hasExistingImage;
  final Function(ImageSource source) onSelected;
  final VoidCallback? onRemove;
  final bool isDialog;

  const ImageSourcePickerModal({
    super.key,
    required this.title,
    this.subtitle,
    this.hasExistingImage = false,
    required this.onSelected,
    this.onRemove,
    this.isDialog = false,
  });

  static Future<void> show(
    BuildContext context, {
    String title = 'Foto de Perfil',
    String subtitle = 'Selecciona el origen de la imagen',
    bool hasExistingImage = false,
    required Function(ImageSource source) onSelected,
    VoidCallback? onRemove,
  }) {
    final isDesktop = MediaQuery.of(context).size.width >= 850;

    if (isDesktop) {
      return showDialog(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: ImageSourcePickerModal(
                title: title,
                subtitle: subtitle,
                hasExistingImage: hasExistingImage,
                onSelected: onSelected,
                onRemove: onRemove,
                isDialog: true,
              ),
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ImageSourcePickerModal(
        title: title,
        subtitle: subtitle,
        hasExistingImage: hasExistingImage,
        onSelected: onSelected,
        onRemove: onRemove,
        isDialog: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF131126) : Colors.white;
    final borderColor = isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0);
    final cardBg = isDark ? const Color(0xFF18152F) : const Color(0xFFF8FAFC);
    final textMain = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final textMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        isDialog ? 24 : MediaQuery.of(context).padding.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: isDialog
            ? BorderRadius.circular(24)
            : const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.4 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isDialog)
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF332D5C) : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

          // Cabecera
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                      color: textMain,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 12.5, color: textMuted),
                    ),
                  ],
                ],
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded, color: textMuted, size: 20),
                splashRadius: 18,
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Tarjeta: Cámara
          _buildOptionCard(
            context: context,
            icon: Icons.camera_alt_rounded,
            iconGradient: const [Color(0xFF059669), Color(0xFF10B981)],
            title: 'Tomar foto con la cámara',
            subtitle: 'Usa la cámara del dispositivo en tiempo real',
            cardBg: cardBg,
            borderColor: borderColor,
            textMain: textMain,
            textMuted: textMuted,
            onTap: () {
              Navigator.pop(context);
              onSelected(ImageSource.camera);
            },
          ),
          const SizedBox(height: 12),

          // Tarjeta: Galería
          _buildOptionCard(
            context: context,
            icon: Icons.photo_library_rounded,
            iconGradient: const [Color(0xFF7C3AED), Color(0xFF8B5CF6)],
            title: 'Elegir de la galería',
            subtitle: 'Selecciona una foto almacenada en este equipo',
            cardBg: cardBg,
            borderColor: borderColor,
            textMain: textMain,
            textMuted: textMuted,
            onTap: () {
              Navigator.pop(context);
              onSelected(ImageSource.gallery);
            },
          ),

          // Opción Eliminar Foto
          if (hasExistingImage && onRemove != null) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: () {
                Navigator.pop(context);
                onRemove!();
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(isDark ? 0.1 : 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Quitar foto actual',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Se restablecerá la imagen predeterminada',
                            style: TextStyle(fontSize: 11.5, color: Colors.redAccent),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionCard({
    required BuildContext context,
    required IconData icon,
    required List<Color> iconGradient,
    required String title,
    required String subtitle,
    required Color cardBg,
    required Color borderColor,
    required Color textMain,
    required Color textMuted,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 1.1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: iconGradient),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: iconGradient.first.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                      color: textMain,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11.5, color: textMuted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
