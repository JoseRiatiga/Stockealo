import 'package:flutter/material.dart';
import 'stocky_mascot.dart';

class StockealoSplashScreen extends StatefulWidget {
  final String? statusMessage;

  const StockealoSplashScreen({
    super.key,
    this.statusMessage,
  });

  @override
  State<StockealoSplashScreen> createState() => _StockealoSplashScreenState();
}

class _StockealoSplashScreenState extends State<StockealoSplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _glowAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _glowAnimation = Tween<double>(begin: 0.35, end: 0.85).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _scaleAnimation = Tween<double>(begin: 0.94, end: 1.02).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fadeAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final primaryTextColor = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    final secondaryTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bgColor,
      body: Center(
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, _) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Mascot con resplandor ambiental suave
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Halo de luz verde esmeralda
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF10B981).withOpacity(_glowAnimation.value * (isDark ? 0.35 : 0.2)),
                            blurRadius: 40,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                    ),
                    Transform.scale(
                      scale: _scaleAnimation.value,
                      child: const StockyMascot(
                        size: 96,
                        state: StockyState.idle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // Nombre de la aplicación
                FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    children: [
                      Text(
                        'Stockealo',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.8,
                          color: primaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.statusMessage ?? 'Iniciando sistema de inventario...',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),

                // Barra de carga estilizada y moderna
                SizedBox(
                  width: 160,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      backgroundColor: isDark
                          ? const Color(0xFF1E293B)
                          : const Color(0xFFE2E8F0),
                      valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF059669)),
                      minHeight: 4,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
