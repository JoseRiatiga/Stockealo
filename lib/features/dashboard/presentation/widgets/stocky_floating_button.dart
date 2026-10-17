import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../auth/presentation/widgets/stocky_mascot.dart';
import 'stocky_assistant_modal.dart';

/// Modelo de un tip inteligente ofrecido proactivamente por Stocky
class StockyBusinessTip {
  final String emoji;
  final String title;
  final String prompt;

  const StockyBusinessTip({
    required this.emoji,
    required this.title,
    required this.prompt,
  });
}

/// Banco de tips comerciales atractivos
const List<StockyBusinessTip> _kStockyTips = [
  StockyBusinessTip(
    emoji: '⚡',
    title: '¿Venta rápida en caja?',
    prompt: '¿Cómo vender más por impulso en la caja?',
  ),
  StockyBusinessTip(
    emoji: '📦',
    title: '¿Mercadería sin salida?',
    prompt: '¿Cómo liquidar productos que no se venden?',
  ),
  StockyBusinessTip(
    emoji: '💰',
    title: '¿Recuperar fiados rápido?',
    prompt: '¿Cómo recuperar el dinero de los fiados?',
  ),
  StockyBusinessTip(
    emoji: '🎯',
    title: '¿Conoces tu regla 80/20?',
    prompt: '¿Qué es la regla 80/20 en mi negocio?',
  ),
  StockyBusinessTip(
    emoji: '👥',
    title: '¿Cómo retener clientes?',
    prompt: '¿Cómo fidelizar a mis clientes?',
  ),
  StockyBusinessTip(
    emoji: '🏷️',
    title: '¿Precios atractivos?',
    prompt: '¿Cómo fijar precios estratégicos y psicológicos?',
  ),
  StockyBusinessTip(
    emoji: '📈',
    title: '¿Cómo vamos hoy?',
    prompt: '¿Cómo va el negocio?',
  ),
  StockyBusinessTip(
    emoji: '⚠️',
    title: '¿Stock por agotarse?',
    prompt: '¿Qué productos tienen poco stock?',
  ),
];

/// Partícula para la animación de explosión
class _ExplosionParticle {
  final double angle;
  final double maxDistance;
  final double size;
  final Color color;
  final double rotation;
  final bool isStar;
  final double initialOpacity;

  _ExplosionParticle({
    required this.angle,
    required this.maxDistance,
    required this.size,
    required this.color,
    required this.rotation,
    required this.isStar,
    required this.initialOpacity,
  });
}

