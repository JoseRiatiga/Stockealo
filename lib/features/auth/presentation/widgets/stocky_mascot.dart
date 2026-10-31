import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../core/theme/stocky_palette.dart';

enum StockyState {
  idle,
  trackingEmail,
  coveringEyes,
  loading,
  error,
  success,
}

/// Stocky, la ardilla tendera con el delantal de Stockealo.
///
/// Estados: normal, siguiendo el correo con los ojos, tapándose los ojos con la cola
/// (contraseña), pensando, preocupada (error) y celebrando. En reposo respira, parpadea
/// y mueve la cola; con "reducir animaciones" solo cambia de cara.
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
  late final AnimationController _idleController =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  late final AnimationController _blinkController =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 160));
  late final AnimationController _tailController =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  late final AnimationController _celebrateController =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  Timer? _blinkTimer;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _idleController.stop();
      _blinkTimer?.cancel();
    } else if (!_idleController.isAnimating) {
      _idleController.repeat(reverse: true);
      _scheduleBlink();
    }
    _updateStateAnimations();
  }

  void _scheduleBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = Timer(Duration(milliseconds: 2600 + math.Random().nextInt(2600)), () async {
      if (!mounted || _reduceMotion) return;
      if (widget.state != StockyState.coveringEyes && widget.state != StockyState.success) {
        try {
          await _blinkController.forward();
          if (mounted) await _blinkController.reverse();
        } catch (_) {}
      }
      if (mounted) _scheduleBlink();
    });
  }

  @override
  void didUpdateWidget(covariant StockyMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) _updateStateAnimations();
  }

  void _updateStateAnimations() {
    final covering = widget.state == StockyState.coveringEyes;
    if (_reduceMotion) {
      _tailController.value = covering ? 1 : 0;
      _celebrateController.value = 0;
      return;
    }
    covering ? _tailController.forward() : _tailController.reverse();
    if (widget.state == StockyState.success) {
      _celebrateController.repeat(reverse: true);
    } else {
      _celebrateController.reset();
    }
  }

  @override
  void dispose() {
    _blinkTimer?.cancel();
    _idleController.dispose();
    _blinkController.dispose();
    _tailController.dispose();
    _celebrateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_idleController, _blinkController, _tailController, _celebrateController]),
      builder: (context, _) {
        final hop = widget.state == StockyState.success ? math.sin(_celebrateController.value * math.pi) * 0.06 : 0.0;
        return Transform.translate(
          offset: Offset(0, -hop * widget.size),
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: CustomPaint(
              painter: _SquirrelPainter(
                state: widget.state,
                look: widget.lookProgress.clamp(-1.0, 1.0),
                breath: _idleController.value,
                blink: _blinkController.value,
                tailCover: _tailController.value,
                celebrate: _celebrateController.value,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Dibuja la ardilla en una grilla de 120 × 112 (la misma de los bocetos) escalada al tamaño
class _SquirrelPainter extends CustomPainter {
  final StockyState state;
  final double look;
  final double breath;
  final double blink;
  final double tailCover;
  final double celebrate;

  _SquirrelPainter({
    required this.state,
    required this.look,
    required this.breath,
    required this.blink,
    required this.tailCover,
    required this.celebrate,
  });

  static Paint _fill(Color color, [double opacity = 1]) => Paint()..color = color.withOpacity(opacity);

  static Paint _stroke(Color color, double width, [double opacity = 1]) => Paint()
    ..color = color.withOpacity(opacity)
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 120;
    canvas.save();
    canvas.translate(0, (size.height - 112 * scale) / 2);
    canvas.scale(scale);

    final thinking = state == StockyState.loading;
    final happy = state == StockyState.success;
    final worried = state == StockyState.error;

    if (happy) _sparkles(canvas);
    if (thinking) _thoughts(canvas);
    if (worried) _sweat(canvas);

    _tail(canvas);

    // Cuerpo y delantal; al respirar el cuerpo sube y baja un poquito
    final lift = math.sin(breath * math.pi) * 1.2;
    canvas.save();
    canvas.translate(0, -lift * 0.5);
    canvas.drawOval(Rect.fromCenter(center: const Offset(56, 88), width: 56, height: 48), _fill(StockyPalette.body));
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(35, 73, 42, 35), const Radius.circular(11)),
      _fill(StockyPalette.apron),
    );
    _apronLogo(canvas, const Offset(55, 91), 19);
    canvas.restore();

    if (happy) {
      // Brazos arriba
      final arms = _stroke(StockyPalette.fur, 8);
      canvas.drawPath(Path()..moveTo(34, 86)..quadraticBezierTo(22, 78, 24, 62), arms);
      canvas.drawPath(Path()..moveTo(78, 86)..quadraticBezierTo(90, 78, 88, 62), arms);
    } else if (thinking) {
      // Pata en la barbilla
      canvas.drawPath(Path()..moveTo(70, 96)..quadraticBezierTo(82, 90, 74, 70), _stroke(StockyPalette.fur, 8));
    }

    // Cabeza
    canvas.save();
    canvas.translate(0, -lift);
    canvas.drawCircle(const Offset(56, 50), 30, _fill(StockyPalette.fur));
    final ears = _fill(StockyPalette.furDark);
    canvas.drawPath(Path()..moveTo(30, 34)..lineTo(26, 16)..lineTo(42, 26)..close(), ears);
    canvas.drawPath(Path()..moveTo(82, 34)..lineTo(86, 16)..lineTo(70, 26)..close(), ears);
    canvas.drawOval(Rect.fromCenter(center: const Offset(56, 62), width: 36, height: 26), _fill(StockyPalette.muzzle));

    _face(canvas, thinking: thinking, happy: happy, worried: worried);

    final blush = _fill(StockyPalette.blush, 0.45);
    canvas.drawOval(Rect.fromCenter(center: const Offset(38, 60), width: 11, height: 6.8), blush);
    canvas.drawOval(Rect.fromCenter(center: const Offset(74, 60), width: 11, height: 6.8), blush);

    if (tailCover > 0) _tailOverEyes(canvas);
    canvas.restore();

    canvas.restore();
  }

  void _tail(Canvas canvas) {
    // La cola se mece un poco con la respiración
    canvas.save();
    canvas.translate(80, 92);
    canvas.rotate(math.sin(breath * math.pi) * 0.05 - tailCover * 0.08);
    canvas.translate(-80, -92);
    canvas.drawPath(
      Path()
        ..moveTo(88, 96)
        ..quadraticBezierTo(118, 86, 110, 48)
        ..quadraticBezierTo(104, 24, 84, 30)
        ..quadraticBezierTo(98, 40, 90, 64)
        ..quadraticBezierTo(84, 82, 68, 86)
        ..close(),
      _fill(StockyPalette.furDark),
    );
    canvas.drawPath(
      Path()
        ..moveTo(92, 90)
        ..quadraticBezierTo(110, 78, 106, 52)
        ..quadraticBezierTo(103, 40, 94, 40)
        ..quadraticBezierTo(102, 52, 96, 70)
        ..quadraticBezierTo(91, 84, 82, 88)
        ..close(),
      _fill(StockyPalette.fur),
    );
    canvas.restore();
  }

  void _face(Canvas canvas, {required bool thinking, required bool happy, required bool worried}) {
    const ink = StockyPalette.ink;
    final hideEyes = tailCover > 0.5;

    if (!hideEyes) {
      if (happy) {
        final arc = _stroke(ink, 3.2);
        canvas.drawPath(Path()..moveTo(39, 49)..quadraticBezierTo(45, 42, 51, 49), arc);
        canvas.drawPath(Path()..moveTo(61, 49)..quadraticBezierTo(67, 42, 73, 49), arc);
      } else {
        var dx = 0.0, dy = 0.0, r = 5.0;
        if (state == StockyState.trackingEmail) {
          dx = look * 3.5;
          dy = 2;
        } else if (thinking) {
          dx = -2;
          dy = -3;
          r = 4.6;
        } else if (worried) {
          dy = 2;
          r = 4.6;
        }
        _eye(canvas, Offset(45 + dx, 48 + dy), r);
        _eye(canvas, Offset(67 + dx, 48 + dy), r);
        if (worried) {
          final brow = _stroke(StockyPalette.furDark, 2.2);
          // Cejas que suben hacia el centro: preocupación (al revés se ve enojada)
          canvas.drawLine(const Offset(38, 43), const Offset(48, 39), brow);
          canvas.drawLine(const Offset(74, 43), const Offset(64, 39), brow);
        }
      }
    }

    canvas.drawOval(Rect.fromCenter(center: const Offset(56, 58), width: 8, height: 6), _fill(ink));

    if (happy) {
      canvas.drawPath(
        Path()..moveTo(49, 62)..quadraticBezierTo(56, 72, 63, 62)..close(),
        _fill(StockyPalette.mouth),
      );
    } else if (thinking) {
      canvas.drawLine(const Offset(52, 65), const Offset(60, 65), _stroke(ink, 2.8));
    } else if (worried) {
      canvas.drawPath(Path()..moveTo(51, 67)..quadraticBezierTo(56, 63, 61, 67), _stroke(ink, 2.8));
    } else {
      canvas.drawPath(Path()..moveTo(51, 64)..quadraticBezierTo(56, 69, 61, 64), _stroke(ink, 3));
    }
  }

  void _eye(Canvas canvas, Offset c, double r) {
    // Al parpadear el ojo se aplasta hasta una línea
    final open = 1 - blink * 0.9;
    canvas.drawOval(Rect.fromCenter(center: c, width: r * 2, height: r * 2 * open), _fill(StockyPalette.ink));
    if (open > 0.5) {
      canvas.drawCircle(c + Offset(r * 0.35, -r * 0.4 * open), r * 0.32, _fill(Colors.white));
    }
  }

  void _tailOverEyes(Canvas canvas) {
    // La cola sube desde abajo y le cubre los ojos
    canvas.save();
    canvas.translate(0, (1 - tailCover) * 24);
    final opacity = tailCover.clamp(0.0, 1.0);
    canvas.drawPath(
      Path()
        ..moveTo(26, 46)
        ..quadraticBezierTo(56, 32, 86, 46)
        ..quadraticBezierTo(88, 53, 82, 55)
        ..quadraticBezierTo(56, 46, 30, 55)
        ..quadraticBezierTo(24, 53, 26, 46)
        ..close(),
      _fill(StockyPalette.fur, opacity),
    );
    canvas.drawPath(
      Path()..moveTo(30, 46)..quadraticBezierTo(56, 38, 82, 46),
      _stroke(StockyPalette.furDark, 2.2, 0.5 * opacity),
    );
    canvas.restore();
  }

  /// El logo de Stockealo estampado en un color: caja, código de barras y ✓
  void _apronLogo(Canvas canvas, Offset center, double size) {
    final k = size / 40;
    Offset p(double x, double y) => center + Offset(x * k, y * k);
    Path poly(List<Offset> pts) => Path()..addPolygon(pts, true);

    canvas.drawPath(poly([p(-19, -11), p(0, -20), p(19, -11), p(0, -2)]), _fill(StockyPalette.printLight));
    const bars = [-17.0, -13.0, -10.0, -7.0, -4.0];
    for (var i = 0; i < bars.length; i++) {
      final bar = Paint()
        ..color = StockyPalette.printLight
        ..strokeWidth = (i.isOdd ? 1.4 : 2.4) * k;
      canvas.drawLine(p(bars[i], -6 + i * 1.3), p(bars[i], 11 + i * 1.3), bar);
    }
    canvas.drawPath(poly([p(1, 0), p(19, -9), p(19, 11), p(1, 20)]), _fill(StockyPalette.printShade));
    canvas.drawPath(
      Path()
        ..moveTo(p(4, 8).dx, p(4, 8).dy)
        ..lineTo(p(9, 13).dx, p(9, 13).dy)
        ..lineTo(p(24, -6).dx, p(24, -6).dy),
      _stroke(StockyPalette.apron, 3.6 * k),
    );
  }

  void _sparkles(Canvas canvas) {
    final o = 0.4 + celebrate * 0.6;
    final gold = _stroke(StockyPalette.sparkleGold, 2.4, o);
    canvas.drawLine(const Offset(8, 18), const Offset(12, 24), gold);
    canvas.drawLine(const Offset(16, 12), const Offset(16, 20), gold);
    canvas.drawLine(const Offset(2, 26), const Offset(10, 26), gold);
    final green = _stroke(StockyPalette.sparkleGreen, 2.4, o);
    canvas.drawLine(const Offset(104, 8), const Offset(107, 14), green);
    canvas.drawLine(const Offset(110, 16), const Offset(103, 16), green);
  }

  void _thoughts(Canvas canvas) {
    final bubble = _fill(StockyPalette.thought);
    canvas.drawCircle(Offset(96, 20 - breath), 3.2, bubble);
    canvas.drawCircle(Offset(103, 10 - breath * 1.5), 4.6, bubble);
  }

  void _sweat(Canvas canvas) {
    canvas.drawPath(
      Path()
        ..moveTo(84, 30)
        ..quadraticBezierTo(87, 36, 84, 40)
        ..quadraticBezierTo(81, 36, 84, 30)
        ..close(),
      _fill(StockyPalette.sweat),
    );
  }

  @override
  bool shouldRepaint(_SquirrelPainter old) =>
      old.state != state ||
      old.look != look ||
      old.breath != breath ||
      old.blink != blink ||
      old.tailCover != tailCover ||
      old.celebrate != celebrate;
}
