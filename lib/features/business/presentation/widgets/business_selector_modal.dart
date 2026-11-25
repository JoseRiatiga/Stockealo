import '../../../../core/theme/app_tokens.dart';
import '../business_identity.dart';
import 'join_business_dialog.dart';
import 'business_trash.dart';
import 'create_business_sheet.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import '../../../../core/design/pro_crown.dart';
import '../../../pro/data/pro_service.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../team/data/team_repository.dart';
import '../../data/business_repository.dart';
import '../../models/business.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/permissions/permissions.dart';

class BusinessSelectorModal extends StatefulWidget {
  final String userId;
  final VoidCallback? onLogout;
  final bool isDialog;

  const BusinessSelectorModal({
    super.key,
    required this.userId,
    this.onLogout,
    this.isDialog = false,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String userId,
    VoidCallback? onLogout,
  }) {
    final isDesktop = MediaQuery.of(context).size.width >= 850;

    if (isDesktop) {
      return showDialog<bool>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BusinessSelectorModal(
                userId: userId,
                onLogout: onLogout,
                isDialog: true,
              ),
            ),
          ),
        ),
      );
    }

    return showModalBottomSheet<bool>(
      showDragHandle: false,
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BusinessSelectorModal(
        userId: userId,
        onLogout: onLogout,
        isDialog: false,
      ),
    );
  }

  @override
  State<BusinessSelectorModal> createState() => _BusinessSelectorModalState();
}

class _BusinessSelectorModalState extends State<BusinessSelectorModal> {
  final _businessRepo = BusinessRepository.instance;
  List<Business> _businesses = [];
  List<Business> _deletedBusinesses = [];
  Map<String, String> _rolesByBusinessId = {};
  Business? _currentBusiness;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBusinesses();
  }

  /// Plan Pro de cada negocio, para la corona (0.18.3)
  final Map<String, ProStatus?> _pro = {};

  Future<void> _loadBusinesses() async {
    final user = AuthRepository.instance.currentUser;
    final userEmail = user?.email ?? '';
    final list = await _businessRepo.getAllBusinesses(widget.userId, userEmail);
    final active = await _businessRepo.getActiveBusiness(widget.userId, userEmail);
    final deleted = await _businessRepo.getDeletedBusinesses(widget.userId);

    final Map<String, String> roles = {};
    for (final biz in list) {
      roles[biz.id] = await TeamRepository.instance.getUserRoleInBusiness(
        businessId: biz.id,
        userId: widget.userId,
        userEmail: userEmail,
      );
    }

    // Plan de cada negocio (0.18.3): primero lo guardado, luego lo de la nube
    final pro = <String, ProStatus?>{for (final biz in list) biz.id: await ProService.cached(biz.id)};
    unawaited(Future(() async {
      for (final biz in list) {
        final fresh = await ProService.instance.statusOf(biz.id);
        if (!mounted) return;
        setState(() => _pro[biz.id] = fresh);
      }
    }));

    if (mounted) {
      setState(() {
        _pro
          ..clear()
          ..addAll(pro);
        _businesses = list;
        _currentBusiness = active;
        _deletedBusinesses = deleted;
        _rolesByBusinessId = roles;
        _isLoading = false;
      });
    }
  }

  Future<void> _showCreateBusinessDialog() async {
    final data = await CreateBusinessSheet.show(context);
    if (data == null || !mounted) return;
    try {
      final newBiz = await _businessRepo.createBusiness(
        name: data.name,
        userId: widget.userId,
        currency: data.currency,
        country: data.country,
        timeZone: data.timeZone,
        icon: data.icon,
        color: data.color,
      );
      _businessRepo.setActiveBusiness(newBiz);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) AppToast.showError(context, 'No se pudo crear el negocio: $e');
    }
  }

  Future<void> _confirmLeaveBusiness(Business biz) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
