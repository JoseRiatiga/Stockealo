import '../../../../core/theme/app_tokens.dart';
import '../business_identity.dart';
import 'join_business_dialog.dart';
import 'business_trash.dart';
import 'create_business_sheet.dart';
import 'package:flutter/material.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../legal/presentation/screens/legal_document_screen.dart';
import '../../../team/data/team_repository.dart';
import '../../data/business_repository.dart';
import '../../models/business.dart';

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

    if (mounted) {
      setState(() {
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
    final newBiz = await _businessRepo.createBusiness(
      name: data.name,
      userId: widget.userId,
      currency: data.currency,
      country: data.country,
      icon: data.icon,
      color: data.color,
    );
    _businessRepo.setActiveBusiness(newBiz);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _confirmLeaveBusiness(Business biz) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Salir de este equipo?'),
        content: Text('Ya no tendrás acceso a los productos ni ventas de "${biz.name}". Puedes volver a unirte con el código de invitación.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Has salido del equipo de "${biz.name}"')),
        );
      }
    }
  }

  Future<void> _showEditBusinessDialog(Business biz) async {
    final role = _rolesByBusinessId[biz.id] ?? 'CASHIER';
    if (role == 'CASHIER') {
      if (mounted) {
        AppToast.showPermission(
          context,
          'Solo el dueño o administradores pueden cambiar los datos de la empresa.',
        );
      }
      return;
    }

    final saved = await CreateBusinessSheet.edit(context, biz);
    if (saved != null) await _loadBusinesses();
  }

  Future<void> _confirmDeleteBusiness(Business biz) async {
    final typedController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final isMatch = typedController.text.trim() == biz.name.trim();
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
                  SizedBox(width: 8),
                  Expanded(child: Text('¿Mover a papelera?')),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'La empresa "${biz.name}" se moverá a la papelera. Tendrás 7 días para restaurarla antes de su eliminación definitiva.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(ctx).brightness == Brightness.dark
                          ? const Color(0xFFCBD5E1)
                          : const Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Para confirmar, escribe exactamente el nombre de la empresa:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(ctx).brightness == Brightness.dark
                          ? const Color(0xFFF8FAFC)
                          : const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).brightness == Brightness.dark
                          ? const Color(0xFF0F172A)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(ctx).brightness == Brightness.dark
                            ? const Color(0xFF334155)
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: SelectableText(
                      biz.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(ctx).brightness == Brightness.dark
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF0F172A),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: typedController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Escribe aquí para confirmar',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: isMatch ? const Color(0xFF059669) : Colors.red,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: isMatch ? () => Navigator.pop(ctx, true) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    disabledForegroundColor: Colors.grey.shade500,
                  ),
                  child: const Text('Eliminar y mover a papelera'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed == true) {
      await _businessRepo.softDeleteBusiness(biz.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Empresa "${biz.name}" movida a la papelera (conservada por 7 días)'),
          backgroundColor: const Color(0xFF334155),
        ),
      );
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
          Text('Tus negocios', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.ink)),
          const SizedBox(height: 2),
          Text(
            'Cada negocio tiene sus propios productos, ventas y clientes',
            style: TextStyle(fontSize: 13, color: c.inkMuted),
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
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text('Nuevo negocio'),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),

          if (_deletedBusinesses.isNotEmpty)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.delete_outline_rounded, color: c.inkMuted),
              title: Text('Papelera · ${_deletedBusinesses.length}'),
              subtitle: const Text('Se pueden recuperar durante 7 días'),
              trailing: Icon(Icons.chevron_right_rounded, color: c.inkMuted),
              onTap: () => BusinessTrash.show(context, userId: widget.userId, onChanged: _loadBusinesses),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.shield_outlined, color: c.inkMuted),
            title: const Text('Términos y privacidad'),
            trailing: Icon(Icons.chevron_right_rounded, color: c.inkMuted),
            onTap: () {
              Navigator.pop(context);
              LegalDocumentScreen.show(context);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout_rounded, color: c.danger),
            title: Text('Cerrar sesión', style: TextStyle(color: c.danger, fontWeight: FontWeight.w600)),
            onTap: () {
              Navigator.pop(context);
              AuthRepository.instance.logout();
              BusinessRepository.instance.setActiveBusiness(null);
              widget.onLogout?.call();
            },
          ),
        ],
      ),
    );
  }

  Widget _businessTile(Business biz) {
    final c = context.colors;
    final isSelected = _currentBusiness?.id == biz.id;
    final role = _rolesByBusinessId[biz.id] ?? 'CASHIER';
    final isOwner = role == 'OWNER';
    final canManage = isOwner || role == 'ADMIN';
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
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: c.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$roleLabel · ${biz.currency}',
                      style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                    ),
                  ],
                ),
              ),
              if (isSelected) Icon(Icons.check_circle_rounded, color: c.accent),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, color: c.inkMuted),
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
                  if (canManage) const PopupMenuItem(value: 'edit', child: Text('Editar negocio')),
                  if (isOwner)
                    PopupMenuItem(value: 'delete', child: Text('Mover a la papelera', style: TextStyle(color: c.danger))),
                  if (!isOwner)
                    PopupMenuItem(value: 'leave', child: Text('Salir del equipo', style: TextStyle(color: c.danger))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
