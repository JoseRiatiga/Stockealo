import 'package:flutter/material.dart';

import '../../../core/database/app_database.dart';
import '../../../core/design/primary_action_button.dart';
import '../../../core/theme/app_tokens.dart';
import '../../auth/presentation/widgets/stocky_mascot.dart';

/// Bienvenida de tres pasos que se ve una sola vez en el dispositivo, antes de
/// iniciar sesión. Se puede saltar en cualquier momento.
class WelcomeScreen extends StatefulWidget {
  final VoidCallback onDone;

  const WelcomeScreen({super.key, required this.onDone});

  /// Clave en app_settings del archivo del dispositivo (el que se usa sin sesión)
  static const seenKey = 'welcome_seen';

  /// true si en este dispositivo todavía no se ha visto
  static Future<bool> shouldShow() async {
    try {
      return await AppDatabase.instance.getSetting(seenKey) != '1';
    } catch (_) {
      return false; // ante cualquier duda, no estorbar el inicio
    }
  }

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeStep {
  final IconData? icon;
  final String title;
  final String body;
  final List<String> points;

  const _WelcomeStep({this.icon, required this.title, required this.body, required this.points});
}

const _steps = [
  _WelcomeStep(
    icon: Icons.inventory_2_rounded,
    title: 'Tu inventario, siempre al día',
    body: 'Registra tus productos con foto, precio y stock.',
    points: ['Te avisamos antes de que algo se agote', 'Ves cuánto ganas en cada producto'],
  ),
  _WelcomeStep(
    icon: Icons.point_of_sale_rounded,
    title: 'Vende y cobra en segundos',
    body: 'Cada venta descuenta el stock sola.',
    points: ['Lleva los fiados de tus clientes', 'Envía comprobantes por WhatsApp'],
  ),
  _WelcomeStep(
    title: 'Stocky te ayuda',
    body: 'Pregúntale cómo van tus ventas, qué reponer o a quién cobrar.',
    points: ['Comparte tu catálogo con un toque', 'Trabaja con tu equipo desde varios celulares'],
  ),
];

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _pageController = PageController();
  int _page = 0;

  bool get _isLast => _page == _steps.length - 1;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    try {
      await AppDatabase.instance.setSetting(WelcomeScreen.seenKey, '1');
    } catch (_) {}
    widget.onDone();
  }

  void _next() {
    if (_isLast) {
      _finish();
      return;
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (reduceMotion) {
      _pageController.jumpToPage(_page + 1);
    } else {
      _pageController.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.md, AppSpace.sm, 0),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.asset('assets/icon/app_icon.png', width: 30, height: 30),
                      ),
                      const SizedBox(width: AppSpace.sm + 2),
                      Expanded(
                        child: Text('Stockealo', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c.ink)),
                      ),
                      AnimatedOpacity(
                        opacity: _isLast ? 0 : 1,
                        duration: const Duration(milliseconds: 200),
                        child: TextButton(
                          onPressed: _isLast ? null : _finish,
                          style: TextButton.styleFrom(foregroundColor: c.inkMuted),
                          child: const Text('Saltar'),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _steps.length,
                    onPageChanged: (i) => setState(() => _page = i),
                    itemBuilder: (_, i) => _StepView(step: _steps[i]),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.xl),
                  child: Column(
                    children: [
                      Semantics(
                        label: 'Paso ${_page + 1} de ${_steps.length}',
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < _steps.length; i++)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                margin: const EdgeInsets.symmetric(horizontal: 3),
                                width: i == _page ? 22 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: i == _page ? c.accent : c.lineStrong,
                                  borderRadius: BorderRadius.circular(AppRadius.pill),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpace.xl),
                      SizedBox(
                        width: double.infinity,
                        child: PrimaryActionButton(
                          label: _isLast ? 'Empezar' : 'Siguiente',
                          icon: _isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                          onPressed: _next,
                        ),
                      ),
                    ],
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

class _StepView extends StatelessWidget {
  final _WelcomeStep step;

  const _StepView({required this.step});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
      child: Column(
        children: [
          const SizedBox(height: AppSpace.xxl),
          Container(
            width: 168,
            height: 168,
            decoration: BoxDecoration(
              color: c.accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(48),
            ),
            child: Center(
              child: step.icon != null
                  ? Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(28)),
                      child: Icon(step.icon, size: 48, color: c.onAccent),
                    )
                  : const StockyMascot(size: 132, state: StockyState.success),
            ),
          ),
          const SizedBox(height: AppSpace.xxl),
          Text(
            step.title,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800, letterSpacing: -0.4, height: 1.15, color: c.ink),
          ),
          const SizedBox(height: AppSpace.md),
          Text(step.body, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, height: 1.4, color: c.inkMuted)),
          const SizedBox(height: AppSpace.xl),
          Container(
            padding: const EdgeInsets.all(AppSpace.lg),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: c.line),
            ),
            child: Column(
              children: [
                for (final point in step.points)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.xs + 2),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_rounded, size: 20, color: c.accent),
                        const SizedBox(width: AppSpace.md),
                        Expanded(child: Text(point, style: TextStyle(fontSize: 15, color: c.ink))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.xl),
        ],
      ),
    );
  }
}
