import 'package:flutter/material.dart';

import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/status_pill.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../data/branch_repository.dart';

/// Elegir la sede (0.18.0): las sedes abiertas con el estado de su caja, «Todas las
/// sedes» para ver los reportes juntos (dueño y administradores) y «Otro negocio…».
class BranchPickerSheet {
  BranchPickerSheet._();

  /// Sin [onOtherBusiness] (desde Vender o Caja) no aparece «Otro negocio…».
  static Future<void> show(BuildContext context, {VoidCallback? onOtherBusiness}) async {
    final repo = BranchRepository.instance;
    final cash = <String?, bool>{
      null: await BranchRepository.openCashSession(null),
      for (final b in repo.openBranches) b.id: await BranchRepository.openCashSession(b.id),
    };
    if (!context.mounted) return;
    final result = await AppSheet.show<String>(
      context: context,
      title: 'Elegir sede',
      builder: (ctx) {
        final c = ctx.colors;
        Widget option({required String value, required String title, String? subtitle, required bool selected, IconData? icon, bool enabled = true}) =>
            ListTile(
              enabled: enabled,
              leading: Icon(icon ?? (selected ? Icons.check_circle_outlined : Icons.place_outlined), color: selected ? c.accent : c.inkMuted),
              title: Text(title, style: AppText.body(ctx, weight: selected ? FontWeight.w700 : FontWeight.w500)),
              subtitle: subtitle == null ? null : Text(subtitle, style: AppText.caption(ctx)),
              onTap: () => Navigator.pop(ctx, value),
            );
        final all = repo.viewAll.value;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            option(
              value: 'main',
              // 0.18.1: «Principal (Principal)» repetía el nombre; si la renombran, «Centro · Principal»
              title: repo.mainName == BranchRepository.mainDefaultName ? repo.mainName : '${repo.mainName} · Principal',
              subtitle: cash[null] == true ? 'Caja abierta' : 'Caja cerrada',
              selected: !all && BranchRepository.active == null,
            ),
            for (final b in repo.openBranches)
              option(
                value: b.id,
                title: b.name,
                subtitle: b.isInactive ? 'Inactiva: se ve, pero no se vende (revisa tu plan)' : (cash[b.id] == true ? 'Caja abierta' : 'Caja cerrada'),
                selected: !all && BranchRepository.active == b.id,
              ),
            if (repo.canSwitch) ...[
              const Divider(),
              option(
                value: 'all',
                title: 'Todas las sedes',
                subtitle: 'Para ver reportes e Inicio juntos. Para vender, elige una sede.',
                selected: all,
                icon: Icons.grid_view_outlined,
              ),
            ],
            if (onOtherBusiness != null) ...[
              const Divider(),
              option(value: 'other', title: 'Otro negocio…', selected: false, icon: Icons.storefront_outlined),
            ],
          ],
        );
      },
    );
    switch (result) {
      case null:
        return;
      case 'other':
        onOtherBusiness?.call();
      case 'all':
        repo.setViewAll(true);
      case 'main':
        repo.setViewAll(false);
        await repo.choose(null);
      default:
        repo.setViewAll(false);
        await repo.choose(result);
    }
  }
}

/// «Todas las sedes» es solo para mirar (0.18.1): en Vender y Caja, en vez de «Abrir
/// caja» (que abriría la de la Principal), pide elegir una sede.
class AllBranchesNotice extends StatelessWidget {
  final String text;
  const AllBranchesNotice({super.key, this.text = 'Estás viendo todas las sedes. Para vender o abrir caja, elige una sede.'});

  @override
  Widget build(BuildContext context) {
    final t = ToneColors.of(context, AppTone.info);
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(color: t.soft, borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Row(
        children: [
          Icon(Icons.grid_view_outlined, color: t.strong),
          const SizedBox(width: AppSpace.md - 2),
          Expanded(child: Text(text, style: AppText.body(context, weight: FontWeight.w600, color: context.colors.ink))),
          const SizedBox(width: AppSpace.sm),
          FilledButton(onPressed: () => BranchPickerSheet.show(context), child: const Text('Elegir sede')),
        ],
      ),
    );
  }
}
