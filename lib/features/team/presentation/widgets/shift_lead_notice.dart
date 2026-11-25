import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../business/data/branch_repository.dart';
import '../../data/shift_lead.dart';

/// En Inicio (0.18.5): «Estás a cargo de Norte hasta las 6:00 p. m.» para el encargado
/// de turno, con lo que puede hacer mientras tanto.
class ShiftLeadNotice extends StatelessWidget {
  const ShiftLeadNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DateTime?>(
      valueListenable: ShiftLead.until,
      builder: (context, until, _) {
        if (until == null || !until.isAfter(DateTime.now())) return const SizedBox.shrink();
        final c = context.colors;
        final branch = BranchRepository.instance.nameOf(BranchRepository.active);
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.lg),
          child: Container(
            padding: const EdgeInsets.all(AppSpace.lg),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: c.line),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.badge_outlined, color: c.accent),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Estás a cargo de $branch ${ShiftLead.describe(until)}',
                          style: AppText.bodyLarge(context, weight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        'Puedes recibir los traslados que llegan y cerrar la caja de otros. Se termina solo.',
                        style: AppText.small(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
