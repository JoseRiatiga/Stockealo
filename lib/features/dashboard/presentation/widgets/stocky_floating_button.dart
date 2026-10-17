import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../auth/presentation/widgets/stocky_mascot.dart';
import 'stocky_assistant_modal.dart';

/// Botón Flotante de Stocky Copiloto (Floating Action Widget)
/// Ubicado en la esquina inferior derecha justo encima de la barra de módulos (BottomNav)
class StockyFloatingButton extends StatefulWidget {
  final String? businessId;
  final ValueChanged<int>? onNavigateToTab;

  const StockyFloatingButton({
    super.key,
    this.businessId,
    this.onNavigateToTab,
  });

  @override
  State<StockyFloatingButton> createState() => _StockyFloatingButtonState();
}

class _StockyFloatingButtonState extends State<StockyFloatingButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    HapticFeedback.mediumImpact();
    await _animController.forward();
    await _animController.reverse();
    if (!mounted) return;
    StockyAssistantModal.show(
      context,
      businessId: widget.businessId,
      onNavigateToTab: widget.onNavigateToTab,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ScaleTransition(
      scale: _scaleAnimation,
      child: Tooltip(
        message: 'Stocky Copiloto - Asistente Comercial',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _handleTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [Color(0xFF2E2660), Color(0xFF1B163B)]
                      : const [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                ),
                border: Border.all(
                  color: isDark
                      ? const Color(0xFF8B5CF6).withOpacity(0.6)
                      : Colors.white.withOpacity(0.9),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8B5CF6).withOpacity(0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Center(
                    child: ClipOval(
                      child: SizedBox(
                        width: 44,
                        height: 44,
                        child: StockyMascot(
                          size: 40,
                          state: StockyState.idle,
                        ),
                      ),
                    ),
                  ),
                  // Indicador luminoso "En línea"
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark ? const Color(0xFF1B163B) : Colors.white,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withOpacity(0.8),
                            blurRadius: 6,
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
