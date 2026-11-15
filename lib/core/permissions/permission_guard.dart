import 'package:flutter/widgets.dart';

import '../widgets/app_toast.dart';
import 'permissions.dart';

/// Revisa un permiso del rol activo antes de una acción (0.15.0). Si no lo tiene,
/// lo dice con un aviso y devuelve false. Uso:
///
/// ```dart
/// if (!PermissionGuard.check(context, Perm.discount)) return;
/// ```
abstract final class PermissionGuard {
  static bool check(BuildContext context, Perm perm) {
    if (Permissions.mine(perm)) return true;
    AppToast.showPermission(context, 'Tu rol no permite «${perm.label}». Si lo necesitas, pídeselo al dueño.');
    return false;
  }
}
