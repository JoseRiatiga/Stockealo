import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/status_pill.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_repository.dart';
import '../../data/activity_repository.dart';
import '../../data/authorization_service.dart';

/// Cuando el rol no permite algo o pasa su límite: «Pedir autorización» (0.15.0).
/// Devuelve true si alguien lo aprobó (una sola vez). Uso:
///
/// ```dart
/// if (reasons.isNotEmpty &&
///     !await AuthorizationGate.allow(context, businessId: id, action: 'Descuento', reasons: reasons)) return;
/// ```
abstract final class AuthorizationGate {
  static Future<bool> allow(
    BuildContext context, {
    required String businessId,
    required String action,
    required List<String> reasons,
    double? amount,
  }) async {
    final ok = await AppDialog.confirm(
      context: context,
      icon: Icons.verified_user_outlined,
      title: 'Necesitas autorización',
      message: '${reasons.join('\n')}\n\nUn administrador o el dueño puede aprobarlo desde su celular. Sirve una sola vez.',
      confirmText: 'Pedir autorización',
    );
    if (!ok || !context.mounted) return false;
    final approved = await AppSheet.show<bool>(
      context: context,
      title: 'Pedir autorización',
      isDismissible: false,
      builder: (_) => _WaitingApproval(
        businessId: businessId,
        action: action,
        detail: reasons.join(' '),
        amount: amount,
      ),
    );
    return approved == true;
  }
}

/// Mientras espera: el número de la solicitud y su estado; se cierra sola al aprobarse
class _WaitingApproval extends StatefulWidget {
  final String businessId;
  final String action;
  final String detail;
  final double? amount;

  const _WaitingApproval({required this.businessId, required this.action, required this.detail, this.amount});

  @override
  State<_WaitingApproval> createState() => _WaitingApprovalState();
}

class _WaitingApprovalState extends State<_WaitingApproval> {
  final _service = AuthorizationService.instance;
  AuthRequest? _request;
  String? _error;
  Timer? _timer;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    try {
      final user = AuthRepository.instance.currentUser;
      final r = await _service.create(
        businessId: widget.businessId,
        action: widget.action,
        detail: widget.detail,
        amount: widget.amount,
        requestedName: user?.displayName.isNotEmpty == true ? user!.displayName : user?.email.split('@').first,
      );
      if (!mounted) return;
      setState(() => _request = r);
      // Revisa cada 3 segundos si ya la decidieron
      _timer = Timer.periodic(const Duration(seconds: 3), (_) => _check());
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _check() async {
    final r = _request;
    if (r == null || _finishing) return;
    try {
      final now = await _service.fetch(r.id);
      if (!mounted || now == null) return;
      setState(() => _request = now);
      if (now.status == AuthRequest.approved) {
        _finishing = true;
        _timer?.cancel();
        final used = await _service.use(now.id);
        if (!mounted) return;
        if (used) {
          AppToast.showSuccess(context, 'Autorizado por ${now.decidedName ?? 'un administrador'}.');
          Navigator.pop(context, true);
        } else {
          setState(() => _error = 'La aprobación venció. Pide otra.');
        }
      } else if (now.status == AuthRequest.rejected || now.expired()) {
        _timer?.cancel();
      }
    } catch (_) {
      // Sin conexión un momento: se reintenta en la próxima vuelta
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = _request;
    final rejected = r?.status == AuthRequest.rejected;
    final expired = r != null && r.status == AuthRequest.pending && r.expired();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_error != null)
          Text(_error!, style: AppText.body(context, color: c.danger))
        else if (r == null)
          const Center(child: Padding(padding: EdgeInsets.all(AppSpace.lg), child: CircularProgressIndicator()))
        else ...[
          Row(
            children: [
              Expanded(child: Text('Solicitud N.º ${r.number}', style: AppText.heading(context))),
              StatusPill(
                rejected ? 'Rechazada' : (expired ? 'Venció' : 'Esperando'),
                tone: rejected ? AppTone.danger : (expired ? AppTone.warning : AppTone.info),
                dot: !rejected && !expired,
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Text(widget.detail, style: AppText.body(context)),
          const SizedBox(height: AppSpace.md),
          Text(
            rejected
                ? 'La rechazó ${r.decidedName ?? 'un administrador'}.'
                : expired
                    ? 'Nadie la aprobó a tiempo. Puedes pedirla de nuevo.'
                    : 'Le llegó a los administradores y al dueño. Cuando la aprueben, esto se cierra solo.',
            style: AppText.small(context, color: c.inkMuted),
          ),
          if (!rejected && !expired) ...[
            const SizedBox(height: AppSpace.md),
            const LinearProgressIndicator(),
          ],
        ],
        const SizedBox(height: AppSpace.lg),
        OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(rejected || expired || _error != null ? 'Cerrar' : 'Cancelar'),
        ),
      ],
    );
  }
}

/// En el celular de quien autoriza: llega una solicitud y se aprueba o rechaza
abstract final class AuthorizationPrompt {
  static Future<void> show(BuildContext context, AuthRequest r) async {
    final amount = r.amount == null ? '' : ' · ${CurrencyFormatter.format(r.amount!)}';
    final decision = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
        icon: Icons.verified_user_outlined,
        title: '${r.requestedName ?? 'Alguien del equipo'} pide autorización',
        subtitle: 'Solicitud N.º ${r.number}$amount',
        content: Text('${r.action}\n${r.detail ?? ''}'.trim(), style: AppText.body(ctx)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Rechazar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aprobar')),
        ],
      ),
    );
    if (decision == null || !context.mounted) return;
    try {
      final me = AuthRepository.instance.currentUser;
      final name = me?.displayName.isNotEmpty == true ? me!.displayName : me?.email.split('@').first;
      final done = await AuthorizationService.instance.decide(r.id, approve: decision, name: name);
      // Cada autorización queda en Actividad del equipo
      ActivityRepository.instance.log(
        businessId: r.businessId,
        action: ActivityAction.authorize,
        summary: '${decision ? 'Autorizó' : 'Rechazó'} a ${r.requestedName ?? 'alguien'}: ${r.action}$amount (N.º ${r.number})',
        data: {'auth_request_id': r.id, 'approved': decision},
      );
      if (context.mounted) {
        AppToast.showSuccess(context, done.status == AuthRequest.approved ? 'Aprobada: tiene 5 minutos para usarla.' : 'Rechazada.');
      }
    } catch (e) {
      if (context.mounted) AppToast.showWarning(context, '$e');
    }
  }
}
