import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/stat_card.dart';
import '../../../../core/design/status_pill.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../business/models/business.dart';
import '../../../customers/data/debt_reminder.dart';
import '../../../home/navigation/app_places.dart';
import '../../../products/presentation/widgets/restock_order_modal.dart';
import '../../../suppliers/data/supplier_repository.dart';
import '../../../suppliers/models/supplier.dart';
import '../../data/home_data.dart';

/// Cómo se ve cada aviso: ícono, tono, título, detalle y pastilla. Lo usan la fila
/// del Inicio y su panel, para que digan siempre lo mismo.
extension AttentionLook on AttentionItem {
  IconData get icon => switch (kind) {
        AttentionKind.outOfStock || AttentionKind.lowStock => Icons.inventory_2_outlined,
        AttentionKind.overdueDebt => Icons.person_outline,
        AttentionKind.cashLeftOpen => Icons.point_of_sale_outlined,
      };

  AppTone get tone => switch (kind) {
        AttentionKind.outOfStock || AttentionKind.cashLeftOpen => AppTone.danger,
        AttentionKind.overdueDebt || AttentionKind.lowStock => AppTone.warning,
      };

  String get title => switch (kind) {
        AttentionKind.outOfStock => 'Se acabó $name',
        AttentionKind.lowStock => 'Quedan $stock de $name',
        AttentionKind.overdueDebt => '$name debe ${CurrencyFormatter.format(amount)}',
        AttentionKind.cashLeftOpen => 'La caja quedó abierta',
      };

  String get detail => switch (kind) {
        AttentionKind.outOfStock =>
          soldThisWeek > 0 ? 'Esta semana vendiste $soldThisWeek' : 'Sin unidades para vender',
        AttentionKind.lowStock => 'Mínimo $minStock${soldThisWeek > 0 ? ' · vendiste $soldThisWeek esta semana' : ''}',
        AttentionKind.overdueDebt => neverPaid ? 'Hace $days días · no ha abonado' : 'Último abono hace $days días',
        AttentionKind.cashLeftOpen => 'Desde el ${DateFormat("d MMM, h:mm a", 'es_CO').format(since!)}',
      };

  String get pill => switch (kind) {
        AttentionKind.outOfStock => 'Agotado',
        AttentionKind.lowStock => 'Quedan $stock',
        AttentionKind.overdueDebt => 'Vencido',
        AttentionKind.cashLeftOpen => 'Sin cerrar',
      };
}

/// Fila de «Necesita atención» del Inicio para un aviso
class AttentionItemRow extends StatelessWidget {
  final AttentionItem item;
  final VoidCallback onTap;

  const AttentionItemRow({super.key, required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) =>
      AttentionRow(icon: item.icon, tone: item.tone, title: item.title, detail: item.detail, pill: item.pill, onTap: onTap);
}

/// Panel «Resolver»: qué pasó, por qué, la solución sugerida y el botón que la hace.
/// En el computador entra por la derecha; en el celular sube desde abajo.
class AttentionPanel {
  AttentionPanel._();

  static Future<void> show(
    BuildContext context, {
    required AttentionItem item,
    required Business business,
    required String userName,
    required ValueChanged<int> onNavigate,
  }) {
    final t = ToneColors.of(context, item.tone);
    return AppSidePanel.show<void>(
      context: context,
      title: item.title,
      subtitle: item.detail,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: t.soft, borderRadius: BorderRadius.circular(AppRadius.control)),
        child: Icon(item.icon, size: 20, color: t.strong),
      ),
      builder: (ctx) => _PanelBody(item: item, business: business, userName: userName, onNavigate: onNavigate, host: context),
    );
  }
}

class _PanelBody extends StatelessWidget {
  final AttentionItem item;
  final Business business;
  final String userName;
  final ValueChanged<int> onNavigate;

  /// La pantalla que abrió el panel: lo que se abre después de cerrarlo va sobre ella
  final BuildContext host;

  const _PanelBody({required this.item, required this.business, required this.userName, required this.onNavigate, required this.host});

  void _go(BuildContext context, int place) {
    Navigator.of(context).maybePop();
    onNavigate(place);
  }

  @override
  Widget build(BuildContext context) {
    final children = switch (item.kind) {
      AttentionKind.outOfStock || AttentionKind.lowStock => _stock(context),
      AttentionKind.overdueDebt => _debt(context),
      AttentionKind.cashLeftOpen => _cash(context),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children);
  }

