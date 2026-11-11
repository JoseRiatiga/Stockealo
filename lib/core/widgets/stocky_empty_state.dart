import 'package:flutter/material.dart';

import '../../features/auth/presentation/widgets/stocky_mascot.dart';
import '../theme/app_tokens.dart';

/// Lista vacía con Stocky: qué falta y, si hay, el botón para empezar
/// («Todavía no hay productos · Agregar el primero»).
class StockyEmptyState extends StatelessWidget {
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final StockyState mascotState;
  final double mascotSize;

  const StockyEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.mascotState = StockyState.idle,
    this.mascotSize = 85.0,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl, vertical: AppSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StockyMascot(size: mascotSize, state: mascotState),
            const SizedBox(height: AppSpace.lg),
            Text(title, textAlign: TextAlign.center, style: AppText.title(context)),
            const SizedBox(height: AppSpace.xs + 2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Text(message, textAlign: TextAlign.center, style: AppText.small(context)),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpace.lg + 2),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
