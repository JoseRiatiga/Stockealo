import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../auth/presentation/widgets/stocky_mascot.dart';
import 'stocky_assistant_modal.dart';

class StockyFaceButton extends StatelessWidget {
  final String? businessId;
  final VoidCallback? onTap;
  final ValueChanged<int>? onNavigateToTab;
  final bool showLabel;

  const StockyFaceButton({
    super.key,
    this.businessId,
    this.onTap,
    this.onNavigateToTab,
    this.showLabel = false,
  });

  void _handleTap(BuildContext context) {
    HapticFeedback.lightImpact();
    if (onTap != null) {
      onTap!();
    } else {
      StockyAssistantModal.show(
        context,
        businessId: businessId,
        onNavigateToTab: onNavigateToTab,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (showLabel) {
      // Versión Desktop / Tablet extendida tipo pill
      return InkWell(
        onTap: () => _handleTap(context),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1A3C) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF8B5CF6).withOpacity(0.4),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF0F0E1E),
                ),
                child: const Center(
                  child: StockyMascot(size: 20, state: StockyState.idle),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Copiloto Stocky',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8B5CF6),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Versión Móvil Compacta para AppBar Actions (Avatar Circular 36x36)
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Tooltip(
        message: 'Stocky Copiloto - Asistente Comercial',
        child: InkWell(
          onTap: () => _handleTap(context),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? const Color(0xFF1C1838) : const Color(0xFFECFDF5),
              border: Border.all(
                color: const Color(0xFF8B5CF6).withOpacity(0.5),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withOpacity(0.2),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Center(
                  child: StockyMascot(
                    size: 26,
                    state: StockyState.idle,
                  ),
                ),
                // Indicador luminoso "En línea"
                Positioned(
                  right: 1,
                  bottom: 1,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark ? const Color(0xFF1C1838) : Colors.white,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withOpacity(0.8),
                          blurRadius: 4,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
