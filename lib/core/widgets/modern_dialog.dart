import 'package:flutter/material.dart';

class ModernDialog extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final Widget? content;
  final List<Widget>? actions;
  final double maxWidth;
  final bool showCloseButton;

  const ModernDialog({
    super.key,
    this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.content,
    this.actions,
    this.maxWidth = 440.0,
    this.showCloseButton = true,
  });

  static Future<T?> show<T>({
    required BuildContext context,
    IconData? icon,
    Color? iconColor,
    required String title,
    String? subtitle,
    Widget? content,
    List<Widget>? actions,
    double maxWidth = 440.0,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => ModernDialog(
        icon: icon,
        iconColor: iconColor,
        title: title,
        subtitle: subtitle,
        content: content,
        actions: actions,
        maxWidth: maxWidth,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = iconColor ?? const Color(0xFF059669);

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1.5,
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      elevation: 12,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Encabezado con Icono, Título y botón cerrar
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(isDark ? 0.2 : 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: primaryColor.withOpacity(0.3),
                          width: 1.2,
                        ),
                      ),
                      child: Icon(icon, color: primaryColor, size: 24),
                    ),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                            letterSpacing: -0.3,
                          ),
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (showCloseButton)
                    InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                ],
              ),

              // Contenido
              if (content != null) ...[
                const SizedBox(height: 20),
                content!,
              ],

              // Acciones
              if (actions != null && actions!.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ModernConfirmDialog {
  static Future<bool?> show({
    required BuildContext context,
    required String title,
    required String message,
    IconData icon = Icons.help_outline_rounded,
    Color iconColor = const Color(0xFF059669),
    String confirmText = 'Aceptar',
    Color confirmColor = const Color(0xFF059669),
    String cancelText = 'Cancelar',
    bool isDestructive = false,
  }) {
    final effectiveColor = isDestructive ? const Color(0xFFDC2626) : confirmColor;
    final effectiveIcon = isDestructive ? Icons.warning_amber_rounded : icon;

    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return ModernDialog(
          icon: effectiveIcon,
          iconColor: effectiveColor,
          title: title,
          content: Text(
            message,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
            ),
          ),
          actions: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                side: BorderSide(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                cancelText,
                style: TextStyle(
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: effectiveColor,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                confirmText,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