/// Botón Flotante de Stocky Asistente (Floating Action Widget)
/// Ubicado en la esquina inferior derecha justo encima de la barra de módulos (BottomNav).
/// Muestra esporádicamente una cápsula/bocadillo con un tip comercial.
/// Al tocar el tip, se ejecuta una animación de explosión con partículas y abre el chat.
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
    with TickerProviderStateMixin {
  late final AnimationController _buttonAnimController;
  late final Animation<double> _buttonScaleAnimation;

  // Controlador de entrada/salida de la cápsula de tip
  late final AnimationController _tipAnimController;
  late final Animation<double> _tipScaleAnimation;
  late final Animation<double> _tipFadeAnimation;
  late final Animation<Offset> _tipSlideAnimation;

  // Controlador de flotación suave del bocadillo
  late final AnimationController _floatController;

  // Controlador de la animación de explosión
  late final AnimationController _explosionController;
  List<_ExplosionParticle> _particles = [];

  Timer? _tipTimer;
  Timer? _autoDismissTimer;
  int _currentTipIndex = 0;
  bool _isTipVisible = false;
  bool _isExploding = false;

  @override
  void initState() {
    super.initState();

    // Botón Stocky principal
    _buttonAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
    );
    _buttonScaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _buttonAnimController, curve: Curves.easeInOut),
    );

    // Animación de aparición de la cápsula
    _tipAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _tipScaleAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _tipAnimController, curve: Curves.easeOutBack),
    );
    _tipFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _tipAnimController, curve: Curves.easeOut),
    );
    _tipSlideAnimation = Tween<Offset>(
      begin: const Offset(0.2, 0.0),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _tipAnimController, curve: Curves.easeOutBack),
    );

    // Flotación sutil
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    // Explosión de partículas
    _explosionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    // Iniciar programación esporádica de tips
    _scheduleNextTip(delay: const Duration(seconds: 4));
  }

  @override
  void dispose() {
    _tipTimer?.cancel();
    _autoDismissTimer?.cancel();
    _buttonAnimController.dispose();
    _tipAnimController.dispose();
    _floatController.dispose();
    _explosionController.dispose();
    super.dispose();
  }

  void _scheduleNextTip({required Duration delay}) {
    _tipTimer?.cancel();
    _tipTimer = Timer(delay, () {
      if (!mounted) return;
      _showNextTip();
    });
  }

  void _showNextTip() {
    if (!mounted || _isTipVisible || _isExploding) return;

    setState(() {
      _isTipVisible = true;
      _currentTipIndex = (_currentTipIndex + 1) % _kStockyTips.length;
    });

    _tipAnimController.forward(from: 0.0);

    // Auto-ocultar después de 14 segundos si no se interactúa
    _autoDismissTimer?.cancel();
    _autoDismissTimer = Timer(const Duration(seconds: 14), () {
      _dismissTip();
    });
  }

  Future<void> _dismissTip() async {
    _autoDismissTimer?.cancel();
    if (!_isTipVisible || !mounted) return;

    await _tipAnimController.reverse();
    if (!mounted) return;

    setState(() {
      _isTipVisible = false;
    });

    // Programar la reaparición esporádica (entre 25 y 35 segundos)
    final nextDelaySeconds = 25 + math.Random().nextInt(11);
    _scheduleNextTip(delay: Duration(seconds: nextDelaySeconds));
  }

  void _generateParticles() {
    final random = math.Random();
    final colors = [
      const Color(0xFFFBBF24), // Gold
      const Color(0xFFA855F7), // Purple
      const Color(0xFF10B981), // Emerald
      const Color(0xFF06B6D4), // Cyan
      const Color(0xFFF43F5E), // Coral Pink
      Colors.white,
    ];

    _particles = List.generate(28, (i) {
      final angle = (i * (2 * math.pi / 28)) + (random.nextDouble() - 0.5) * 0.35;
      return _ExplosionParticle(
        angle: angle,
        maxDistance: 45.0 + random.nextDouble() * 60.0,
        size: 3.2 + random.nextDouble() * 4.2,
        color: colors[random.nextInt(colors.length)],
        rotation: random.nextDouble() * math.pi * 2,
        isStar: i % 3 == 0,
        initialOpacity: 0.90 + random.nextDouble() * 0.10,
      );
    });
  }

  Future<void> _handleTipExplosion(StockyBusinessTip tip) async {
    if (_isExploding) return;
    _autoDismissTimer?.cancel();
    _tipTimer?.cancel();

    // Haptic pop fuerte al explotar
    HapticFeedback.heavyImpact();

    _generateParticles();
    setState(() {
      _isExploding = true;
    });

    // Lanzar animación de explosión
    _explosionController.forward(from: 0.0);

    // A los 190ms (en el clímax de la explosión), abrir el modal de Stocky con el tip precargado
    Future.delayed(const Duration(milliseconds: 190), () {
      if (!mounted) return;
      StockyAssistantModal.show(
        context,
        businessId: widget.businessId,
        onNavigateToTab: widget.onNavigateToTab,
        initialPrompt: tip.prompt,
      ).then((_) {
        // Al cerrar el chat, pausar por 35-45s antes del siguiente tip
        _scheduleNextTip(delay: const Duration(seconds: 40));
      });
    });

    // Esperar término de la animación para limpiar estado
    await Future.delayed(const Duration(milliseconds: 440));
    if (mounted) {
      setState(() {
        _isExploding = false;
        _isTipVisible = false;
      });
      _tipAnimController.reset();
    }
  }

  Future<void> _handleButtonTap() async {
    // Si la cápsula está abierta, cerrarla limpiamente
    if (_isTipVisible) {
      _dismissTip();
    }

    HapticFeedback.mediumImpact();
    await _buttonAnimController.forward();
    await _buttonAnimController.reverse();
    if (!mounted) return;

    StockyAssistantModal.show(
      context,
      businessId: widget.businessId,
      onNavigateToTab: widget.onNavigateToTab,
    ).then((_) {
      _scheduleNextTip(delay: const Duration(seconds: 35));
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentTip = _kStockyTips[_currentTipIndex];

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Bocadillo / Cápsula del Tip o Animación de Explosión
        if (_isExploding)
          SizedBox(
            width: 220,
            height: 52,
            child: AnimatedBuilder(
              animation: _explosionController,
              builder: (context, _) {
                return CustomPaint(
                  painter: _ExplosionPainter(
                    progress: _explosionController.value,
                    particles: _particles,
                  ),
                );
              },
            ),
          )
        else if (_isTipVisible)
          SlideTransition(
            position: _tipSlideAnimation,
            child: FadeTransition(
              opacity: _tipFadeAnimation,
              child: ScaleTransition(
                scale: _tipScaleAnimation,
                alignment: Alignment.centerRight,
                child: AnimatedBuilder(
                  animation: _floatController,
                  builder: (context, child) {
                    final floatOffset = math.sin(_floatController.value * math.pi) * 2.0;
                    return Transform.translate(
                      offset: Offset(0, floatOffset),
                      child: child,
                    );
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _handleTipExplosion(currentTip),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          constraints: const BoxConstraints(maxWidth: 225),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: isDark
                                  ? const [Color(0xFF282050), Color(0xFF1B163B)]
                                  : const [Colors.white, Color(0xFFF8FAFC)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF8B5CF6).withOpacity(0.55)
                                  : const Color(0xFFDDD6FE),
                              width: 1.4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF8B5CF6).withOpacity(0.25),
                                blurRadius: 14,
                                offset: const Offset(0, 3),
                                spreadRadius: 0.5,
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Badge de Emoji con brillo
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B5CF6).withOpacity(0.18),
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  currentTip.emoji,
                                  style: const TextStyle(fontSize: 15),
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Textos: Titular y pregunta
                              Flexible(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'TIP DE STOCKY',
                                          style: TextStyle(
                                            fontSize: 8.5,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.4,
                                            color: isDark
                                                ? const Color(0xFFA78BFA)
                                                : const Color(0xFF7C3AED),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '• Toca aquí',
                                          style: TextStyle(
                                            fontSize: 8,
                                            fontWeight: FontWeight.w500,
                                            color: isDark ? Colors.white54 : Colors.black45,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      currentTip.title,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 2),

                              // Botón de descartar 'x'
                              GestureDetector(
                                onTap: _dismissTip,
                                behavior: HitTestBehavior.opaque,
                                child: Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: Icon(
                                    Icons.close,
                                    size: 13,
                                    color: isDark ? Colors.white38 : Colors.black38,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Pequeña flecha/puntero del bocadillo apuntando a la cara de Stocky
                      CustomPaint(
                        size: const Size(6, 10),
                        painter: _SpeechArrowPainter(
                          color: isDark ? const Color(0xFF282050) : Colors.white,
                          borderColor: isDark
                              ? const Color(0xFF8B5CF6).withOpacity(0.55)
                              : const Color(0xFFDDD6FE),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          ),

        const SizedBox(width: 6),

        // Botón Circular Principal con la Cara de Stocky
        ScaleTransition(
          scale: _buttonScaleAnimation,
          child: Tooltip(
            message: 'Stocky',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _handleButtonTap,
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
                      Center(
                        child: ClipOval(
                          child: SizedBox(
                            width: 44,
                            height: 44,
                            child: StockyMascot(
                              size: 40,
                              state: _isExploding
                                  ? StockyState.success
                                  : StockyState.idle,
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
        ),
      ],
    );
  }
}

/// Painter para la pequeña flecha del bocadillo
class _SpeechArrowPainter extends CustomPainter {
  final Color color;
  final Color borderColor;

  _SpeechArrowPainter({required this.color, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..close();

    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SpeechArrowPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.borderColor != borderColor;
}

/// Painter para la animación de explosión con partículas, estrellas y onda expansiva
class _ExplosionPainter extends CustomPainter {
  final double progress;
  final List<_ExplosionParticle> particles;

  _ExplosionPainter({required this.progress, required this.particles});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0 || progress >= 1.0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final opacity = (1.0 - progress).clamp(0.0, 1.0);

    // 1. Onda expansiva exterior
    final ringPaint = Paint()
      ..color = const Color(0xFF8B5CF6).withOpacity(opacity * 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2 * (1.0 - progress);
    canvas.drawCircle(
      center,
      10.0 + 65.0 * Curves.easeOutCubic.transform(progress),
      ringPaint,
    );

    // 2. Onda expansiva interior dorada/verde
    final innerRingPaint = Paint()
      ..color = const Color(0xFF10B981).withOpacity(opacity * 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * (1.0 - progress);
    canvas.drawCircle(
      center,
      6.0 + 42.0 * Curves.easeOutQuad.transform(progress),
      innerRingPaint,
    );

    // 3. Partículas que vuelan en 360 grados
    for (final p in particles) {
      final curveDistance = Curves.easeOutCubic.transform(progress);
      final dist = p.maxDistance * curveDistance;
      final x = center.dx + math.cos(p.angle) * dist;
      final y = center.dy + math.sin(p.angle) * dist;
      final currentSize = p.size * (1.0 - progress * 0.55);
      final pColor = p.color.withOpacity((opacity * p.initialOpacity).clamp(0.0, 1.0));

      final paint = Paint()
        ..color = pColor
        ..style = PaintingStyle.fill;

      if (p.isStar) {
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(p.rotation + progress * math.pi * 2);
        // Dibuja una chispa / estrella de 4 puntas
        final starPath = Path()
          ..moveTo(0, -currentSize * 1.6)
          ..lineTo(currentSize * 0.5, 0)
          ..lineTo(0, currentSize * 1.6)
          ..lineTo(-currentSize * 0.5, 0)
          ..close();
        canvas.drawPath(starPath, paint);
        canvas.restore();
      } else {
        canvas.drawCircle(Offset(x, y), currentSize, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ExplosionPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
