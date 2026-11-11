import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Elegir cualquier color sin saber códigos: tres barras con el dedo o el ratón.
/// Tono (el arcoíris), intensidad (de gris a vivo) y claridad (de oscuro a claro).
class ColorSliders extends StatefulWidget {
  final Color? value;
  final ValueChanged<Color> onChanged;

  const ColorSliders({super.key, required this.value, required this.onChanged});

  @override
  State<ColorSliders> createState() => _ColorSlidersState();
}

class _ColorSlidersState extends State<ColorSliders> {
  late HSLColor _hsl = _from(widget.value);

  static HSLColor _from(Color? c) => c == null ? const HSLColor.fromAHSL(1, 0, 0.75, 0.5) : HSLColor.fromColor(c);

  @override
  void didUpdateWidget(ColorSliders old) {
    super.didUpdateWidget(old);
    // Si eligieron el color por otro lado (paleta, foto), las barras se acomodan
    if (widget.value != null && widget.value != _hsl.toColor()) _hsl = _from(widget.value);
  }

  void _set(HSLColor hsl) {
    setState(() => _hsl = hsl);
    widget.onChanged(hsl.toColor());
  }

  @override
  Widget build(BuildContext context) {
    final hues = [for (var h = 0; h <= 360; h += 30) HSLColor.fromAHSL(1, h.toDouble(), _hsl.saturation.clamp(0.35, 1), 0.5).toColor()];
    return Column(
      children: [
        _GradientSlider(
          label: 'Tono',
          colors: hues,
          value: _hsl.hue / 360,
          onChanged: (v) => _set(_hsl.withHue((v * 360).clamp(0, 359.9))),
        ),
        _GradientSlider(
          label: 'Intensidad',
          colors: [_hsl.withSaturation(0).toColor(), _hsl.withSaturation(1).toColor()],
          value: _hsl.saturation,
          onChanged: (v) => _set(_hsl.withSaturation(v)),
        ),
        _GradientSlider(
          label: 'Claridad',
          colors: [Colors.black, _hsl.withLightness(0.5).toColor(), Colors.white],
          value: _hsl.lightness,
          onChanged: (v) => _set(_hsl.withLightness(v)),
        ),
      ],
    );
  }
}

/// Barra con el degradado de fondo y una perilla redonda que se arrastra
class _GradientSlider extends StatelessWidget {
  final String label;
  final List<Color> colors;
  final double value;
  final ValueChanged<double> onChanged;

  const _GradientSlider({required this.label, required this.colors, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(
        children: [
          SizedBox(
            width: 74,
            child: Text(label, style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted)),
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, box) {
              const knob = 22.0;
              final width = box.maxWidth;
              void update(double dx) => onChanged((dx / width).clamp(0.0, 1.0));
              return Semantics(
                slider: true,
                label: label,
                value: '${(value * 100).round()} %',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => update(d.localPosition.dx),
                  onHorizontalDragUpdate: (d) => update(d.localPosition.dx),
                  child: SizedBox(
                    height: 32,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Container(
                          height: 14,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            gradient: LinearGradient(colors: colors),
                            border: Border.all(color: c.line),
                          ),
                        ),
                        Positioned(
                          left: (value.clamp(0.0, 1.0) * width - knob / 2).clamp(0.0, width - knob),
                          child: Container(
                            width: knob,
                            height: knob,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white,
                              border: Border.all(color: c.ink.withValues(alpha: 0.6), width: 2),
                              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 3)],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
