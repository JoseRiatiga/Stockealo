import 'dart:js_interop';
import 'dart:js_interop_unsafe';

@JS('EyeDropper')
extension type _EyeDropper._(JSObject _) implements JSObject {
  external factory _EyeDropper();
  external JSPromise<_EyeDropperResult> open();
}

extension type _EyeDropperResult._(JSObject _) implements JSObject {
  external String get sRGBHex;
}

bool get canUseEyeDropper => globalContext.has('EyeDropper');

Future<String?> pickScreenColor() async {
  if (!canUseEyeDropper) return null;
  try {
    final result = await _EyeDropper().open().toDart;
    final hex = result.sRGBHex;
    // Chrome devuelve '#rrggbb'; algunos navegadores, 'rgb(r, g, b)'
    if (hex.startsWith('#')) return hex.toUpperCase();
    final m = RegExp(r'(\d+)\D+(\d+)\D+(\d+)').firstMatch(hex);
    if (m == null) return null;
    String two(String v) => int.parse(v).clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#${two(m[1]!)}${two(m[2]!)}${two(m[3]!)}'.toUpperCase();
  } catch (_) {
    return null; // la persona presionó Esc
  }
}
