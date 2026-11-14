import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/design/app_dialog.dart';
import '../core/theme/app_tokens.dart';
import '../core/widgets/app_toast.dart';
import '../core/utils/currency_formatter.dart';
import '../features/pro/data/pro_admin_service.dart';
import 'admin_user_detail.dart';
import 'admin_widgets.dart';

/// Salud de Stockealo: a quién conviene escribirle hoy y cuánto se usa de Supabase
class AdminHealthSection extends StatelessWidget {
  final AdminHealth health;

  /// correo → {at, by}: a quién ya se le escribió (para no hacerlo dos veces)
  final Map<String, Map<String, dynamic>> contacts;

  const AdminHealthSection({super.key, required this.health, this.contacts = const {}});

  String? _contactedLabel(String? email) {
    final c = email == null ? null : contacts[email.toLowerCase()];
    if (c == null) return null;
    return 'contactado ${adminDate(DateTime.tryParse('${c['at']}')?.toLocal())}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final h = health;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpace.xl),
        Text('Salud de Stockealo', style: TextStyle(fontSize: AppText.sizeHeading, fontWeight: FontWeight.w700, color: c.ink)),
        Text('A quién conviene escribirle hoy', style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted)),
        const SizedBox(height: AppSpace.md),
        if (h.allGood)
          AdminCard(
            child: Row(children: [
              Icon(Icons.check_circle_outline_outlined, color: c.success),
              const SizedBox(width: AppSpace.md),
              Expanded(child: Text('Todo en orden: nadie necesita atención hoy.', style: TextStyle(color: c.ink))),
            ]),
          ),
        if (h.noCloud.isNotEmpty)
          _group(
            context,
            icon: Icons.cloud_off_outlined,
            title: '${h.noCloud.length} ${h.noCloud.length == 1 ? 'cuenta' : 'cuentas'} sin negocio en la nube',
            hint: 'O no han empezado, o tienen sus datos solo en el celular o el navegador y pueden perderlos. '
                'Escríbeles para que activen la sincronización.',
            rows: [
              for (final u in h.noCloud)
                _Row(
                  title: (u['name'] as String?)?.trim().isNotEmpty == true ? u['name'] as String : u['email'] as String,
                  detail: '${u['email']} · registro ${adminDate(DateTime.tryParse('${u['created_at']}'))}',
                  email: u['email'] as String?,
                  phone: u['phone'] as String?,
                ),
            ],
          ),
        if (h.expiring.isNotEmpty)
          _group(
            context,
            icon: Icons.hourglass_bottom_outlined,
            title: '${h.expiring.length} Pro vence${h.expiring.length == 1 ? '' : 'n'} en los próximos 7 días',
            hint: 'Avísales antes de que venza para que renueven.',
            rows: [
              for (final s in h.expiring)
                _Row(
                  title: '${s['business'] ?? 'Pro Global'}',
                  detail: '${s['owner_email']} · vence ${adminDate(DateTime.tryParse('${s['ends_at']}'))}',
                  email: s['owner_email'] as String?,
                  phone: s['phone'] as String?,
                ),
            ],
          ),
        if (h.failedPayments.isNotEmpty)
          _group(
            context,
            icon: Icons.credit_card_off_outlined,
            title: '${h.failedPayments.length} ${h.failedPayments.length == 1 ? 'pago' : 'pagos'} de Pro sin completar (7 días)',
            hint: 'Intentaron pagar y no se pudo: vale la pena preguntarles si necesitan ayuda.',
            rows: [
              for (final p in h.failedPayments)
                _Row(
                  title: '${p['business'] ?? p['user_email']}',
                  detail: '${p['user_email']} · '
                      '${CurrencyFormatter.formatIn(((p['amount_in_cents'] as num?) ?? 0) / 100, 'COP')} · '
                      '${adminDate(DateTime.tryParse('${p['created_at']}'))}',
                  email: p['user_email'] as String?,
                ),
            ],
          ),
        const SizedBox(height: AppSpace.md),
        _usage(c),
        if (h.inactive30d > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.sm),
            child: Text(
              '${h.inactive30d} ${h.inactive30d == 1 ? 'cuenta no ha' : 'cuentas no han'} iniciado sesión en 30 días '
              '(quien deja la sesión abierta no cuenta como nuevo inicio).',
              style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkFaint),
            ),
          ),
      ],
    );
  }

  Widget _group(BuildContext context,
      {required IconData icon, required String title, required String hint, required List<_Row> rows}) {
    final c = context.colors;
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: c.warning),
            const SizedBox(width: AppSpace.md),
            Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: c.ink))),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: 36, top: 2, bottom: AppSpace.sm),
            child: Text(hint, style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted)),
          ),
          for (final r in rows.take(5))
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.title, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.ink)),
                        Text(r.detail, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkFaint)),
                        if (_contactedLabel(r.email) != null)
                          Text(_contactedLabel(r.email)!,
                              style: TextStyle(fontSize: AppText.sizeCaption, fontWeight: FontWeight.w600, color: c.success)),
                      ],
                    ),
                  ),
                  if (whatsappDigits(r.phone) != null)
                    IconButton(
                      tooltip: 'Escribir por WhatsApp',
                      icon: Icon(Icons.chat_outlined, size: 18, color: c.accent),
                      onPressed: () =>
                          launchUrl(Uri.parse('https://wa.me/${whatsappDigits(r.phone)}'), webOnlyWindowName: '_blank'),
                    ),
                  if (r.email != null)
                    IconButton(
                      tooltip: 'Ver ficha',
                      icon: Icon(Icons.person_search_outlined, size: 18, color: c.inkMuted),
                      onPressed: () => AdminUserDetailDialog.show(context, r.email!),
                    ),
                ],
              ),
            ),
          if (rows.length > 5)
            Padding(
              padding: const EdgeInsets.only(left: 36, top: 4),
              child: Text('y ${rows.length - 5} más', style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkFaint)),
            ),
        ],
      ),
    );
  }

  Widget _usage(StockealoColors c) {
    Widget bar(String label, int used, int limit, double share, String extra) {
      final tone = share >= 0.85 ? c.danger : (share >= 0.6 ? c.warning : c.accent);
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text(label, style: TextStyle(color: c.ink))),
              Text('${AdminHealth.bytesLabel(used)} de ${AdminHealth.bytesLabel(limit)}',
                  style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: share.clamp(0.0, 1.0),
                minHeight: 8,
                color: tone,
                backgroundColor: c.surfaceMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text('${(share * 100).toStringAsFixed(share < 0.1 ? 1 : 0)} % usado$extra',
                style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkFaint)),
          ],
        ),
      );
    }

    final h = health;
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.storage_outlined, color: c.inkMuted),
            const SizedBox(width: AppSpace.md),
            Expanded(child: Text('Uso de Supabase', style: TextStyle(fontWeight: FontWeight.w700, color: c.ink))),
          ]),
          const SizedBox(height: AppSpace.md),
          bar('Base de datos', h.dbBytes, h.dbLimitBytes, h.dbUse, ''),
          bar('Archivos (fotos y logos)', h.storageBytes, h.storageLimitBytes, h.storageUse,
              ' · ${h.storageObjects} ${h.storageObjects == 1 ? 'archivo' : 'archivos'}'),
          Text('Límites del plan gratis de Supabase.', style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkFaint)),
          const SizedBox(height: AppSpace.sm),
          const _OrphanCleanup(),
        ],
      ),
    );
  }
}

