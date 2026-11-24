import 'dart:async';

import 'package:flutter/material.dart';

import '../core/design/country_flag.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/countries.dart';
import '../features/pro/data/pro_admin_service.dart';
import 'admin_user_detail.dart';
import 'admin_widgets.dart';

/// Todos los negocios creados, solo con lo necesario para administrar Stockealo:
/// nombre, dueño, país y si tiene Pro. Nunca productos, ventas, clientes ni dinero.
class AdminBusinessesPage extends StatefulWidget {
  const AdminBusinessesPage({super.key});

  @override
  State<AdminBusinessesPage> createState() => _AdminBusinessesPageState();
}

class _AdminBusinessesPageState extends State<AdminBusinessesPage> {
  List<AdminBusiness> _businesses = const [];
  bool _loading = true;
  String? _error;
  String _query = '';
  bool _onlyPro = false;
  Timer? _debounce;
  int _loadId = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final id = ++_loadId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ProAdminService.instance.findBusinesses(_query);
      if (mounted && id == _loadId) setState(() => _businesses = list);
    } catch (e) {
      if (mounted && id == _loadId) setState(() => _error = '$e');
    } finally {
      if (mounted && id == _loadId) setState(() => _loading = false);
    }
  }

  void _onQuery(String q) {
    _query = q.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final visible = _onlyPro ? _businesses.where((b) => b.pro).toList() : _businesses;
    final withPro = _businesses.where((b) => b.pro).length;
    final state = AdminLoadState(
      loading: _loading && _businesses.isEmpty,
      error: _error,
      empty: visible.isEmpty,
      emptyText: _query.isEmpty ? 'Todavía no hay negocios en la nube' : 'Ningún negocio coincide con «$_query»',
      emptyDetail: _query.isEmpty ? 'Aparecen cuando alguien activa la nube en su negocio.' : 'Prueba con otro nombre o con el correo del dueño.',
      emptyIcon: Icons.storefront_outlined,
      onRetry: _load,
    );
    return AdminPage(
      width: AdminWidth.full,
      title: 'Negocios',
      subtitle: _loading && _businesses.isEmpty
          ? null
          : '${_businesses.length}${_businesses.length >= 50 ? '+' : ''} · $withPro con Pro · '
              'solo nombre, dueño y país: los datos de cada negocio son privados',
      onRefresh: _load,
      children: [
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 320,
              child: TextField(
                onChanged: _onQuery,
                decoration: const InputDecoration(
                  hintText: 'Buscar por nombre o correo del dueño',
                  prefixIcon: Icon(Icons.search_outlined),
                  isDense: true,
                ),
              ),
            ),
            FilterChip(
              label: const Text('Solo con Pro'),
              selected: _onlyPro,
              onSelected: (v) => setState(() => _onlyPro = v),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        if (state.blocking)
          state
        else ...[
          // En el computador, encabezado de columnas (re-diseño del panel)
          if (MediaQuery.sizeOf(context).width >= 900)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.xs),
              child: Row(
                children: [
                  const SizedBox(width: 26 + AppSpace.md),
                  Expanded(flex: 3, child: Text('Negocio', style: AppText.caption(context, color: c.inkMuted))),
                  Expanded(flex: 3, child: Text('Dueño', style: AppText.caption(context, color: c.inkMuted))),
                  Expanded(flex: 2, child: Text('País', style: AppText.caption(context, color: c.inkMuted))),
                  SizedBox(width: 90, child: Text('Plan', style: AppText.caption(context, color: c.inkMuted))),
                  const SizedBox(width: 40 + 24),
                ],
              ),
            ),
          for (final b in visible) _row(c, b),
        ],
      ],
    );
  }

  /// Un negocio. Tocarlo abre la ficha de su dueño (antes la lista no hacía nada)
  Widget _row(StockealoColors c, AdminBusiness b) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final flag = b.country != null
        ? CountryFlag(code: b.country!, width: 26)
        : Icon(Icons.store_mall_directory_outlined, color: c.inkFaint);
    final plan = b.pro ? const AdminBadge('Pro', tone: AdminTone.good) : Text('Gratis', style: AppText.small(context, color: c.inkMuted));
    final copy = b.ownerEmail == null
        ? const SizedBox(width: 40)
        : IconButton(
            tooltip: 'Copiar correo del dueño',
            onPressed: () => adminCopy(context, b.ownerEmail!, 'Correo'),
            icon: Icon(Icons.copy_outlined, size: 18, color: c.inkMuted),
          );
    final open = b.ownerEmail == null ? null : () => AdminUserDetailDialog.show(context, b.ownerEmail!);
    return AdminCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
          child: Row(
            children: [
              flag,
              const SizedBox(width: AppSpace.md),
              if (wide) ...[
                Expanded(flex: 3, child: Text(b.name, overflow: TextOverflow.ellipsis, style: AppText.body(context, weight: FontWeight.w600))),
                Expanded(flex: 3, child: Text(b.ownerEmail ?? 'sin dueño', overflow: TextOverflow.ellipsis, style: AppText.small(context, color: c.inkMuted))),
                Expanded(
                  flex: 2,
                  child: Text(b.country == null ? '—' : countryByCode(b.country).name, overflow: TextOverflow.ellipsis, style: AppText.small(context, color: c.inkMuted)),
                ),
                SizedBox(width: 90, child: Align(alignment: Alignment.centerLeft, child: plan)),
              ] else
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(child: Text(b.name, overflow: TextOverflow.ellipsis, style: AppText.body(context, weight: FontWeight.w600))),
                        if (b.pro) ...[const SizedBox(width: AppSpace.sm), plan],
                      ]),
                      Text(
                        [b.ownerEmail ?? 'sin dueño', if (b.country != null) countryByCode(b.country).name].join(' · '),
                        overflow: TextOverflow.ellipsis,
                        style: AppText.small(context, color: c.inkMuted),
                      ),
                    ],
                  ),
                ),
              copy,
              Icon(Icons.chevron_right, size: 20, color: open == null ? Colors.transparent : c.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}
