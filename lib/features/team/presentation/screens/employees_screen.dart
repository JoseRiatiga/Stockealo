import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:share_plus/share_plus.dart';
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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final currentUser = _authRepo.currentUser;
    if (currentUser != null) {
      _currentUserRole = await _teamRepo.getUserRoleInBusiness(
        businessId: widget.business.id,
        userId: currentUser.id,
        userEmail: currentUser.email,
      );
    }

    final list = await _teamRepo.getMembers(widget.business.id);

    if (mounted) {
      setState(() {
        _members = list;
        _isLoading = false;
      });
    }
  }

  bool get isOwner => _currentUserRole == 'OWNER';

  Future<void> _showEditRoleDialog(BusinessMember member) async {
    String selectedRole = member.role;

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.manage_accounts_outlined, color: Color(0xFF059669)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ajustar Rol: ${member.email.split('@').first}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Correo: ${member.email}',
                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Selecciona el nivel de acceso:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              // Opción Cajero
              RadioListTile<String>(
                value: 'CASHIER',
                groupValue: selectedRole,
                contentPadding: EdgeInsets.zero,
                activeColor: const Color(0xFF059669),
                title: const Text('Cajero / Vendedor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text(
                  'Solo registra ventas. Precios de compra y costos protegidos.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                onChanged: (val) => setDialogState(() => selectedRole = val!),
              ),

              // Opción Administrador
              RadioListTile<String>(
                value: 'ADMIN',
                groupValue: selectedRole,
                contentPadding: EdgeInsets.zero,
                activeColor: const Color(0xFF059669),
                title: const Text('Administrador', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text(
                  'Puede ingresar inventario, modificar precios y ver márgenes.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                onChanged: (val) => setDialogState(() => selectedRole = val!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                try {
                  await _teamRepo.updateRole(member.id, selectedRole);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Guardar Rol'),
            ),
          ],
        ),
      ),
    );

    if (updated == true) {
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rol de ${member.email} actualizado correctamente'),
            backgroundColor: const Color(0xFF059669),
          ),
        );
      }
    }
  }

  Future<void> _removeMember(BusinessMember member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desvincular Empleado'),
        content: Text('¿Seguro que deseas remover a ${member.email} del equipo de ${widget.business.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desvincular'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _teamRepo.removeMember(member.id);
      _loadData();
    }
  }

  void _showInviteQrModal() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inviteCode = widget.business.inviteCode;
    final qrData = 'stockealo://join?biz=${widget.business.id}&code=$inviteCode';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('¡Código de invitación copiado!'),
                          backgroundColor: Color(0xFF059669),
                          duration: Duration(seconds: 2),
                        ),
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Equipo • ${widget.business.name}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            tooltip: 'Código y QR de Invitación',
            onPressed: _showInviteQrModal,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
          : ListView(
              padding: const EdgeInsets.all(16),
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

                // Tarjeta de Código de Invitación Rápido
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
                        onPressed: _showInviteQrModal,
                        child: const Text('Ver QR', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Miembros del Equipo (${_members.length + 1})',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
                    ),
                    if (isOwner)
                      TextButton.icon(
                        onPressed: _showInviteQrModal,
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: CircleAvatar(
                      backgroundColor: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                      child: Icon(Icons.military_tech, color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669)),
                    ),
                    title: const Text('Dueño de la Empresa', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    subtitle: Text('Acceso total e irrestricto', style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF059669)),
                      ),
                      child: Text(
                        'Dueño',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Lista de Empleados
                if (_members.isEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 20),
                    padding: const EdgeInsets.all(24),
                    alignment: Alignment.center,
                    child: const Column(
                      children: [
                        Icon(Icons.person_outline, size: 48, color: Color(0xFF94A3B8)),
                        SizedBox(height: 12),
                        Text(
                          'Aún no has agregado empleados a este negocio.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                        ),
                      ],
                    ),
                  )
                else
                  ..._members.map((member) {
                    final isCashier = member.isCashier;
                    final roleColor = isCashier
                        ? (isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB))
                        : (isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706));
                    final roleBg = isCashier
                        ? (isDark ? const Color(0xFF1E3A8A).withOpacity(0.4) : const Color(0xFFEFF6FF))
                        : (isDark ? const Color(0xFF78350F).withOpacity(0.4) : const Color(0xFFFEF3C7));

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        onTap: isOwner ? () => _showEditRoleDialog(member) : null,
                        leading: CircleAvatar(
                          backgroundColor: roleBg,
                          child: Icon(
                            isCashier ? Icons.point_of_sale : Icons.admin_panel_settings,
                            color: roleColor,
                          ),
                        ),
                        title: Text(member.email, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        subtitle: Text(
                          member.roleDescription,
                          style: TextStyle(fontSize: 11, color: secondaryTextColor),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: isOwner ? () => _showEditRoleDialog(member) : null,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: roleBg,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: roleColor.withOpacity(0.5)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      member.roleDisplayName,
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: roleColor),
                                    ),
                                    if (isOwner) ...[
                                      const SizedBox(width: 4),
                                      Icon(Icons.edit, size: 12, color: roleColor),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            if (isOwner)
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                tooltip: 'Desvincular',
                                onPressed: () => _removeMember(member),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}
