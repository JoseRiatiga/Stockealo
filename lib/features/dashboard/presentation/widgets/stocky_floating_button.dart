import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/theme/stocky_palette.dart';
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

  // Los consejos tapaban la lista y se llevaban los toques: salen pocas veces,
  // duran poco y se cierran al tocar en cualquier otra parte
  static const _firstTipDelay = Duration(seconds: 45);
  static const _tipVisibleFor = Duration(seconds: 8);
  static const _maxTipsPerSession = 3;
  static int _tipsShownThisSession = 0;

  /// Entre 3 y 5 minutos hasta el siguiente consejo
  Duration get _nextTipDelay => Duration(seconds: 180 + math.Random().nextInt(121));
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
    _scheduleNextTip(delay: _firstTipDelay);
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
    if (_tipsShownThisSession >= _maxTipsPerSession) return;
    _tipTimer = Timer(delay, () {
      if (!mounted) return;
      _showNextTip();
    });
  }

  void _showNextTip() {
    if (!mounted || _isTipVisible || _isExploding) return;

    _tipsShownThisSession++;
    setState(() {
      _isTipVisible = true;
      _currentTipIndex = (_currentTipIndex + 1) % _kStockyTips.length;
    });

    _tipAnimController.forward(from: 0.0);

    // Auto-ocultar si no se interactúa
    _autoDismissTimer?.cancel();
    _autoDismissTimer = Timer(_tipVisibleFor, () {
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

    _scheduleNextTip(delay: _nextTipDelay);
  }

  void _generateParticles() {
    final random = math.Random();
    // Los colores de Stocky: dorado, verdes del delantal, canela y rubor
    const colors = [
      StockyPalette.sparkleGold,
      StockyPalette.sparkleGreen,
      StockyPalette.printShade,
      StockyPalette.fur,
      StockyPalette.blush,
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
        _scheduleNextTip(delay: _nextTipDelay);
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
      _scheduleNextTip(delay: _nextTipDelay);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final currentTip = _kStockyTips[_currentTipIndex];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Consejo de Stocky (o la explosión al tocarlo), encima de la pastilla
        if (_isExploding)
          SizedBox(
            width: 220,
            height: 52,
            child: AnimatedBuilder(
              animation: _explosionController,
              builder: (context, _) => CustomPaint(
                painter: _ExplosionPainter(
                  progress: _explosionController.value,
                  particles: _particles,
                  glow: c.accent,
                ),
              ),
            ),
          )
        else if (_isTipVisible)
          SlideTransition(
            position: _tipSlideAnimation,
            child: FadeTransition(
              opacity: _tipFadeAnimation,
              child: ScaleTransition(
                scale: _tipScaleAnimation,
                alignment: Alignment.bottomRight,
                child: AnimatedBuilder(
                  animation: _floatController,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(0, math.sin(_floatController.value * math.pi) * 2.0),
                    child: child,
                  ),
                  // Tocar o deslizar fuera del consejo lo cierra; el toque sigue a su destino
                  child: TapRegion(
                    onTapOutside: (_) => _dismissTip(),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _handleTipExplosion(currentTip),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 250),
                        margin: const EdgeInsets.only(bottom: AppSpace.sm),
                        padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.sm),
                        decoration: BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(AppRadius.card),
                          border: Border.all(color: c.line),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(currentTip.emoji, style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: AppSpace.sm),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'Consejo de Stocky · toca para verlo',
                                    style: TextStyle(fontSize: 11, color: c.inkMuted),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    currentTip.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.ink),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Cerrar consejo',
                              visualDensity: VisualDensity.compact,
                              onPressed: _dismissTip,
                              icon: Icon(Icons.close_rounded, size: 16, color: c.inkFaint),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

        // Pastilla "Pregúntale a Stocky": dice qué hace, con el estilo de las tarjetas
        ScaleTransition(
          scale: _buttonScaleAnimation,
          child: Semantics(
            button: true,
            label: 'Pregúntale a Stocky',
            child: Material(
              color: c.surface,
              shape: StadiumBorder(side: BorderSide(color: c.line)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _handleButtonTap,
                child: Padding(
                  // Texto a la izquierda y Stocky a la derecha, pegado al borde de la pantalla
                  padding: const EdgeInsets.fromLTRB(AppSpace.lg, 4, 4, 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Pregúntale a Stocky',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.ink),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Container(
                        width: 38,
                        height: 38,
                        decoration: const BoxDecoration(color: StockyPalette.halo, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: StockyMascot(
                          size: 34,
                          state: _isExploding ? StockyState.success : StockyState.idle,
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

/// Painter para la animación de explosión con partículas, estrellas y onda expansiva
class _ExplosionPainter extends CustomPainter {
  final double progress;
  final List<_ExplosionParticle> particles;
  final Color glow;

  _ExplosionPainter({required this.progress, required this.particles, required this.glow});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0 || progress >= 1.0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final opacity = (1.0 - progress).clamp(0.0, 1.0);

    // 1. Onda expansiva exterior
    final ringPaint = Paint()
      ..color = glow.withOpacity(opacity * 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2 * (1.0 - progress);
    canvas.drawCircle(
      center,
      10.0 + 65.0 * Curves.easeOutCubic.transform(progress),
      ringPaint,
    );

    // 2. Onda expansiva interior dorada/verde
    final innerRingPaint = Paint()
      ..color = StockyPalette.sparkleGold.withOpacity(opacity * 0.55)
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
