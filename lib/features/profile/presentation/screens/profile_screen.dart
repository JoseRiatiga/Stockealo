import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/utils/image_helper.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/models/app_user.dart';
import '../../../business/data/business_repository.dart';
import '../../../business/models/business.dart';
import '../../../legal/presentation/screens/legal_document_screen.dart';
import '../../../reports/data/excel_export_service.dart';
import '../../../team/presentation/screens/employees_screen.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback onLogout;

  const ProfileScreen({super.key, required this.onLogout});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authRepo = AuthRepository.instance;
  final _businessRepo = BusinessRepository.instance;

  late TextEditingController _nameController;
  late TextEditingController _phoneController;

  AppUser? _user;
  Business? _activeBusiness;
  String? _avatarPath;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _user = _authRepo.currentUser;
    _nameController = TextEditingController(text: _user?.name ?? '');
    _phoneController = TextEditingController(text: _user?.phone ?? '');
    _avatarPath = _user?.avatarPath;
    _loadActiveBusiness();
  }

  Future<void> _loadActiveBusiness() async {
    if (_user != null) {
      final biz = await _businessRepo.getActiveBusiness(_user!.id, _user!.email);
      if (mounted) {
        setState(() => _activeBusiness = biz);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar(ImageSource source) async {
    final path = source == ImageSource.camera
        ? await ImageHelper.pickFromCamera()
        : await ImageHelper.pickFromGallery();

    if (path != null) {
      setState(() => _avatarPath = path);
      if (_user != null) {
        await _authRepo.updateProfile(
          userId: _user!.id,
          avatarPath: path,
        );
      }
    }
  }

  void _showAvatarPickerModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Foto de Perfil', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFECFDF5),
                  child: Icon(Icons.camera_alt, color: Color(0xFF059669)),
                ),
                title: const Text('Tomar foto con la cámara'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAvatar(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFEFF6FF),
                  child: Icon(Icons.photo_library, color: Color(0xFF2563EB)),
                ),
                title: const Text('Elegir de la galería'),
                onTap: () {
                  Navigator.pop(context);
                  _pickAvatar(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (_user == null) return;
    setState(() => _isLoading = true);

    try {
      await _authRepo.updateProfile(
        userId: _user!.id,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        avatarPath: _avatarPath,
      );

      setState(() => _user = _authRepo.currentUser);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Perfil actualizado con éxito'),
            backgroundColor: Color(0xFF059669),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final currentPassController = TextEditingController();
    final newPassController = TextEditingController();
    final confirmPassController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cambiar Contraseña', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPassController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contraseña Actual', prefixIcon: Icon(Icons.lock_outline)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPassController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Nueva Contraseña', prefixIcon: Icon(Icons.lock_reset)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPassController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirmar Nueva Contraseña', prefixIcon: Icon(Icons.check_circle_outline)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () async {
              if (newPassController.text != confirmPassController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Las contraseñas no coinciden'), backgroundColor: Colors.orange),
                );
                return;
              }
              try {
                await _authRepo.changePassword(
                  userId: _user!.id,
                  currentPassword: currentPassController.text,
                  newPassword: newPassController.text,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Contraseña actualizada correctamente'), backgroundColor: Color(0xFF059669)),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString().replaceAll('Exception: ', '')), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportToExcel() async {
    if (_activeBusiness == null || _user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay una empresa activa seleccionada.'), backgroundColor: Colors.orange),
      );
      return;
    }

    // Modal de progreso
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          elevation: 6,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF059669)),
                SizedBox(height: 18),
                Text(
                  'Generando Excel (.xlsx)...',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                SizedBox(height: 6),
                Text(
                  'Inventario, Ventas y Clientes',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    bool dialogClosed = false;
    void closeDialog() {
      if (!dialogClosed && mounted) {
        dialogClosed = true;
        Navigator.pop(context);
      }
    }

    try {
      await ExcelExportService.instance.exportBusinessData(
        business: _activeBusiness!,
        userId: _user!.id,
        userEmail: _user!.email,
        onGenerated: closeDialog,
      );
      closeDialog();
    } catch (e) {
      closeDialog();
      if (mounted) {
        final errorMsg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Mi Perfil y Ajustes',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Avatar y bienvenida
          Center(
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 50,
                  backgroundColor: const Color(0xFFECFDF5),
                  backgroundImage: _avatarPath != null && File(_avatarPath!).existsSync()
                      ? FileImage(File(_avatarPath!))
                      : null,
                  child: _avatarPath == null
                      ? Text(
                          (user?.displayName.isNotEmpty == true ? user!.displayName[0] : 'U').toUpperCase(),
                          style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: InkWell(
                    onTap: _showAvatarPickerModal,
                    child: const CircleAvatar(
                      radius: 18,
                      backgroundColor: Color(0xFF059669),
                      child: Icon(Icons.camera_alt, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              user?.displayName ?? 'Usuario',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
            ),
          ),
          Center(
            child: Text(
              user?.email ?? '',
              style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
          ),
          const SizedBox(height: 24),

          // Sección Datos Personales
          const Text(
            'Datos Personales',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Nombre o Apodo Comercial',
              hintText: 'Ej. Don José Martínez',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),

          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Teléfono / WhatsApp',
              hintText: 'Ej. +57 300 123 4567',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _saveProfile,
              child: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Actualizar Datos'),
            ),
          ),
          const SizedBox(height: 28),

          // Accesos a Funcionalidades Clave
          const Text(
            'Herramientas y Equipo',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 10),

          if (_activeBusiness != null)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFECFDF5),
                  child: Icon(Icons.group_outlined, color: Color(0xFF059669)),
                ),
                title: Text('Equipo de ${_activeBusiness!.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Administrar empleados, cajeros y permisos', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EmployeesScreen(business: _activeBusiness!),
                    ),
                  );
                },
              ),
            ),

          if (_activeBusiness != null)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFF0FDF4),
                  child: Icon(Icons.table_chart_outlined, color: Color(0xFF16A34A)),
                ),
                title: const Text('Exportar a Excel (.xlsx)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Inventario, ventas y clientes en un solo libro', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                trailing: const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
                onTap: _exportToExcel,
              ),
            ),

          Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFEFF6FF),
                child: Icon(Icons.lock_reset, color: Color(0xFF2563EB)),
              ),
              title: const Text('Seguridad', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: const Text('Cambiar contraseña de acceso', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              trailing: const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
              onTap: _showChangePasswordDialog,
            ),
          ),

          Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFF8FAFC),
                child: Icon(Icons.shield_outlined, color: Color(0xFF475569)),
              ),
              title: const Text('Términos y Privacidad', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: const Text('Políticas y condiciones del servicio', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              trailing: const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
              onTap: () => LegalDocumentScreen.show(context),
            ),
          ),

          const SizedBox(height: 16),

          // Botón Cerrar Sesión
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Cerrar Sesión', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            onTap: widget.onLogout,
          ),

          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Stockealo v1.0.0 • Local-First Inventory',
              style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
