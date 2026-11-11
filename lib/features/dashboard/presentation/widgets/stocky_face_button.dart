import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../auth/presentation/widgets/stocky_mascot.dart';
import 'stocky_assistant_modal.dart';
import '../../../../core/theme/app_tokens.dart';

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

    if (showLabel) {
      // Versión Desktop / Tablet extendida tipo pill
      return InkWell(
        onTap: () => _handleTap(context),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: context.colors.surfaceMuted,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: context.colors.accent.withValues(alpha: 0.4),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colors.paper,
                ),
                child: const Center(
                  child: StockyMascot(size: 20, state: StockyState.idle),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Stocky',
                style: TextStyle(
                  fontSize: AppText.sizeCaption,
                  fontWeight: FontWeight.w700,
                  color: context.colors.accent,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: context.colors.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Versión Móvil Compacta para AppBar Actions (Avatar Circular 36x36 con 42x42 tap area)
    return Tooltip(
      message: 'Stocky',
      child: InkWell(
        onTap: () => _handleTap(context),
        borderRadius: BorderRadius.circular(22),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.colors.successSoft,
                border: Border.all(
                  color: context.colors.accent.withValues(alpha: 0.6),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: context.colors.accent.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Center(
                    child: ClipOval(
                      child: SizedBox(
                        width: 30,
                        height: 30,
                        child: StockyMascot(
                          size: 28,
                          state: StockyState.idle,
                        ),
                      ),
                    ),
                  ),
                  // Indicador luminoso "En línea"
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: context.colors.accent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: context.colors.surface,
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: context.colors.accent.withValues(alpha: 0.8),
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
      ),
    );
  }
}
