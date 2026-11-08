import 'eyedropper_stub.dart' if (dart.library.js_interop) 'eyedropper_web.dart' as impl;

/// Gotero de pantalla del navegador (Chrome y Edge en el computador): se hace clic
/// en cualquier parte de la pantalla y devuelve ese color como '#RRGGBB'.
/// En el celular y en Safari/Firefox no existe.
bool get canUseEyeDropper => impl.canUseEyeDropper;

/// null si la persona canceló o el navegador no lo permite
Future<String?> pickScreenColor() => impl.pickScreenColor();
