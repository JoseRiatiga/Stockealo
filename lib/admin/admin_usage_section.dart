import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';
import '../features/pro/data/pro_admin_service.dart';
import 'admin_widgets.dart';

/// Uso de la app en números totales: embudo de activación, Stocky con IA y versiones.
/// Nunca muestra el contenido de ningún negocio.
class AdminUsageSection extends StatefulWidget {
  const AdminUsageSection({super.key});

  @override
  State<AdminUsageSection> createState() => _AdminUsageSectionState();
}

class _AdminUsageSectionState extends State<AdminUsageSection> {
  Map<String, dynamic>? _funnel;
  Map<String, dynamic>? _ai;
  List<Map<String, dynamic>>? _versions;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final admin = ProAdminService.instance;
    try {
      final r = await Future.wait([admin.funnel(), admin.aiUsage(), admin.appVersions()]);
      if (!mounted) return;
      setState(() {
        _funnel = r[0] as Map<String, dynamic>;
        _ai = r[1] as Map<String, dynamic>;
        _versions = r[2] as List<Map<String, dynamic>>;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpace.xl),
        Text('Uso de la app', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.ink)),
        Text('Solo totales: nunca el contenido de un negocio', style: TextStyle(fontSize: 13, color: c.inkMuted)),
        const SizedBox(height: AppSpace.md),
        if (_error != null)
          Text(_error!, style: TextStyle(fontSize: 12.5, color: c.inkFaint))
        else if (_funnel == null)
          const Padding(padding: EdgeInsets.all(AppSpace.lg), child: Center(child: CircularProgressIndicator()))
        else ...[
          _funnelCard(c),
          _aiCard(c),
          _versionsCard(c),
        ],
      ],
    );
  }

  Widget _title(StockealoColors c, IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.md),
        child: Row(children: [
          Icon(icon, color: c.inkMuted),
          const SizedBox(width: AppSpace.md),
          Expanded(child: Text(text, style: TextStyle(fontWeight: FontWeight.w700, color: c.ink))),
        ]),
      );

  Widget _funnelCard(StockealoColors c) {
    final f = _funnel!;
    int n(String k) => (f[k] as num?)?.toInt() ?? 0;
    final steps = [
      ('Cuentas creadas', n('accounts'), n('accounts')),
      ('Crearon su negocio', n('with_business'), n('accounts')),
      ('Agregaron productos', n('with_products'), n('businesses')),
      ('Hicieron su primera venta', n('with_sales'), n('businesses')),
      ('Han tenido Pro', n('with_pro'), n('businesses')),
    ];
    final top = steps.first.$2 == 0 ? 1 : steps.first.$2;
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(c, Icons.filter_alt_outlined, 'Embudo de activación'),
          for (final (label, value, base) in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(label, style: TextStyle(color: c.ink))),
                    Text(
                      base > 0 && label != steps.first.$1 ? '$value · ${(value * 100 / base).round()} %' : '$value',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.inkMuted),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: LinearProgressIndicator(
                      value: (value / top).clamp(0.0, 1.0),
                      minHeight: 8,
                      color: c.accent,
                      backgroundColor: c.surfaceMuted,
                    ),
                  ),
                ],
              ),
            ),
          Text(
            'Desde "Agregaron productos", el porcentaje es sobre los ${n('businesses')} negocios.',
            style: TextStyle(fontSize: 11.5, color: c.inkFaint),
          ),
        ],
      ),
    );
  }

  Widget _aiCard(StockealoColors c) {
    final a = _ai!;
    final days = [for (final d in (a['days'] as List? ?? const [])) Map<String, dynamic>.from(d as Map)];
    final maxDay = days.fold<int>(1, (m, d) => ((d['count'] as num?)?.toInt() ?? 0) > m ? (d['count'] as num).toInt() : m);
    final providers = Map<String, dynamic>.from((a['providers_7d'] as Map?) ?? const {});
    final total7 = days.where((d) {
      final day = DateTime.tryParse('${d['day']}');
      return day != null && DateTime.now().difference(day).inDays < 7;
    }).fold<int>(0, (s, d) => s + ((d['count'] as num?)?.toInt() ?? 0));
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(c, Icons.auto_awesome_outlined, 'Stocky con IA'),
          Wrap(spacing: AppSpace.lg, runSpacing: AppSpace.sm, children: [
            _stat(c, '$total7', 'preguntas en 7 días'),
            _stat(c, '${a['users_today'] ?? 0}', 'cuentas la usaron hoy'),
            _stat(c, '${a['at_free_limit_today'] ?? 0}', 'llegaron al límite gratis hoy'),
          ]),
          if (days.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            SizedBox(
              height: 60,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final d in days)
                    Expanded(
                      child: Tooltip(
                        message: '${adminDate(DateTime.tryParse('${d['day']}'))}: ${d['count']}',
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          height: 4 + 56 * (((d['count'] as num?)?.toInt() ?? 0) / maxDay),
                          decoration: BoxDecoration(
                            color: c.accent.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Text('Preguntas por día, últimos 14 días', style: TextStyle(fontSize: 11.5, color: c.inkFaint)),
          ],
          if (providers.isNotEmpty) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              'Respuestas nuevas por proveedor (7 días): '
              '${providers.entries.map((e) => '${e.key} ${e.value}').join(' · ')}',
              style: TextStyle(fontSize: 12.5, color: c.inkMuted),
            ),
            if (providers.keys.length == 1 && providers.containsKey('rules'))
              Text('Solo respondieron las reglas: puede que las IA gratis estén fallando.',
                  style: TextStyle(fontSize: 12.5, color: c.warning)),
          ],
        ],
      ),
    );
  }

  Widget _stat(StockealoColors c, String value, String label) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.ink)),
          Text(label, style: TextStyle(fontSize: 12, color: c.inkMuted)),
        ],
      );

  Widget _versionsCard(StockealoColors c) {
    final v = _versions!;
    String platform(String p) => switch (p) {
          'android' => 'Android',
          'ios' => 'iPhone',
          'web' => 'Web',
          'windows' => 'Windows',
          _ => p,
        };
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(c, Icons.system_update_outlined, 'Versiones en uso (últimos 60 días)'),
          if (v.isEmpty)
            Text('Aún no hay datos: las versiones se registran desde la 0.9.9 al abrir la app.',
                style: TextStyle(fontSize: 12.5, color: c.inkMuted))
          else
            for (final row in v)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Expanded(child: Text('${platform('${row['platform']}')} ${row['version']}', style: TextStyle(color: c.ink))),
                  Text('${row['count']} ${row['count'] == 1 ? 'cuenta' : 'cuentas'}',
                      style: TextStyle(fontSize: 13, color: c.inkMuted)),
                ]),
              ),
        ],
      ),
    );
  }
}
