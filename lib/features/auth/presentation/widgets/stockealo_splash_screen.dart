import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import 'stocky_mascot.dart';

/// Pantalla de espera mientras se abre la sesión o se carga el negocio
class StockealoSplashScreen extends StatefulWidget {
  final String? statusMessage;

  const StockealoSplashScreen({
    super.key,
    this.statusMessage,
  });

  @override
  State<StockealoSplashScreen> createState() => _StockealoSplashScreenState();
}

class _StockealoSplashScreenState extends State<StockealoSplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  late final Animation<double> _pulse = CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Con "reducir animaciones" Stocky se queda quieto
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulseController.stop();
    } else if (!_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.paper,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) => Container(
                width: 132,
                height: 132,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.accent.withOpacity(0.08 + 0.06 * _pulse.value),
                ),
                child: Center(
                  child: Transform.scale(scale: 0.96 + 0.06 * _pulse.value, child: child),
                ),
              ),
              child: const StockyMascot(size: 96, state: StockyState.idle),
            ),
            const SizedBox(height: AppSpace.xl),
            Text(
              'Stockealo',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: c.ink),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              widget.statusMessage ?? 'Preparando tu inventario…',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.inkMuted),
            ),
            const SizedBox(height: AppSpace.xxl),
            SizedBox(
              width: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  backgroundColor: c.surfaceMuted,
                  valueColor: AlwaysStoppedAnimation<Color>(c.accent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
