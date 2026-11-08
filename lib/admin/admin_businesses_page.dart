import 'dart:async';

import 'package:flutter/material.dart';

import '../core/design/country_flag.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/countries.dart';
import '../features/pro/data/pro_admin_service.dart';
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
      emptyText: _query.isEmpty ? 'Todavía no hay negocios en la nube.' : 'Ningún negocio coincide con "$_query".',
      onRetry: _load,
    );
    return AdminPage(
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
                  prefixIcon: Icon(Icons.search_rounded),
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
        else
          for (final b in visible)
            AdminCard(
              child: Row(
                children: [
                  if (b.country != null) ...[
                    CountryFlag(code: b.country!, width: 26),
                    const SizedBox(width: AppSpace.md),
                  ] else ...[
                    Icon(Icons.store_mall_directory_outlined, color: c.inkFaint),
                    const SizedBox(width: AppSpace.md),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(b.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
                            ),
                            if (b.pro) ...[
                              const SizedBox(width: AppSpace.sm),
                              const AdminBadge('Pro', tone: AdminTone.good),
                            ],
                          ],
                        ),
                        Text(
                          [
                            b.ownerEmail ?? 'sin dueño',
                            if (b.country != null) countryByCode(b.country).name,
                          ].join(' · '),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: c.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  if (b.ownerEmail != null)
                    IconButton(
                      tooltip: 'Copiar correo del dueño',
                      onPressed: () => adminCopy(context, b.ownerEmail!, 'Correo'),
                      icon: Icon(Icons.copy_rounded, size: 18, color: c.inkMuted),
                    ),
                ],
              ),
            ),
      ],
    );
  }
}
