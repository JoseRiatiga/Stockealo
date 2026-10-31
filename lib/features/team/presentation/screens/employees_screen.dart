import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/modern_dialog.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../business/models/business.dart';
import '../../data/team_repository.dart';
import '../../models/business_member.dart';

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
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return ModernDialog(
            icon: Icons.manage_accounts_outlined,
            iconColor: const Color(0xFF059669),
            title: 'Ajustar Rol',
            subtitle: member.displayName,
            maxWidth: 440,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.email_outlined, size: 16, color: Color(0xFF64748B)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          member.email,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Nivel de permisos:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                // Opción Cajero
                RadioListTile<String>(
                  value: 'CASHIER',
                  groupValue: selectedRole,
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFF059669),
                  title: const Text('Cajero / Vendedor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                  subtitle: const Text(
                    'Solo registra ventas. Precios de compra y costos protegidos.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                  ),
                  onChanged: (val) => setDialogState(() => selectedRole = val!),
                ),

                // Opción Administrador
                RadioListTile<String>(
                  value: 'ADMIN',
                  groupValue: selectedRole,
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFF059669),
                  title: const Text('Administrador', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                  subtitle: const Text(
                    'Puede ingresar inventario, modificar precios y ver márgenes.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                  ),
                  onChanged: (val) => setDialogState(() => selectedRole = val!),
                ),
              ],
            ),
            actions: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  'Cancelar',
                  style: TextStyle(
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
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
                child: const Text('Guardar Rol', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
          'Rol de ${member.displayName} actualizado correctamente',
          title: 'Equipo Actualizado',
        );
      }
    }
  }

  Future<void> _removeMember(BusinessMember member) async {
    final confirm = await ModernConfirmDialog.show(
      context: context,
      title: 'Desvincular Empleado',
      message: '¿Seguro que deseas remover a ${member.displayName} (${member.email}) del equipo de ${widget.business.name}?',
      confirmText: 'Desvincular',
      isDestructive: true,
    );

    if (confirm == true) {
      await _teamRepo.removeMember(member.id);
      _loadData();
      if (mounted) {
        AppToast.showSuccess(
          context,
          '${member.displayName} ha sido desvinculado del equipo.',
          title: 'Empleado Desvinculado',
        );
      }
    }
  }

  Future<void> _checkAndShowInviteModal() async {
    if (!canInvite) {
      AppToast.showPermission(
        context,
        'Solo el dueño o administradores pueden generar códigos de invitación.',
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF059669).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.cloud_sync_outlined, color: Color(0xFF059669), size: 26),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Colaboración en la Nube',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Para invitar miembros a "${widget.business.name}" y que puedan vender o ver existencias desde sus dispositivos, los datos de esta empresa se respaldarán y sincronizarán en la nube de Stockealo.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Column(
                  children: [
                    _buildConsentFeature(
                      icon: Icons.shield_outlined,
                      title: 'Privacidad Garantizada',
                      subtitle: 'Tus datos están protegidos y sólo tú y tu equipo autorizado tienen acceso.',
                      isDark: isDark,
                    ),
                    const Divider(height: 16),
                    _buildConsentFeature(
                      icon: Icons.wifi_off_outlined,
                      title: 'Ventas Offline',
                      subtitle: 'Si falla el internet, siguen registrando ventas sin interrupción.',
                      isDark: isDark,
                    ),
                    const Divider(height: 16),
                    _buildConsentFeature(
                      icon: Icons.sync_alt,
                      title: 'Inventario en Tiempo Real',
                      subtitle: 'Las existencias se descuentan automáticamente para todos.',
                      isDark: isDark,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Al continuar, aceptas la sincronización en la nube según nuestros Términos de Servicio y Privacidad.',
                style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Aceptar y Activar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onPressed: () async {
              Navigator.pop(ctx, true);
              await SupabaseService.instance.setCloudSyncEnabled(true);
              SupabaseService.instance.syncToCloud();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildConsentFeature({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF059669).withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF059669)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
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
        'Solo el dueño o administradores pueden generar códigos de invitación.',
      );
      return;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inviteCode = widget.business.inviteCode;
    final qrData = 'stockealo://join?biz=${widget.business.id}&code=$inviteCode';

    showModalBottomSheet(
      showDragHandle: false,
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(
          24,
          20,
          24,
          MediaQuery.of(ctx).padding.bottom + 20,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF059669).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.qr_code_2, color: Color(0xFF059669), size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Invitar al Equipo',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        widget.business.name,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Contenedor del Código QR
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: BarcodeWidget(
                barcode: Barcode.qrCode(),
                data: qrData,
                width: 180,
                height: 180,
              ),
            ),
            const SizedBox(height: 18),

            // Badge del Código de Invitación
            const Text(
              'O comparte este Código de Invitación:',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    inviteCode,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.5,
                      color: Color(0xFF059669),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20, color: Color(0xFF059669)),
                    tooltip: 'Copiar código',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: inviteCode));
                      AppToast.showSuccess(
                        context,
                        'Código de invitación $inviteCode copiado al portapapeles.',
                        title: 'Código Copiado',
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Botón Compartir
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.share, size: 18),
                label: const Text('Compartir Invitación'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  final text = '¡Únete a mi equipo en Stockealo!\n\nEmpresa: ${widget.business.name}\nCódigo de Invitación: $inviteCode\n\nAbre la app Stockealo, selecciona "Soy Colaborador" e ingresa este código o escanea mi QR.';
                  Share.share(text);
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B);
    final secondaryTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    final employeesList = _members.where((m) => !m.isOwner).toList();
    final isOwnerSelf = isOwner &&
        ((_ownerEmail != null &&
                _ownerEmail!.toLowerCase() == _authRepo.currentUser?.email.toLowerCase()) ||
            (widget.business.userId == _authRepo.currentUser?.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Equipo • ${widget.business.name}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        actions: [
          if (canInvite)
            IconButton(
              icon: const Icon(Icons.qr_code_2),
              tooltip: 'Código y QR de Invitación',
              onPressed: _checkAndShowInviteModal,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                MediaQuery.of(context).padding.bottom + 28,
              ),
              children: [
                // Banner Informativo
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF064E3B).withOpacity(0.3) : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0),
                    ),
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Color(0xFF059669),
                        child: Icon(Icons.people_alt_outlined, color: Colors.white),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Gestión de Empleados y Roles',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF065F46),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Los cajeros solo registran ventas. Tus costos de compra e ingresos globales están protegidos.',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857),
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Tarjeta de Código de Invitación Rápido (Solo visible para Dueño / Admin)
                if (canInvite) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF059669).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.qr_code_scanner, color: Color(0xFF059669), size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Código: ${widget.business.inviteCode}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Comparte con tus empleados para vincularlos.',
                                style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _checkAndShowInviteModal,
                          child: const Text('Ver QR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Miembros del Equipo (${employeesList.length + 1})',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                    ),
                    if (canInvite)
                      TextButton.icon(
                        onPressed: _checkAndShowInviteModal,
                        icon: const Icon(Icons.qr_code, size: 18),
                        label: const Text('Invitar'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF059669),
                          textStyle: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                // Tarjeta Dueño / Fundador
                Card(
                  color: isDark ? const Color(0xFF131127) : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(
                      color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                      child: Text(
                        (_ownerName?.trim().isNotEmpty == true ? _ownerName!.trim()[0] : 'D').toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                        ),
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _ownerName?.trim().isNotEmpty == true ? _ownerName!.trim() : 'Dueño de la Empresa',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: primaryTextColor),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isOwnerSelf) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF059669).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Tú',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF059669),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_ownerEmail != null && _ownerEmail!.isNotEmpty)
                            Text(
                              _ownerEmail!,
                              style: TextStyle(fontSize: 12, color: secondaryTextColor),
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 2),
                          Text(
                            'Dueño Fundador • Acceso total e irrestricto',
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF059669)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.workspace_premium_rounded,
                            size: 13,
                            color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Dueño',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Lista de Colaboradores (excluye al dueño para no duplicarlo)
                if (employeesList.isEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 20),
                    padding: const EdgeInsets.all(24),
                    alignment: Alignment.center,
                    child: Column(
                      children: [
                        const Icon(Icons.person_outline, size: 48, color: Color(0xFF94A3B8)),
                        const SizedBox(height: 12),
                        Text(
                          canInvite
                              ? 'Aún no has agregado colaboradores a este negocio.'
                              : 'No hay más miembros registrados en este equipo.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                        ),
                      ],
                    ),
                  )
                else
                  ...employeesList.map((member) {
                    final currentUser = _authRepo.currentUser;
                    final isSelf = (member.userId != null && member.userId == currentUser?.id) ||
                        member.email.toLowerCase() == currentUser?.email.toLowerCase();
                    final isCashier = member.isCashier;
                    final roleColor = isCashier
                        ? (isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB))
                        : (isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706));
                    final roleBg = isCashier
                        ? (isDark ? const Color(0xFF1E3A8A).withOpacity(0.4) : const Color(0xFFEFF6FF))
                        : (isDark ? const Color(0xFF78350F).withOpacity(0.4) : const Color(0xFFFEF3C7));

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF131127) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? const Color(0xFF26214A) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: roleBg,
                                child: Text(
                                  (member.displayName.isNotEmpty ? member.displayName[0] : 'E').toUpperCase(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: roleColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            member.displayName,
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: primaryTextColor),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isSelf) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Tú',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      member.email,
                                      style: TextStyle(fontSize: 12, color: secondaryTextColor),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (isOwner && !isSelf)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                  tooltip: 'Desvincular',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _removeMember(member),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Divider(height: 1, color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  member.roleDescription,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              InkWell(
                                onTap: (isOwner && !isSelf) ? () => _showEditRoleDialog(member) : null,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: roleBg,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: roleColor.withOpacity(0.5)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        member.roleDisplayName,
                                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: roleColor),
                                      ),
                                      if (isOwner && !isSelf) ...[
                                        const SizedBox(width: 4),
                                        Icon(Icons.edit, size: 12, color: roleColor),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
            ),
            ),
    );
  }
}
