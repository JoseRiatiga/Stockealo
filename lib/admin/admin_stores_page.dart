import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_tokens.dart';
import '../features/pro/data/pro_admin_service.dart';
import 'admin_widgets.dart';

/// Tiendas en línea registradas
class AdminStoresPage extends StatefulWidget {
  const AdminStoresPage({super.key});

  @override
  State<AdminStoresPage> createState() => _AdminStoresPageState();
}

class _AdminStoresPageState extends State<AdminStoresPage> {
  List<AdminStore> _stores = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final stores = await ProAdminService.instance.listStores();
      if (mounted) setState(() => _stores = stores);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final live = _stores.where((s) => s.live).length;
    final state = AdminLoadState(
      loading: _loading,
      error: _error,
      empty: _stores.isEmpty,
      emptyText: 'Ningún negocio ha creado su tienda todavía.',
      onRetry: _load,
    );
    return AdminPage(
      title: 'Tiendas',
      subtitle: _loading ? null : '${_stores.length} registradas · $live publicadas',
      onRefresh: _load,
      children: [
        if (state.blocking)
          state
        else
          for (final s in _stores)
            AdminCard(
              child: Row(
                children: [
                  Icon(Icons.storefront_outlined, color: s.live ? c.accent : c.inkFaint),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(s.businessName,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
                            ),
                            const SizedBox(width: AppSpace.sm),
                            AdminBadge(s.statusLabel,
                                tone: s.live ? AdminTone.good : (s.enabled ? AdminTone.warn : AdminTone.neutral)),
                          ],
                        ),
                        Text('stockealo.online/tienda/${s.slug}', style: TextStyle(fontSize: 13, color: c.accent)),
                        Text(
                          '${s.products} productos con stock · ${s.ownerEmail ?? 'sin dueño'} · '
                          'actualizada ${adminDate(s.updatedAt)}',
                          style: TextStyle(fontSize: 12, color: c.inkFaint),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copiar enlace',
                    onPressed: () => adminCopy(context, s.url, 'Enlace'),
                    icon: Icon(Icons.copy_rounded, size: 18, color: c.inkMuted),
                  ),
                  IconButton(
                    tooltip: 'Abrir tienda',
                    onPressed: () => launchUrl(Uri.parse(s.url), webOnlyWindowName: '_blank'),
                    icon: Icon(Icons.open_in_new_rounded, size: 18, color: c.inkMuted),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}
