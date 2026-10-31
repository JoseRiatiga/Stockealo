import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../business/models/business.dart';
import '../../data/activity_repository.dart';

/// Grupos de acciones para filtrar el registro
enum _ActivityFilter {
  all('Todo', {}),
  sales('Ventas', {ActivityAction.sale, ActivityAction.saleCancel}),
  inventory('Inventario', {
    ActivityAction.productCreate,
    ActivityAction.productUpdate,
    ActivityAction.priceChange,
    ActivityAction.productDelete,
    ActivityAction.stockAdjust,
    ActivityAction.shrinkage,
  }),
  money('Fiados y caja', {
    ActivityAction.debtPayment,
    ActivityAction.customerDelete,
    ActivityAction.cashOpen,
    ActivityAction.cashClose,
  }),
  team('Equipo', {
    ActivityAction.memberJoin,
    ActivityAction.memberAdd,
    ActivityAction.memberRemove,
    ActivityAction.roleChange,
  });

  final String label;
  final Set<String> actions;

  const _ActivityFilter(this.label, this.actions);

  bool matches(ActivityEntry e) => actions.isEmpty || actions.contains(e.action);
}

/// Actividad del equipo: quién hizo qué y cuándo. Solo para dueño y administradores.
class ActivityScreen extends StatefulWidget {
  final Business business;

  const ActivityScreen({super.key, required this.business});

  static Future<void> open(BuildContext context, Business business) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => ActivityScreen(business: business)));

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  late Future<List<ActivityEntry>> _entries = ActivityRepository.instance.list(widget.business.id);
  _ActivityFilter _filter = _ActivityFilter.all;
  String? _person;

  Future<void> _reload() async {
    final next = ActivityRepository.instance.list(widget.business.id);
    setState(() => _entries = next);
    await next;
  }

  static (IconData, Color Function(StockealoColors)) _style(String action) => switch (action) {
        ActivityAction.sale => (Icons.point_of_sale_rounded, (c) => c.success),
        ActivityAction.saleCancel => (Icons.undo_rounded, (c) => c.danger),
        ActivityAction.priceChange => (Icons.sell_outlined, (c) => c.warning),
        ActivityAction.productCreate => (Icons.add_box_outlined, (c) => c.accent),
        ActivityAction.productUpdate => (Icons.edit_outlined, (c) => c.inkMuted),
        ActivityAction.productDelete => (Icons.delete_outline_rounded, (c) => c.danger),
        ActivityAction.stockAdjust => (Icons.inventory_2_outlined, (c) => c.accent),
        ActivityAction.shrinkage => (Icons.remove_circle_outline_rounded, (c) => c.danger),
        ActivityAction.debtPayment => (Icons.payments_outlined, (c) => c.success),
        ActivityAction.customerDelete => (Icons.person_remove_outlined, (c) => c.danger),
        ActivityAction.cashOpen => (Icons.lock_open_rounded, (c) => c.accent),
        ActivityAction.cashClose => (Icons.lock_outline_rounded, (c) => c.accent),
        ActivityAction.memberJoin || ActivityAction.memberAdd => (Icons.person_add_alt_1_outlined, (c) => c.accent),
        ActivityAction.memberRemove => (Icons.person_remove_outlined, (c) => c.danger),
        ActivityAction.roleChange => (Icons.manage_accounts_outlined, (c) => c.warning),
        _ => (Icons.history_rounded, (c) => c.inkMuted),
      };

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final day = DateTime(d.year, d.month, d.day);
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return 'Hoy';
    if (day == today.subtract(const Duration(days: 1))) return 'Ayer';
    const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${d.day} ${months[d.month - 1]}${d.year == now.year ? '' : ' ${d.year}'}';
  }

  static String _time(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'a. m.' : 'p. m.'}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(
        backgroundColor: c.paper,
        surfaceTintColor: Colors.transparent,
        title: const Text('Actividad del equipo'),
      ),
      body: FutureBuilder<List<ActivityEntry>>(
        future: _entries,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return snapshot.hasError
                ? Center(child: Text('No se pudo cargar la actividad', style: TextStyle(color: c.inkMuted)))
                : const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data!;
          final people = {for (final e in all) e.actorEmail: e.actor};
          final visible = all.where((e) => _filter.matches(e) && (_person == null || e.actorEmail == _person)).toList();

          return RefreshIndicator(
            onRefresh: _reload,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _filters(c, people)),
                if (visible.isEmpty)
                  SliverFillRemaining(hasScrollBody: false, child: _empty(c, all.isEmpty))
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(AppSpace.lg, 0, AppSpace.lg, AppSpace.xxl),
                    sliver: SliverList.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final e = visible[i];
                        final newDay = i == 0 || _dayLabel(visible[i - 1].createdAt) != _dayLabel(e.createdAt);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (newDay)
                              Padding(
                                padding: EdgeInsets.fromLTRB(AppSpace.xs, i == 0 ? AppSpace.sm : AppSpace.xl, 0, AppSpace.sm),
                                child: Text(
                                  _dayLabel(e.createdAt).toUpperCase(),
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: c.inkFaint),
                                ),
                              ),
                            _row(c, e),
                          ],
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _filters(StockealoColors c, Map<String, String> people) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.xs, AppSpace.lg, AppSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final f in _ActivityFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpace.sm),
                    child: ChoiceChip(
                      label: Text(f.label),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          if (people.length > 1) ...[
            const SizedBox(height: AppSpace.sm),
            DropdownButtonFormField<String?>(
              value: _person,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Persona', isDense: true),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Todo el equipo')),
                for (final entry in people.entries)
                  DropdownMenuItem<String?>(value: entry.key, child: Text(entry.value, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _person = v),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(StockealoColors c, ActivityEntry e) {
    final (icon, colorOf) = _style(e.action);
    final color = colorOf(c);
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    style: TextStyle(fontSize: 14, height: 1.35, color: c.ink),
                    children: [
                      TextSpan(text: e.actor, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const TextSpan(text: ' '),
                      TextSpan(text: _lowerFirst(e.summary)),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  e.pending ? '${_time(e.createdAt)} · sin subir a la nube' : _time(e.createdAt),
                  style: TextStyle(fontSize: 12, color: e.pending ? c.warning : c.inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "Vendió 3 × Arroz" → "vendió 3 × Arroz", para leerse junto al nombre
  static String _lowerFirst(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

  Widget _empty(StockealoColors c, bool nothingYet) {
    return Padding(
      padding: const EdgeInsets.all(AppSpace.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_rounded, size: 44, color: c.inkFaint),
          const SizedBox(height: AppSpace.md),
          Text(
            nothingYet ? 'Todavía no hay actividad' : 'Nada con ese filtro',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            nothingYet
                ? 'Aquí verás quién vendió, cambió precios, ajustó el stock o cerró la caja.'
                : 'Prueba con otro tipo o con todo el equipo.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.4, color: c.inkMuted),
          ),
        ],
      ),
    );
  }
}
