import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/design/app_card.dart';
import '../../../../core/design/content_width.dart';
import '../../../../core/design/skeleton.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/status_pill.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../business/models/business.dart';
import '../../../pro/data/pro_service.dart';
import '../../../services/presentation/widgets/staff_section.dart';
import '../../data/team_repository.dart';
import '../../models/business_member.dart';

/// Ajustes › Equipo: dueño, colaboradores con su rol e invitación por código o QR
class EmployeesScreen extends StatefulWidget {
  final Business business;

  const EmployeesScreen({super.key, required this.business});

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  final _teamRepo = TeamRepository.instance;
  final _authRepo = AuthRepository.instance;

  List<BusinessMember> _members = [];
  bool _isLoading = true;
  String _currentUserRole = 'CASHIER';
  String? _ownerName;
  String? _ownerEmail;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final currentUser = _authRepo.currentUser;
    String role = 'CASHIER';
    if (currentUser != null) {
      role = await _teamRepo.getUserRoleInBusiness(
        businessId: widget.business.id,
        userId: currentUser.id,
        userEmail: currentUser.email,
      );
    }

    final list = await _teamRepo.getMembers(widget.business.id);

    // Si el usuario actual aparece en la lista de miembros, su rol explícito es la verdad absoluta
    final myMember = list.where((m) =>
        (m.userId != null && m.userId == currentUser?.id) ||
        (currentUser?.email != null && m.email.toLowerCase() == currentUser!.email.toLowerCase())).firstOrNull;
    if (myMember != null) {
      role = myMember.role;
    }

    // 1. Identificar al dueño real a través del miembro con rol 'OWNER'
    final ownerMember = list.where((m) => m.isOwner).firstOrNull;
    String? ownerName;
    String? ownerEmail;

    if (ownerMember != null) {
      ownerName = ownerMember.displayName;
      ownerEmail = ownerMember.email;
    } else {
      // 2. Si no hay fila de OWNER en business_members, buscar por userId de la empresa
      // PERO únicamente si el usuario actual realmente es OWNER (nunca si es cajero)
      if (currentUser != null && currentUser.id == widget.business.userId && role == 'OWNER') {
        ownerName = currentUser.name;
        ownerEmail = currentUser.email;
      }

      try {
        final db = await AppDatabase.instance.database;
        final ownerRes = await db.query(
          'users',
          where: 'id = ?',
          whereArgs: [widget.business.userId],
          limit: 1,
        );
        if (ownerRes.isNotEmpty) {
          ownerName ??= ownerRes.first['name'] as String?;
          ownerEmail ??= ownerRes.first['email'] as String?;
        }
      } catch (_) {}

      if ((ownerName == null || ownerName.trim().isEmpty) && SupabaseService.instance.client != null) {
        try {
          final cloudUser = await SupabaseService.instance.client!
              .from('users')
              .select('name, email')
              .eq('id', widget.business.userId)
              .maybeSingle();
          if (cloudUser != null) {
            ownerName ??= cloudUser['name'] as String?;
            ownerEmail ??= cloudUser['email'] as String?;
          }
        } catch (_) {}
      }
    }