title: '¿Salir de este equipo?',
content: Text('Ya no tendrás acceso a los productos ni ventas de "${biz.name}". Puedes volver a unirte con el código de invitación.'),
actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: context.colors.warning, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir del equipo'),
          ),
        ],
),
    );

    if (confirmed == true) {
      final user = AuthRepository.instance.currentUser;
      final userEmail = user?.email ?? '';
      final db = await AppDatabase.instance.database;

      // Eliminar membresía local
      await db.delete(
        'business_members',
        where: 'business_id = ? AND (user_id = ? OR LOWER(email) = ?)',
        whereArgs: [biz.id, widget.userId, userEmail.toLowerCase()],
      );

      // Eliminar de Supabase
      try {
        final client = SupabaseService.instance.client;
        if (client != null) {
          await client
              .from('business_members')
              .delete()
              .eq('business_id', biz.id)
              .eq('user_email', userEmail.toLowerCase());
        }
      } catch (_) {}

      // Si era la empresa activa, cambiar a otra
      if (_currentBusiness?.id == biz.id) {
        final otherBusinesses = _businesses.where((b) => b.id != biz.id).toList();
        if (otherBusinesses.isNotEmpty) {
          _businessRepo.setActiveBusiness(otherBusinesses.first);
        } else {
          _businessRepo.setActiveBusiness(null);
        }
      }

      await _loadBusinesses();
      if (mounted) {
        AppToast.show(context, message: 'Has salido del equipo de "${biz.name}"', type: ToastType.info);
      }
    }
  }

  Future<void> _showEditBusinessDialog(Business biz) async {
    final role = _rolesByBusinessId[biz.id] ?? 'CASHIER';
    if (!Permissions.can(role, Perm.businessInfo)) {
      if (mounted) {
        AppToast.showPermission(
          context,
          'Solo el dueño o administradores pueden cambiar los datos del negocio.',
        );
      }
      return;
    }

    final saved = await CreateBusinessSheet.edit(context, biz);
    if (saved != null) await _loadBusinesses();
  }

  Future<void> _confirmDeleteBusiness(Business biz) async {
    final confirmed = await BusinessTrash.confirmMove(context, biz);

    if (confirmed == true) {
      await _businessRepo.softDeleteBusiness(biz.id);
      if (!mounted) return;
      AppToast.show(context, message: 'Negocio "${biz.name}" movido a la papelera (se conserva 7 días)', type: ToastType.info);
      await _loadBusinesses();
      if (_currentBusiness == null || _currentBusiness?.id == biz.id) {
        if (_businesses.isNotEmpty) {
          _businessRepo.setActiveBusiness(_businesses.first);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.md,
        AppSpace.xl,
        widget.isDialog ? AppSpace.xl : MediaQuery.of(context).padding.bottom + AppSpace.lg,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: widget.isDialog
            ? BorderRadius.circular(AppRadius.sheet)
            : const BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.isDialog)
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpace.lg),
                decoration: BoxDecoration(color: c.lineStrong, borderRadius: BorderRadius.circular(2)),
              ),
            ),
          Text('Tus negocios', style: TextStyle(fontSize: AppText.sizeHeading, fontWeight: FontWeight.w700, color: c.ink)),
          const SizedBox(height: 2),
          Text(
            'Cada negocio tiene sus propios productos, ventas y clientes',
            style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted),
          ),
          const SizedBox(height: AppSpace.lg),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(AppSpace.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_businesses.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
              child: Text(
                'Aún no tienes negocios. Crea el tuyo o únete al de tu equipo.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.inkMuted),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _businesses.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppSpace.sm),
                itemBuilder: (context, index) => _businessTile(_businesses[index]),
              ),
            ),
          const SizedBox(height: AppSpace.lg),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => JoinBusinessDialog.show(context, userId: widget.userId),
                  icon: const Icon(Icons.group_add_outlined, size: 18),
                  label: const Text('Unirme'),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _showCreateBusinessDialog,
                  icon: const Icon(Icons.add_outlined, size: 20),
                  label: const Text('Nuevo negocio'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),

          if (_deletedBusinesses.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline_outlined, color: c.inkMuted),
              title: Text('Papelera · ${_deletedBusinesses.length}'),
              subtitle: const Text('Se pueden recuperar durante 7 días'),
              trailing: Icon(Icons.chevron_right_outlined, color: c.inkMuted),
              onTap: () => BusinessTrash.show(context, userId: widget.userId, onChanged: _loadBusinesses),
            ),
          // «Términos» vive en Ajustes y «Cerrar sesión» en «Salir» del menú lateral
          // (0.16.7, decisión D5, hallazgo 50)
        ],
      ),
    );
  }

  Widget _businessTile(Business biz) {
    final c = context.colors;
    final isSelected = _currentBusiness?.id == biz.id;
    final role = _rolesByBusinessId[biz.id] ?? 'CASHIER';
    final isOwner = role == 'OWNER';
    final canManage = Permissions.can(role, Perm.businessInfo);
    final roleLabel = isOwner ? 'Dueño' : (role == 'ADMIN' ? 'Administrador' : 'Cajero');

    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: BorderSide(color: isSelected ? c.accent : c.line, width: isSelected ? 1.6 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _businessRepo.setActiveBusiness(biz);
          Navigator.pop(context, true);
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.md, AppSpace.xs, AppSpace.md),
          child: Row(
            children: [
              BusinessAvatar(business: biz, size: 44),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      biz.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: AppText.sizeTitle, fontWeight: FontWeight.w600, color: c.ink),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            [roleLabel, biz.currency, if (_pro[biz.id]?.active == true) _pro[biz.id]!.kindLabel].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted),
                          ),
                        ),
                        if (_pro[biz.id]?.active == true) ...[const SizedBox(width: 4), const ProCrown(size: 14)],
                      ],
                    ),
                  ],
                ),
              ),
              if (isSelected) Icon(Icons.check_circle_outlined, color: c.accent),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_outlined, color: c.inkMuted),
                tooltip: 'Opciones de ${biz.name}',
                onSelected: (action) {
                  if (action == 'edit') {
                    _showEditBusinessDialog(biz);
                  } else if (action == 'delete') {
                    _confirmDeleteBusiness(biz);
                  } else if (action == 'leave') {
                    _confirmLeaveBusiness(biz);
                  }
                },
                itemBuilder: (_) => [
                  if (canManage) _menuItem('edit', Icons.edit_outlined, 'Editar negocio', c.ink),
                  if (isOwner) _menuItem('delete', Icons.delete_outline_outlined, 'Mover a la papelera', c.danger),
                  if (!isOwner) _menuItem('leave', Icons.logout_outlined, 'Salir del equipo', c.danger),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opción del menú ⋮ con ícono, como en el resto de la app
  PopupMenuItem<String> _menuItem(String value, IconData icon, String label, Color color) => PopupMenuItem(
        value: value,
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: AppSpace.md),
            Text(label, style: TextStyle(color: color)),
          ],
        ),
      );
}