  List<Widget> _stock(BuildContext context) {
    final out = item.kind == AttentionKind.outOfStock;
    final entry = item.lastEntry == null ? null : DateFormat("d 'de' MMMM", 'es_CO').format(item.lastEntry!);
    final why = [
      if (item.soldThisWeek > 0) 'Esta semana vendiste ${item.soldThisWeek}.' else 'Esta semana no se ha vendido.',
      if (entry != null) 'La última entrada fue el $entry.' else 'No tiene entradas de mercancía registradas.',
      'El mínimo es ${item.minStock}.',
    ].join(' ');
    // Si se vende más de lo que alcanza el mínimo, sugerir subirlo
    final suggestedMin = item.soldThisWeek > item.minStock ? item.soldThisWeek : null;
    return [
      _pills([
        StatusPill(out ? 'Alta' : 'Media', tone: out ? AppTone.danger : AppTone.warning),
        if (item.soldThisWeek > 0) StatusPill('Lo vendes ${item.soldThisWeek} veces por semana', tone: AppTone.warning),
      ]),
      _Reason(icon: '?', tone: AppTone.info, title: 'Por qué pasó', text: why),
      if (out && item.soldThisWeek > 0)
        _Reason(
          icon: '!',
          tone: AppTone.warning,
          title: 'Si nadie hace nada',
          text: 'Mientras no llegue, cada cliente que lo pida se va sin él. Esta semana lo pidieron ${item.soldThisWeek} veces.',
        ),
      FutureBuilder<Supplier?>(
        future: item.supplierId == null ? Future.value() : SupplierRepository.instance.getSupplier(item.supplierId!),
        builder: (context, snap) {
          final s = snap.data;
          final visit = (s?.visitDay ?? '').isEmpty ? null : 'pasa los ${s!.visitDay!.toLowerCase()}';
          return _Solution(
            title: s == null ? 'Pedirlo a tu proveedor' : 'Pedir a ${s.name}',
            detail: s == null
                ? 'Arma el pedido con lo que falta y envíalo por WhatsApp.'
                : 'Arma el pedido con lo que falta y envíalo por WhatsApp${visit == null ? '' : ' · $visit'}.',
            footer: suggestedMin == null
                ? null
                : 'Para que no se repita: sube el mínimo a $suggestedMin, porque se vende más que antes. Se cambia en el producto.',
            primary: 'Pedir al proveedor',
            onPrimary: () {
              Navigator.of(context).maybePop();
              if (host.mounted) RestockOrderModal.show(host, business: business, userName: userName, supplier: s);
            },
            secondary: 'Ver en Stock',
            onSecondary: () => _go(context, AppPlace.stock),
          );
        },
      ),
    ];
  }

  List<Widget> _debt(BuildContext context) {
    final message = DebtReminder.message(customerName: item.name, debtAmount: item.amount, businessName: business.name);
    final hasPhone = DebtReminder.normalizePhone(item.phone) != null;
    return [
      _pills([
        const StatusPill('Vencido', tone: AppTone.warning),
        StatusPill('Debe ${CurrencyFormatter.format(item.amount)}', tone: AppTone.neutral),
      ]),
      _Reason(
        icon: '?',
        tone: AppTone.info,
        title: 'Por qué pasó',
        text: item.neverPaid
            ? 'Fió hace ${item.days} días y todavía no ha abonado.'
            : 'Su último abono fue hace ${item.days} días. Pasados ${HomeRepository.overdueDays} días se considera vencido.',
      ),
      _Solution(
        title: 'Recordarle por WhatsApp',
        detail: hasPhone ? 'Le llega este mensaje a su celular:' : 'No tiene celular guardado: elige a quién enviarlo en WhatsApp.',
        quote: message,
        primary: 'Enviar cobro por WhatsApp',
        onPrimary: () {
          Navigator.of(context).maybePop();
          DebtReminder.send(customerName: item.name, debtAmount: item.amount, businessName: business.name, phone: item.phone);
        },
        secondary: 'Ver cliente',
        onSecondary: () => _go(context, AppPlace.personas),
      ),
    ];
  }

  List<Widget> _cash(BuildContext context) => [
        _Reason(
          icon: '?',
          tone: AppTone.info,
          title: 'Por qué pasó',
          text: 'El turno se abrió ${item.detail.toLowerCase()} y no se cerró. Mientras siga abierto, lo que se venda hoy se suma a ese turno y el cuadre no sale.',
        ),
        _Solution(
          title: 'Cerrar ese turno',
          detail: 'Cuenta el efectivo, ciérralo y abre la caja de hoy.',
          primary: 'Ir a la caja',
          onPrimary: () => _go(context, AppPlace.caja),
        ),
      ];

  Widget _pills(List<Widget> pills) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.lg),
        child: Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: pills),
      );
}

/// «Por qué pasó» / «Si nadie hace nada»
class _Reason extends StatelessWidget {
  final String icon;
  final AppTone tone;
  final String title;
  final String text;

  const _Reason({required this.icon, required this.tone, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    final t = ToneColors.of(context, tone);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: t.soft, shape: BoxShape.circle),
              child: Text(icon, style: AppText.small(context, weight: FontWeight.w700, color: t.text)),
            ),
          ),
          const SizedBox(width: AppSpace.md - 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.body(context, weight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(text, style: AppText.body(context, color: context.colors.inkMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Recuadro «Solución sugerida» con el borde del color del negocio y sus botones
class _Solution extends StatelessWidget {
  final String title;
  final String detail;
  final String? quote;
  final String? footer;
  final String primary;
  final VoidCallback onPrimary;
  final String? secondary;
  final VoidCallback? onSecondary;

  const _Solution({
    required this.title,
    required this.detail,
    this.quote,
    this.footer,
    required this.primary,
    required this.onPrimary,
    this.secondary,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpace.md + 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.control + 2),
            border: Border.all(color: c.accent, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('SOLUCIÓN SUGERIDA', padding: EdgeInsets.zero),
              const SizedBox(height: AppSpace.sm),
              Text(title, style: AppText.title(context)),
              const SizedBox(height: 2),
              Text(detail, style: AppText.small(context)),
              if (quote != null) ...[
                const SizedBox(height: AppSpace.md - 2),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpace.md),
                  decoration: BoxDecoration(color: c.paper, borderRadius: BorderRadius.circular(AppRadius.control)),
                  child: Text(quote!, style: AppText.body(context)),
                ),
              ],
            ],
          ),
        ),
        if (footer != null) ...[
          const SizedBox(height: AppSpace.md),
          Text(footer!, style: AppText.small(context)),
        ],
        const SizedBox(height: AppSpace.lg),
        Wrap(
          spacing: AppSpace.md - 2,
          runSpacing: AppSpace.sm,
          alignment: WrapAlignment.end,
          children: [
            if (secondary != null) OutlinedButton(onPressed: onSecondary, child: Text(secondary!)),
            FilledButton(onPressed: onPrimary, child: Text(primary)),
          ],
        ),
      ],
    );
  }
}
