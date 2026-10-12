import 'package:flutter/material.dart';
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

  Future<void> _showAddEmployeeDialog() async {
    final emailController = TextEditingController();
    String selectedRole = 'CASHIER';

    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.person_add_alt_1, color: Color(0xFF059669)),
              SizedBox(width: 10),
              Text('Añadir Empleado', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ingresa el correo electrónico del colaborador para vincularlo a tu empresa.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Correo Electrónico *',
                    hintText: 'empleado@gmail.com',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Rol y Privilegios:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 8),

                // Selector Cajero
                RadioListTile<String>(
                  value: 'CASHIER',
                  groupValue: selectedRole,
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFF059669),
                  title: const Text('Cajero / Vendedor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text(
                    'Recomendado. Solo registra ventas. Precios de compra y costos protegidos.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  onChanged: (val) => setDialogState(() => selectedRole = val!),
                ),

                // Selector Administrador
                RadioListTile<String>(
                  value: 'ADMIN',
                  groupValue: selectedRole,
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFF059669),
                  title: const Text('Administrador', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text(
                    'Puede ingresar inventario, modificar precios y ver márgenes de ganancia.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  onChanged: (val) => setDialogState(() => selectedRole = val!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                final email = emailController.text.trim();
                if (email.isEmpty || !email.contains('@')) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ingresa un correo válido')),
                  );
                  return;
                }
                try {
                  await _teamRepo.addMember(
                    businessId: widget.business.id,
                    email: email,
                    role: selectedRole,
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('Vincular'),
            ),
          ],
        ),
      ),
    );

    if (added == true) {
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Empleado vinculado exitosamente'),
            backgroundColor: Color(0xFF059669),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Equipo • ${widget.business.name}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
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
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFA7F3D0)),
                  ),
                  child: const Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Color(0xFF059669),
                        child: Icon(Icons.people_alt_outlined, color: Colors.white),
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Gestión de Empleados y Roles',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF065F46)),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Los cajeros solo registran ventas. Tus costos de compra e ingresos globales están protegidos.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF047857), height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Miembros del Equipo (${_members.length + 1})',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                    ),
                    if (isOwner)
                      TextButton.icon(
                        onPressed: _showAddEmployeeDialog,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Añadir'),
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
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFECFDF5),
                      child: Icon(Icons.military_tech, color: Color(0xFF059669)),
                    ),
                    title: const Text('Dueño de la Empresa', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    subtitle: const Text('Acceso total e irrestricto', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF059669)),
                      ),
                      child: const Text(
                        'Dueño',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
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
                    final roleColor = isCashier ? const Color(0xFF2563EB) : const Color(0xFFD97706);
                    final roleBg = isCashier ? const Color(0xFFEFF6FF) : const Color(0xFFFEF3C7);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: roleBg,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: roleColor.withOpacity(0.5)),
                              ),
                              child: Text(
                                member.roleDisplayName,
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: roleColor),
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