    if (mounted) {
      setState(() {
        _currentUserRole = role;
        _members = list;
        _ownerName = ownerName;
        _ownerEmail = ownerEmail;
        _isLoading = false;
      });
    }
  }

  bool get isOwner => _currentUserRole == 'OWNER';
  bool get isAdmin => _currentUserRole == 'ADMIN';
  bool get canInvite => isOwner || isAdmin;

  Future<void> _showEditRoleDialog(BusinessMember member) async {
    String selectedRole = member.role;

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final c = context.colors;
          return AppDialog(
            icon: Icons.manage_accounts_outlined,
            tone: AppTone.accent,
            title: 'Ajustar rol',
            subtitle: member.displayName,
            maxWidth: 440,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpace.md),
                  decoration: BoxDecoration(
                    color: c.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    border: Border.all(color: c.line),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.email_outlined, size: 16, color: c.inkMuted),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Text(
                          member.email,
                          style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                Text(
                  'Nivel de permisos',
                  style: TextStyle(fontSize: AppText.sizeSmall, fontWeight: FontWeight.w600, color: c.ink),
                ),
                const SizedBox(height: AppSpace.sm),
                RadioGroup<String>(
                  groupValue: selectedRole,
                  onChanged: (val) => setDialogState(() => selectedRole = val!),
                  child: Column(
                    children: [
                    RadioListTile<String>(
                      value: 'CASHIER',
                      contentPadding: EdgeInsets.zero,
                      activeColor: c.accent,
                      title: Text('Cajero o vendedor',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppText.sizeBody, color: c.ink)),
                      subtitle: Text(
                        'Solo registra ventas. Los precios de compra y los costos quedan protegidos.',
                        style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted),
                      ),
                    ),
                    RadioListTile<String>(
                      value: 'ADMIN',
                      contentPadding: EdgeInsets.zero,
                      activeColor: c.accent,
                      title: Text('Administrador',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppText.sizeBody, color: c.ink)),
                      subtitle: Text(
                        'Puede ingresar inventario, cambiar precios y ver márgenes.',
                        style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted),
                      ),
                    ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: AppSpace.sm),
              FilledButton(
                onPressed: () async {
                  try {
                    await _teamRepo.updateRole(member.id, selectedRole);
                    if (ctx.mounted) Navigator.pop(ctx, true);
                  } catch (e) {
                    if (context.mounted) {
                      AppToast.showError(context, e.toString().replaceAll('Exception: ', ''));
                    }
                  }
                },
                child: const Text('Guardar rol'),
              ),
            ],
          );
        },
      ),
    );

    if (updated == true) {
      _loadData();
      if (mounted) {
        AppToast.showSuccess(
          context,
          'Rol de ${member.displayName} actualizado.',
          title: 'Equipo actualizado',
        );
      }
    }
  }

  Future<void> _removeMember(BusinessMember member) async {
    final confirm = await AppDialog.confirm(
      context: context,
      title: 'Quitar del equipo',
      message: '¿Seguro que quieres quitar a ${member.displayName} (${member.email}) del equipo de ${widget.business.name}?',
      confirmText: 'Quitar',
      destructive: true,
    );

    if (confirm == true) {
      await _teamRepo.removeMember(member.id);
      _loadData();
      if (mounted) {
        AppToast.showSuccess(
          context,
          '${member.displayName} ya no hace parte del equipo.',
          title: 'Desvinculado',
        );
      }
    }
  }

  Future<void> _checkAndShowInviteModal() async {
    if (!canInvite) {
      AppToast.showPermission(
        context,
        'Solo el dueño o los administradores pueden invitar.',
      );
      return;
    }

    final isCloudSync = await SupabaseService.instance.isCloudSyncEnabled();
    if (!isCloudSync) {
      if (!mounted) return;
      final accepted = await _showCloudConsentDialog();
      if (accepted != true) return;
    }

    if (!mounted) return;
    _showInviteQrModal();
  }

  Future<bool?> _showCloudConsentDialog() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final c = ctx.colors;
        return AppDialog(
          icon: Icons.cloud_sync_outlined,
          tone: AppTone.accent,
          title: 'Trabajar en equipo',
          subtitle: 'Se activa la sincronización en la nube',
          maxWidth: 460,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Para que tu equipo venda y vea existencias de "${widget.business.name}" desde sus dispositivos, '
                'los datos de este negocio se respaldan y sincronizan en la nube de Stockealo.',
                style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted, height: 1.4),
              ),
              const SizedBox(height: AppSpace.md),
              Container(
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: c.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(color: c.line),
                ),
                child: Column(
                  children: [
                    _buildConsentFeature(
                      icon: Icons.shield_outlined,
                      title: 'Privacidad',
                      subtitle: 'Solo tú y tu equipo autorizado tienen acceso a los datos.',
                    ),
                    Divider(height: AppSpace.lg, color: c.line),
                    _buildConsentFeature(
                      icon: Icons.wifi_off_outlined,
                      title: 'Ventas sin internet',
                      subtitle: 'Si se cae el internet, siguen vendiendo sin interrupción.',
                    ),
                    Divider(height: AppSpace.lg, color: c.line),
                    _buildConsentFeature(
                      icon: Icons.sync_alt_outlined,
                      title: 'Inventario al día',
                      subtitle: 'Las existencias se descuentan para todos.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                'Al continuar aceptas la sincronización en la nube según los Términos de servicio y la Política de privacidad.',
                style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkFaint),
              ),
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: AppSpace.sm),
            FilledButton.icon(
              icon: const Icon(Icons.check_outlined, size: 18),
              label: const Text('Aceptar y activar'),
              onPressed: () async {
                Navigator.pop(ctx, true);
                await SupabaseService.instance.setCloudSyncEnabled(true);
                SupabaseService.instance.syncToCloud();
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildConsentFeature({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: c.successSoft,
            borderRadius: BorderRadius.circular(AppSpace.sm),
          ),
          child: Icon(icon, size: 18, color: c.success),
        ),
        const SizedBox(width: AppSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: AppText.sizeCaption, fontWeight: FontWeight.w600, color: c.ink)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted)),
            ],
          ),
        ),
      ],
    );
  }

  void _showInviteQrModal() {
    if (!canInvite) {
      AppToast.showPermission(
        context,
        'Solo el dueño o los administradores pueden invitar.',
      );
      return;
    }
    final inviteCode = widget.business.inviteCode;
    final qrData = 'stockealo://join?biz=${widget.business.id}&code=$inviteCode';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) {
        final c = ctx.colors;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppSpace.xl,
            0,
            AppSpace.xl,
            MediaQuery.of(ctx).padding.bottom + AppSpace.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: c.successSoft,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: Icon(Icons.qr_code_2_outlined, color: c.success, size: 26),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Invitar al equipo',
                            style: TextStyle(fontSize: AppText.sizeHeading, fontWeight: FontWeight.w700, color: c.ink)),
                        Text(widget.business.name, style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xl),

              // El QR va siempre sobre blanco para que la cámara lo lea también en modo oscuro
              Container(
                padding: const EdgeInsets.all(AppSpace.lg),
                decoration: BoxDecoration(
                  color: AppPalette.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  border: Border.all(color: c.line),
                ),
                child: BarcodeWidget(
                  barcode: Barcode.qrCode(),
                  data: qrData,
                  width: 180,
                  height: 180,
                  color: AppPalette.ink,
                ),
              ),
              const SizedBox(height: AppSpace.lg),

              Text('O comparte este código de invitación',
                  style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted)),
              const SizedBox(height: AppSpace.sm),
              Container(
                padding: const EdgeInsets.only(left: AppSpace.lg, right: AppSpace.xs),
                decoration: BoxDecoration(
                  color: c.surfaceMuted,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(color: c.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      inviteCode,
                      style: TextStyle(
                        fontSize: AppText.sizeHeading,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.5,
                        color: c.success,
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    IconButton(
                      icon: Icon(Icons.copy_outlined, size: 20, color: c.success),
                      tooltip: 'Copiar código',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: inviteCode));
                        AppToast.showSuccess(
                          context,
                          'Código $inviteCode copiado.',
                          title: 'Código copiado',
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Compartir invitación'),
                  onPressed: () {
                    final text = 'Únete a mi equipo en Stockealo.\n\nNegocio: ${widget.business.name}\nCódigo de invitación: $inviteCode\n\nAbre la app Stockealo, elige "Soy colaborador" y escribe este código o escanea mi QR.';
                    Share.share(text);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Etiqueta de rol: dueño en verde, administrador en ámbar y cajero en azul
  Widget _roleChip({required String label, required Color fg, required Color bg, IconData? icon, VoidCallback? onTap}) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: fg),
                const SizedBox(width: AppSpace.xs),
              ],
              Text(label, style: TextStyle(fontSize: AppText.sizeCaption, fontWeight: FontWeight.w600, color: fg)),
              if (onTap != null) ...[
                const SizedBox(width: AppSpace.xs),
                Icon(Icons.edit_outlined, size: 12, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _youTag() {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('Tú', style: TextStyle(fontSize: AppText.sizeCaption, fontWeight: FontWeight.w700, color: c.inkMuted)),
    );
  }

  Widget _avatar(String name, {required Color fg, required Color bg}) {
    return CircleAvatar(
      radius: 20,
      backgroundColor: bg,
      child: Text(
        (name.trim().isNotEmpty ? name.trim().characters.first : '?').toUpperCase(),
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: AppText.sizeTitle, color: fg),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final employeesList = _members.where((m) => !m.isOwner).toList();
    final currentUser = _authRepo.currentUser;
    final isOwnerSelf = isOwner &&
        ((_ownerEmail != null && _ownerEmail!.toLowerCase() == currentUser?.email.toLowerCase()) ||
            (widget.business.userId == currentUser?.id));
    final ownerName = _ownerName?.trim().isNotEmpty == true ? _ownerName!.trim() : 'Dueño del negocio';

    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(
        title: const Text('Equipo'),
        actions: [
          if (canInvite)
            TextButton.icon(
              onPressed: _checkAndShowInviteModal,
              icon: const Icon(Icons.qr_code_2_outlined, size: 18),
              label: const Text('Invitar'),
            ),
        ],
      ),
      body: ContentWidth(
        child: _isLoading
            ? ListView(
                padding: const EdgeInsets.all(AppSpace.lg),
                children: const [
                  SkeletonListTile(),
                  SkeletonListTile(),
                  SkeletonListTile(),
                ],
              )
            : RefreshIndicator(
                onRefresh: _loadData,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    AppSpace.lg,
                    AppSpace.lg,
                    AppSpace.lg,
                    MediaQuery.of(context).padding.bottom + AppSpace.xxl,
                  ),
                  children: [
                    Text(
                      widget.business.name,
                      style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      'Los cajeros solo registran ventas. Tus costos de compra y tus ganancias quedan protegidos.',
                      style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted, height: 1.35),
                    ),
                    const SizedBox(height: AppSpace.lg),

                    // Código de invitación (solo dueño o administrador)
                    if (canInvite) ...[
                      AppCard(
                        onTap: _checkAndShowInviteModal,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: c.successSoft,
                                borderRadius: BorderRadius.circular(AppRadius.control),
                              ),
                              child: Icon(Icons.qr_code_scanner_outlined, color: c.success),
                            ),
                            const SizedBox(width: AppSpace.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Código ${widget.business.inviteCode}',
                                      style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
                                  Text('Compártelo con tu equipo para que se unan',
                                      style: TextStyle(color: c.inkMuted, fontSize: AppText.sizeCaption)),
                                ],
                              ),
                            ),
                            Text('Ver QR', style: TextStyle(color: c.accent, fontWeight: FontWeight.w600)),
                            Icon(Icons.chevron_right_outlined, color: c.inkFaint),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpace.xl),
                    ],

                    Text(
                      'Miembros (${employeesList.length + 1})',
                      style: TextStyle(fontSize: AppText.sizeBodyLarge, fontWeight: FontWeight.w700, color: c.ink),
                    ),
                    const SizedBox(height: AppSpace.sm),

                    // Dueño
                    AppCard(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.md),
                      child: Row(
                        children: [
                          _avatar(ownerName, fg: c.success, bg: c.successSoft),
                          const SizedBox(width: AppSpace.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        ownerName,
                                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppText.sizeBodyLarge, color: c.ink),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (isOwnerSelf) _youTag(),
                                  ],
                                ),
                                if (_ownerEmail != null && _ownerEmail!.isNotEmpty)
                                  Text(
                                    _ownerEmail!,
                                    style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                Text('Acceso total', style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkFaint)),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpace.sm),
                          _roleChip(
                            label: 'Dueño',
                            fg: c.success,
                            bg: c.successSoft,
                            icon: Icons.workspace_premium_outlined,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpace.sm),

                    // Colaboradores (sin el dueño para no repetirlo)
                    if (employeesList.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: AppSpace.xxl),
                        child: Column(
                          children: [
                            Icon(Icons.person_outline_outlined, size: 48, color: c.inkFaint),
                            const SizedBox(height: AppSpace.md),
                            Text(
                              canInvite
                                  ? 'Aún no hay colaboradores en este negocio'
                                  : 'No hay más miembros en este equipo',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: c.ink, fontWeight: FontWeight.w600, fontSize: AppText.sizeBodyLarge),
                            ),
                            if (canInvite) ...[
                              const SizedBox(height: AppSpace.xs),
                              Text(
                                'Comparte el código de invitación para que se unan.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: c.inkMuted, fontSize: AppText.sizeSmall),
                              ),
                            ],
                          ],
                        ),
                      )
                    else
                      for (final member in employeesList) ...[
                        _memberCard(member),
                        const SizedBox(height: AppSpace.sm),
                      ],

                    // Con Pro Servicios: quienes hacen los servicios (sin cuenta en la app)
                    ValueListenableBuilder<ProStatus>(
                      valueListenable: ProService.instance.status,
                      builder: (context, pro, _) => pro.services
                          ? Padding(
                              padding: const EdgeInsets.only(top: AppSpace.xl),
                              child: StaffSection(business: widget.business, canEdit: canInvite),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _memberCard(BusinessMember member) {
    final c = context.colors;
    final currentUser = _authRepo.currentUser;
    final isSelf = (member.userId != null && member.userId == currentUser?.id) ||
        member.email.toLowerCase() == currentUser?.email.toLowerCase();
    final fg = member.isCashier ? c.info : c.warning;
    final bg = member.isCashier ? c.infoSoft : c.warningSoft;
    final canEdit = isOwner && !isSelf;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.sm, AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _avatar(member.displayName, fg: fg, bg: bg),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            member.displayName,
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppText.sizeBodyLarge, color: c.ink),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isSelf) _youTag(),
                      ],
                    ),
                    Text(
                      member.email,
                      style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (canEdit)
                IconButton(
                  icon: Icon(Icons.person_remove_outlined, color: c.danger, size: 20),
                  tooltip: 'Desvincular',
                  onPressed: () => _removeMember(member),
                ),
            ],
          ),
          Divider(height: AppSpace.xl, color: c.line),
          Padding(
            padding: const EdgeInsets.only(right: AppSpace.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    member.roleDescription,
                    style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                _roleChip(
                  label: member.roleDisplayName,
                  fg: fg,
                  bg: bg,
                  onTap: canEdit ? () => _showEditRoleDialog(member) : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
