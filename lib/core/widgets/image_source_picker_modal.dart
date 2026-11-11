import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_tokens.dart';

class ImageSourcePickerModal extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool hasExistingImage;
  final Function(ImageSource source) onSelected;
  final VoidCallback? onRemove;
  final bool isDialog;

  /// Si se pasa, agrega "Traer la foto desde un enlace" (página del producto o imagen)
  final VoidCallback? onLink;

  /// Nota al pie, por ejemplo "también puedes pegar una imagen con Ctrl+V"
  final String? footerHint;

  const ImageSourcePickerModal({
    super.key,
    required this.title,
    this.subtitle,
    this.hasExistingImage = false,
    required this.onSelected,
    this.onRemove,
    this.isDialog = false,
    this.onLink,
    this.footerHint,
  });

  static Future<void> show(
    BuildContext context, {
    String title = 'Foto de Perfil',
    String subtitle = 'Selecciona el origen de la imagen',
    bool hasExistingImage = false,
    required Function(ImageSource source) onSelected,
    VoidCallback? onRemove,
    VoidCallback? onLink,
    String? footerHint,
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
                onLink: onLink,
                footerHint: footerHint,
                isDialog: true,
              ),
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet(
      showDragHandle: false,
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
        onLink: onLink,
        footerHint: footerHint,
        isDialog: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.xl,
        isDialog ? AppSpace.xl : MediaQuery.of(context).padding.bottom + AppSpace.lg,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: isDialog
            ? BorderRadius.circular(AppRadius.sheet)
            : const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
        border: Border.all(color: c.line),
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
                margin: const EdgeInsets.only(bottom: AppSpace.lg),
                decoration: BoxDecoration(color: c.lineStrong, borderRadius: BorderRadius.circular(2)),
              ),
            ),

          // Cabecera
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.ink)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(subtitle!, style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close_rounded, color: c.inkMuted, size: 20),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),

          _option(
            context,
            icon: Icons.photo_camera_outlined,
            title: 'Tomar foto con la cámara',
            subtitle: 'Usa la cámara del dispositivo',
            onTap: () {
              Navigator.pop(context);
              onSelected(ImageSource.camera);
            },
          ),
          const SizedBox(height: AppSpace.sm),
          _option(
            context,
            icon: Icons.photo_library_outlined,
            title: 'Elegir de la galería',
            subtitle: 'Una foto guardada en este equipo',
            onTap: () {
              Navigator.pop(context);
              onSelected(ImageSource.gallery);
            },
          ),
          if (onLink != null) ...[
            const SizedBox(height: AppSpace.sm),
            _option(
              context,
              icon: Icons.link_rounded,
              title: 'Traer la foto desde un enlace',
              subtitle: 'Pega el enlace del producto (Shein, Temu, Mercado Libre…) o de la imagen',
              onTap: () {
                Navigator.pop(context);
                onLink!();
              },
            ),
          ],
          if (footerHint != null) ...[
            const SizedBox(height: AppSpace.md),
            Text(footerHint!, style: TextStyle(fontSize: 12, color: c.inkMuted)),
          ],
          if (hasExistingImage && onRemove != null) ...[
            const SizedBox(height: AppSpace.sm),
            _option(
              context,
              icon: Icons.delete_outline_rounded,
              title: 'Quitar la imagen actual',
              subtitle: 'Vuelve a la imagen predeterminada',
              danger: true,
              onTap: () {
                Navigator.pop(context);
                onRemove!();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _option(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final c = context.colors;
    final fg = danger ? c.danger : c.accent;
    return Material(
      color: danger ? c.dangerSoft : c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: danger ? c.danger.withValues(alpha: 0.25) : c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: danger ? c.surface : c.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Icon(icon, color: fg, size: 22),
              ),
              const SizedBox(width: AppSpace.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: danger ? c.danger : c.ink)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: c.inkMuted)),
                  ],
                ),
              ),
              if (!danger) Icon(Icons.chevron_right_rounded, color: c.inkFaint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