/// Limpieza única de archivos que ya no usa nadie (0.13.4): primero cuenta y muestra
/// cuánto espacio libera; solo borra después de confirmar.
class _OrphanCleanup extends StatefulWidget {
  const _OrphanCleanup();

  @override
  State<_OrphanCleanup> createState() => _OrphanCleanupState();
}

class _OrphanCleanupState extends State<_OrphanCleanup> {
  bool _busy = false;

  static String _size(num bytes) =>
      bytes >= 1048576 ? '${(bytes / 1048576).toStringAsFixed(1)} MB' : '${(bytes / 1024).ceil()} KB';

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      final found = await ProAdminService.instance.orphanFiles();
      if (!mounted) return;
      final count = (found['count'] as num?)?.toInt() ?? 0;
      if (count == 0) {
        AppToast.show(context, message: 'No hay archivos sin uso.', type: ToastType.success);
        return;
      }
      final ok = await AppDialog.confirm(
        context: context,
        title: 'Borrar $count ${count == 1 ? 'archivo sin uso' : 'archivos sin uso'}',
        message: 'Son fotos de productos que ya no existen y facturas sin compra, con más de un día. '
            'Liberan ${_size(found['bytes'] as num? ?? 0)}. Los negocios en la papelera no se tocan. '
            'No se puede deshacer.',
        confirmText: 'Borrar',
        destructive: true,
      );
      if (!ok || !mounted) return;
      final done = await ProAdminService.instance.orphanFiles(delete: true);
      if (!mounted) return;
      AppToast.show(context, message: 'Se borraron ${done['deleted']} archivos.', type: ToastType.success);
    } on ProAdminException catch (e) {
      if (mounted) AppToast.showError(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _busy ? null : _run,
          icon: const Icon(Icons.cleaning_services_outlined, size: 18),
          label: Text(_busy ? 'Revisando…' : 'Buscar archivos sin uso'),
        ),
      );
}

class _Row {
  final String title;
  final String detail;
  final String? email;
  final String? phone;
  const _Row({required this.title, required this.detail, this.email, this.phone});
}
