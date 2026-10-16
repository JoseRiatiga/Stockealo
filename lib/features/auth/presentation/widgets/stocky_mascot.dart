import 'dart:math' as math;
import 'package:flutter/material.dart';

enum StockyState {
  idle,
  trackingEmail,
  coveringEyes,
  loading,
  error,
  success,
}

class StockyMascot extends StatefulWidget {
  final StockyState state;
  final double lookProgress; // -1.0 a 1.0 para seguir la posición del texto
  final double size;

  const StockyMascot({
    super.key,
    this.state = StockyState.idle,
    this.lookProgress = 0.0,
    this.size = 100.0,
  });

  @override
  State<StockyMascot> createState() => _StockyMascotState();
}

class _StockyMascotState extends State<StockyMascot> with TickerProviderStateMixin {
  late AnimationController _idleController;
  late AnimationController _blinkController;
  late AnimationController _handsController;
  late AnimationController _celebrateController;

  @override
  void initState() {
    super.initState();

    // Respiración y balanceo flotante suave
    _idleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    // Parpadeo intermitente natural
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _scheduleBlink();

    // Animación de taparse los ojos
    _handsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );

    // Animación de celebración (éxito)
    _celebrateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _updateStateAnimations();
  }

  void _scheduleBlink() async {
    while (mounted) {
      await Future.delayed(Duration(milliseconds: 2800 + math.Random().nextInt(2500)));
      if (!mounted) break;
      if (widget.state != StockyState.coveringEyes) {
        await _blinkController.forward();
        if (mounted) {
          await _blinkController.reverse();
        }
      }
    }
  }

  @override
  void didUpdateWidget(covariant StockyMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _updateStateAnimations();
    }
  }

  void _updateStateAnimations() {
    if (widget.state == StockyState.coveringEyes) {
      _handsController.forward();
    } else {
      _handsController.reverse();
    }

    if (widget.state == StockyState.success) {
      _celebrateController.repeat(reverse: true);
    } else {
      _celebrateController.reset();
    }
  }

  @override
  void dispose() {
    _idleController.dispose();
    _blinkController.dispose();
    _handsController.dispose();
    _celebrateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: Listenable.merge([
        _idleController,
        _blinkController,
        _handsController,
        _celebrateController,
      ]),
      builder: (context, _) {
        final floatOffset = math.sin(_idleController.value * math.pi) * 3.5;
        final jumpOffset = widget.state == StockyState.success
            ? math.sin(_celebrateController.value * math.pi) * 8.0
            : 0.0;

        return Transform.translate(
          offset: Offset(0, -floatOffset - jumpOffset),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: _StockyPainter(
                state: widget.state,
                lookProgress: widget.lookProgress.clamp(-1.0, 1.0),
                blinkValue: _blinkController.value,
                handsValue: _handsController.value,
                celebrateValue: _celebrateController.value,
                isDark: isDark,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _StockyPainter extends CustomPainter {
  final StockyState state;
  final double lookProgress;
  final double blinkValue;
  final double handsValue;
  final double celebrateValue;
  final bool isDark;

  _StockyPainter({
    required this.state,
    required this.lookProgress,
    required this.blinkValue,
    required this.handsValue,
    required this.celebrateValue,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);

    // Sombra en el suelo
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(isDark ? 0.35 : 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    final shadowRect = Rect.fromCenter(
      center: Offset(center.dx, h - 4),
      width: w * 0.75,
      height: 10,
    );
    canvas.drawOval(shadowRect, shadowPaint);

    // 1. Cuerpo de Stocky: Caja amigable con esquinas redondeadas
    final boxRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(center.dx, center.dy + 2), width: w * 0.82, height: h * 0.78),
      const Radius.circular(20),
    );

    // Gradiente esmeralda premium
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: isDark
            ? [const Color(0xFF059669), const Color(0xFF047857), const Color(0xFF064E3B)]
            : [const Color(0xFF10B981), const Color(0xFF059669), const Color(0xFF047857)],
      ).createShader(boxRect.outerRect);

    // Dibujar cuerpo
    canvas.drawRRect(boxRect, bodyPaint);

    // Borde brillante superior
    final borderPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRRect(boxRect, borderPaint);

    // Cinta / Tapa superior de la caja (característica de paquete de stock)
    final tapeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(center.dx - 12, boxRect.top, 24, boxRect.height * 0.35),
      const Radius.circular(5),
    );
    final tapePaint = Paint()..color = const Color(0xFF34D399).withOpacity(0.35);
    canvas.drawRRect(tapeRect, tapePaint);

    // Pequeño broche / estrella en el centro de la cinta
    final pinPaint = Paint()..color = const Color(0xFFA7F3D0);
    canvas.drawCircle(Offset(center.dx, boxRect.top + 8), 3.5, pinPaint);

    // 2. Mejillas sonrosadas suaves (Blush)
    final blushPaint = Paint()..color = const Color(0xFFFDA4AF).withOpacity(0.45);
    canvas.drawCircle(Offset(center.dx - w * 0.26, center.dy + 12), 7.5, blushPaint);
    canvas.drawCircle(Offset(center.dx + w * 0.26, center.dy + 12), 7.5, blushPaint);

    // 3. Ojos interactivos
    final eyeCenterY = center.dy - 2;
    final leftEyeCenterX = center.dx - w * 0.16;
    final rightEyeCenterX = center.dx + w * 0.16;

    if (state == StockyState.success) {
      // Ojos de felicidad cerrada en media luna (^ ^)
      final happyEyePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3.5;

      final leftPath = Path()
        ..moveTo(leftEyeCenterX - 9, eyeCenterY + 2)
        ..quadraticBezierTo(leftEyeCenterX, eyeCenterY - 7, leftEyeCenterX + 9, eyeCenterY + 2);
      final rightPath = Path()
        ..moveTo(rightEyeCenterX - 9, eyeCenterY + 2)
        ..quadraticBezierTo(rightEyeCenterX, eyeCenterY - 7, rightEyeCenterX + 9, eyeCenterY + 2);

      canvas.drawPath(leftPath, happyEyePaint);
      canvas.drawPath(rightPath, happyEyePaint);
    } else if (state == StockyState.error) {
      // Ojos de mareo / error (> <)
      final errorPaint = Paint()
        ..color = const Color(0xFFFEF08A)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3.0;

      // Ojo izquierdo 'X'
      canvas.drawLine(Offset(leftEyeCenterX - 6, eyeCenterY - 6), Offset(leftEyeCenterX + 6, eyeCenterY + 6), errorPaint);
      canvas.drawLine(Offset(leftEyeCenterX + 6, eyeCenterY - 6), Offset(leftEyeCenterX - 6, eyeCenterY + 6), errorPaint);

      // Ojo derecho 'X'
      canvas.drawLine(Offset(rightEyeCenterX - 6, eyeCenterY - 6), Offset(rightEyeCenterX + 6, eyeCenterY + 6), errorPaint);
      canvas.drawLine(Offset(rightEyeCenterX + 6, eyeCenterY - 6), Offset(rightEyeCenterX - 6, eyeCenterY + 6), errorPaint);
    } else {
      // Ojos normales con seguimiento de cursor y parpadeo
      final eyeHeight = 16.0 * (1.0 - blinkValue).clamp(0.1, 1.0);
      const eyeWidth = 14.0;

      final whitePaint = Paint()..color = Colors.white;
      final pupilPaint = Paint()..color = const Color(0xFF064E3B);
      final shinePaint = Paint()..color = Colors.white;

      // Desplazamiento pupilar según lookProgress (-1.0 a 1.0)
      final pupilOffsetX = lookProgress * 4.0;
      const pupilOffsetY = 1.0;

      for (final eyeX in [leftEyeCenterX, rightEyeCenterX]) {
        // Esclerótica blanca
        canvas.drawOval(
          Rect.fromCenter(center: Offset(eyeX, eyeCenterY), width: eyeWidth, height: eyeHeight),
          whitePaint,
        );

        if (blinkValue < 0.7) {
          // Pupila oscura
          const pupilRadius = 4.5;
          canvas.drawCircle(
            Offset(eyeX + pupilOffsetX, eyeCenterY + pupilOffsetY),
            pupilRadius,
            pupilPaint,
          );

          // Brillo de luz en el ojo
          canvas.drawCircle(
            Offset(eyeX + pupilOffsetX - 1.5, eyeCenterY + pupilOffsetY - 1.5),
            1.8,
            shinePaint,
          );
        }
      }
    }

    // 4. Boca expresiva
    final mouthPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.8;

    if (state == StockyState.success) {
      // Sonrisa amplia abierta con lengua
      final mouthPath = Path()
        ..moveTo(center.dx - 12, center.dy + 14)
        ..quadraticBezierTo(center.dx, center.dy + 26, center.dx + 12, center.dy + 14);
      canvas.drawPath(mouthPath, mouthPaint);

      // Lengua
      final tonguePaint = Paint()..color = const Color(0xFFF43F5E);
      final tonguePath = Path()
        ..moveTo(center.dx - 6, center.dy + 18)
        ..quadraticBezierTo(center.dx, center.dy + 24, center.dx + 6, center.dy + 18);
      canvas.drawPath(tonguePath, tonguePaint);
    } else if (state == StockyState.error) {
      // Boca ondulada confundida
      final wavyPath = Path()
        ..moveTo(center.dx - 8, center.dy + 17)
        ..quadraticBezierTo(center.dx - 4, center.dy + 13, center.dx, center.dy + 17)
        ..quadraticBezierTo(center.dx + 4, center.dy + 21, center.dx + 8, center.dy + 17);
      canvas.drawPath(wavyPath, mouthPaint);
    } else {
      // Sonrisa tierna sutil
      final smilePath = Path()
        ..moveTo(center.dx - 7, center.dy + 15)
        ..quadraticBezierTo(center.dx, center.dy + 21, center.dx + 7, center.dy + 15);
      canvas.drawPath(smilePath, mouthPaint);
    }

    // 5. Manitas de Stocky (Se mueven para taparse los ojos cuando handsValue > 0)
    final handPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF34D399), Color(0xFF059669)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final handStroke = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // Posición de reposo vs posición sobre los ojos
    final restLeftHand = Offset(boxRect.left + 2, center.dy + 18);
    final restRightHand = Offset(boxRect.right - 2, center.dy + 18);

    final coverLeftHand = Offset(leftEyeCenterX - 2, eyeCenterY + 2);
    final coverRightHand = Offset(rightEyeCenterX + 2, eyeCenterY + 2);

    final curLeftHand = Offset.lerp(restLeftHand, coverLeftHand, handsValue)!;
    final curRightHand = Offset.lerp(restRightHand, coverRightHand, handsValue)!;

    const handRadius = 11.0;

    // Dibujar manitas
    for (final handPos in [curLeftHand, curRightHand]) {
      canvas.drawCircle(handPos, handRadius, handPaint);
      canvas.drawCircle(handPos, handRadius, handStroke);

      // Detalles de deditos cuando se tapa los ojos
      if (handsValue > 0.4) {
        final fingerPaint = Paint()
          ..color = Colors.white.withOpacity(0.4)
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.2;
        canvas.drawLine(Offset(handPos.dx - 3, handPos.dy - 4), Offset(handPos.dx - 3, handPos.dy + 3), fingerPaint);
        canvas.drawLine(Offset(handPos.dx, handPos.dy - 5), Offset(handPos.dx, handPos.dy + 4), fingerPaint);
        canvas.drawLine(Offset(handPos.dx + 3, handPos.dy - 4), Offset(handPos.dx + 3, handPos.dy + 3), fingerPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StockyPainter oldDelegate) {
    return oldDelegate.state != state ||
        oldDelegate.lookProgress != lookProgress ||
        oldDelegate.blinkValue != blinkValue ||
        oldDelegate.handsValue != handsValue ||
        oldDelegate.celebrateValue != celebrateValue ||
        oldDelegate.isDark != isDark;
  }
}
