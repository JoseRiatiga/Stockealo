import 'package:flutter/material.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/design/app_card.dart';
import '../../../../core/services/data_events.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../business/models/business.dart';
import '../../../home/navigation/app_places.dart';
import '../../../store/data/online_store_service.dart';
import '../../../team/presentation/screens/employees_screen.dart';
import '../../../home/navigation/app_pane.dart';

/// Un paso de «Primeros pasos»
class FirstStep {
  final String label;
  final bool done;
  final VoidCallback? go;
  const FirstStep(this.label, {required this.done, this.go});
}

/// Primeros pasos para un negocio nuevo (0.16.0, fase 5): crear el primer producto,
/// abrir la caja, la primera venta, invitar al equipo y publicar la tienda. Lo ve el
/// dueño; desaparece al terminar o con «Ya sé usarla».
class FirstStepsCard extends StatefulWidget {
  final Business business;

  /// Para las pruebas: la tienda publicada o no (por defecto, la nube)
  final bool? storePublished;
  final DateTime? now;

  const FirstStepsCard({super.key, required this.business, this.storePublished, this.now});

  static String hiddenKey(String businessId) => 'first_steps_hidden_$businessId';

  /// Un negocio deja de ser «nuevo» a los 60 días
  static const newForDays = 60;

  @override
  State<FirstStepsCard> createState() => _FirstStepsCardState();
}

class _FirstStepsCardState extends State<FirstStepsCard> {
  List<FirstStep>? _steps;

  @override
  void initState() {
    super.initState();
    DataEvents.instance.salesVersion.addListener(_load);
    DataEvents.instance.productsVersion.addListener(_load);
    DataEvents.instance.cashVersion.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    DataEvents.instance.salesVersion.removeListener(_load);
    DataEvents.instance.productsVersion.removeListener(_load);
    DataEvents.instance.cashVersion.removeListener(_load);
    super.dispose();
  }

  Future<int> _count(String sql, List<Object?> args) async {
    final rows = await (await AppDatabase.instance.database).rawQuery(sql, args);
    return (rows.first.values.first as num?)?.toInt() ?? 0;
  }

  Future<void> _load() async {
    // Inicio no se cae si la base se cerró mientras cargaba (cerrar sesión, cambiar de cuenta)
    try {
      await _loadNow();
    } catch (e) {
      debugPrint('Inicio: no se pudo cargar: $e');
    }
  }

  Future<void> _loadNow() async {
    final b = widget.business;
    final now = widget.now ?? DateTime.now();
    if (now.difference(b.createdAt).inDays > FirstStepsCard.newForDays ||
        await AppDatabase.instance.getSetting(FirstStepsCard.hiddenKey(b.id)) == '1') {
      if (mounted) setState(() => _steps = const []);
      return;
    }
    final products = await _count('SELECT COUNT(*) FROM products WHERE business_id = ? AND COALESCE(is_active, 1) = 1', [b.id]);
    final cash = await _count('SELECT COUNT(*) FROM cash_sessions WHERE business_id = ?', [b.id]);
    final sales = await _count('SELECT COUNT(*) FROM sales WHERE business_id = ?', [b.id]);
    final team = await _count('SELECT COUNT(*) FROM business_members WHERE business_id = ?', [b.id]);
    var published = widget.storePublished;
    if (published == null) {
      try {
        published = (await OnlineStoreService.instance.getMine(b.id))?.enabled ?? false;
      } catch (_) {
        published = false;
      }
    }
    final steps = [
      FirstStep('Crea tu primer producto', done: products > 0, go: () => AppPlace.go(AppPlace.productos)),
      // Un negocio nuevo trae la caja apagada: primero hay que activarla (0.16.3)
      b.cashRegisterEnabled
          ? FirstStep('Abre la caja', done: cash > 0, go: () => AppPlace.go(AppPlace.caja))
          : FirstStep('Activa la caja', done: false, go: () => AppPlace.go(AppPlace.caja)),
      FirstStep('Haz tu primera venta', done: sales > 0, go: () => AppPlace.go(AppPlace.vender)),
      FirstStep(
        'Invita a alguien de tu equipo',
        done: team > 1,
        go: () => AppPane.open(context, (_) => EmployeesScreen(business: b)),
      ),
      FirstStep('Publica tu tienda en línea', done: published, go: () => AppPlace.go(AppPlace.tienda)),
    ];
    if (mounted) setState(() => _steps = steps.every((s) => s.done) ? const [] : steps);
  }

  Future<void> _hide() async {
    await AppDatabase.instance.setSetting(FirstStepsCard.hiddenKey(widget.business.id), '1');
    if (mounted) setState(() => _steps = const []);
  }

  @override
  Widget build(BuildContext context) {
    final steps = _steps;
    if (steps == null || steps.isEmpty) return const SizedBox.shrink();
    final c = context.colors;
    final done = steps.where((s) => s.done).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Primeros pasos · $done de ${steps.length}', style: AppText.title(context))),
                TextButton(onPressed: _hide, child: const Text('Ya sé usarla')),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(value: done / steps.length, minHeight: 6, color: c.success, backgroundColor: c.surfaceMuted),
            ),
            const SizedBox(height: AppSpace.sm),
            for (final s in steps)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: Icon(s.done ? Icons.check_circle_outlined : Icons.radio_button_unchecked_outlined,
                    color: s.done ? c.success : c.inkFaint),
                title: Text(
                  s.label,
                  style: AppText.body(context, color: s.done ? c.inkMuted : c.ink).copyWith(
                    decoration: s.done ? TextDecoration.lineThrough : null,
                  ),
                ),
                trailing: s.done ? null : const Icon(Icons.chevron_right),
                onTap: s.done ? null : s.go,
              ),
          ],
        ),
      ),
    );
  }
}
