import 'package:flutter/material.dart';
import '../../../../core/widgets/app_toast.dart';
import 'quick_actions_catalog.dart';

/// Hoja para elegir qué acciones rápidas se muestran en el panel.
class QuickActionsCustomizer {
  /// Devuelve la nueva selección, o null si el usuario canceló.
  static Future<List<String>?> show(BuildContext context, {required List<String> current}) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedIds = List<String>.from(current);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            final availableToAdd = kAvailableQuickActions
                .where((a) => !selectedIds.contains(a.id))
                .toList();

            return Container(
              height: MediaQuery.of(ctx).size.height * 0.82,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.fromLTRB(
                20,
                16,
                20,
                MediaQuery.of(ctx).padding.bottom + 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Personalizar y Ordenar',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Arrastra con ☰ para fijar el orden que prefieras',
                            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: selectedIds.length >= 2 && selectedIds.length <= 5
                              ? const Color(0xFFECFDF5)
                              : const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selectedIds.length >= 2 && selectedIds.length <= 5
                                ? const Color(0xFF10B981)
                                : Colors.red,
                          ),
                        ),
                        child: Text(
                          '${selectedIds.length} / 5',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: selectedIds.length >= 2 && selectedIds.length <= 5
                                ? const Color(0xFF059669)
                                : Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'ACCIONES ACTIVAS EN TU INICIO (ARRASTRA PARA ORDENAR)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Lista reordenable
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: selectedIds.length,
                            onReorder: (oldIndex, newIndex) {
                              setModalState(() {
                                if (oldIndex < newIndex) {
                                  newIndex -= 1;
                                }
                                final item = selectedIds.removeAt(oldIndex);
                                selectedIds.insert(newIndex, item);
                              });
                            },
                            itemBuilder: (context, index) {
                              final actionId = selectedIds[index];
                              final action = kAvailableQuickActions.firstWhere(
                                (a) => a.id == actionId,
                                orElse: () => kAvailableQuickActions.first,
                              );

                              return Container(
                                key: ValueKey(action.id),
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF059669).withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '#${index + 1}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF059669),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    CircleAvatar(
                                      radius: 16,
                                      backgroundColor: action.color.withOpacity(0.12),
                                      child: Icon(action.icon, color: action.color, size: 18),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            action.label,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                          ),
                                          Text(
                                            action.description,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
                                      tooltip: 'Quitar de accesos activos',
                                      onPressed: () {
                                        if (selectedIds.length > 2) {
                                          setModalState(() => selectedIds.removeAt(index));
                                        } else {
                                          AppToast.show(
                                            ctx,
                                            message: 'Debes mantener al menos 2 accesos activos',
                                            type: ToastType.warning,
                                          );
                                        }
                                      },
                                    ),
                                    ReorderableDragStartListener(
                                      index: index,
                                      child: const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 4),
                                        child: Icon(Icons.drag_handle_rounded, color: Color(0xFF64748B)),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),

                          if (availableToAdd.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(
                              'DISPONIBLES PARA AGREGAR (+)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: availableToAdd.map((action) {
                                return ActionChip(
                                  avatar: Icon(action.icon, size: 16, color: action.color),
                                  label: Text(
                                    '+ ${action.label}',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                  backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                                  side: BorderSide(
                                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                                  ),
                                  onPressed: () {
                                    setModalState(() {
                                      if (selectedIds.length < 5) {
                                        selectedIds.add(action.id);
                                      } else {
                                        AppToast.show(
                                          ctx,
                                          message: 'Máximo 5 acciones para mantener la pantalla ordenada',
                                          type: ToastType.warning,
                                        );
                                      }
                                    });
                                  },
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx, true);
                      },
                      child: const Text('Guardar Orden y Accesos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    return saved == true ? selectedIds : null;
  }
}
