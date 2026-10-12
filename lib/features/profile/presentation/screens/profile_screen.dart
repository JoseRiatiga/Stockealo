import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/image_helper.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/models/app_user.dart';
import '../../../business/data/business_repository.dart';
import '../../../business/models/business.dart';
import '../../../legal/presentation/screens/legal_document_screen.dart';
import '../../../reports/data/excel_export_service.dart';
import '../../../reports/presentation/widgets/excel_import_modal.dart';
import '../../../team/presentation/screens/employees_screen.dart';
import '../../../../core/theme/theme_controller.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback onLogout;

  const ProfileScreen({super.key, required this.onLogout});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authRepo = AuthRepository.instance;
  final _businessRepo = BusinessRepository.instance;
  final _supabase = SupabaseService.instance;

  late TextEditingController _nameController;
  late TextEditingController _phoneController;

  AppUser? _user;
  Business? _activeBusiness;
  String? _avatarPath;
  bool _isLoading = false;
  bool _isEditingProfile = false;
  bool _isCloudSyncEnabled = false;
  bool _isManualSyncing = false;

  @override
  void initState() {
    super.initState();
    _user = _authRepo.currentUser;
    _nameController = TextEditingController(text: _user?.name ?? '');
    _phoneController = TextEditingController(text: _user?.phone ?? '');
    _avatarPath = _user?.avatarPath;
    _loadActiveBusiness();
    _loadCloudSyncStatus();
  }

  Future<void> _loadCloudSyncStatus() async {
    final enabled = await _supabase.isCloudSyncEnabled();
    if (mounted) {
      setState(() => _isCloudSyncEnabled = enabled);
    }
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

  Future<void> _toggleCloudSync(bool value) async {
    await _supabase.setCloudSyncEnabled(value);
    if (!mounted) return;
    setState(() => _isCloudSyncEnabled = value);

    if (value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('☁️ Sincronización en la nube activada. Respaldando datos...'),
          backgroundColor: Color(0xFF059669),
        ),
      );
      _runManualSync();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔒 Modo Local Privado activo. Tus datos ya no se sincronizan a internet.'),
          backgroundColor: Color(0xFF475569),
        ),
      );
    }
  }

  Future<void> _runManualSync() async {
    if (_isManualSyncing) return;
    setState(() => _isManualSyncing = true);

    final res = await _supabase.syncToCloud();

    if (!mounted) return;
    setState(() => _isManualSyncing = false);

    if (res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Respaldo al día: ${res.productsCount} productos y ${res.salesCount} ventas.'),
          backgroundColor: const Color(0xFF059669),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Aviso: ${res.errorMessage ?? "No se pudo sincronizar"}'),
          backgroundColor: Colors.orange,
        ),
      );
    }
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

      setState(() {
        _user = _authRepo.currentUser;
        _isEditingProfile = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Perfil comercial actualizado con éxito'),
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
                Text('Generando Excel (.xlsx)...', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                SizedBox(height: 6),
                Text('Inventario, Ventas y Clientes', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
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
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red, duration: const Duration(seconds: 4)),
        );
      }
    }
  }

  void _openExcelImport() {
    if (_activeBusiness == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona una empresa primero para importar inventario.'), backgroundColor: Colors.orange),
      );
      return;
    }

    ExcelImportModal.show(
      context,
      businessId: _activeBusiness!.id,
      onImportCompleted: () {
        if (mounted) setState(() {});
      },
    );
  }

  /// Opción A: Confirmación para purgar únicamente los datos en la nube
  Future<void> _showPurgeCloudDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.cloud_off_rounded, color: Colors.orange, size: 24),
            SizedBox(width: 10),
            Text('Purgar datos de la Nube', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          '¿Deseas eliminar únicamente tus copias en la nube?\n\n'
          '• Se borrarán tus registros de Supabase.\n'
          '• Tus datos en este teléfono seguirán 100% INTACTOS.\n'
          '• La app volverá al Modo Local Privado.',
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: Theme.of(ctx).brightness == Brightness.dark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Purgar Nube'),
          ),
        ],
      ),
    );

    if (confirmed == true && _user != null) {
      setState(() => _isLoading = true);
      final ok = await _supabase.purgeCloudDataForUser(_user!.id, _user!.email);
      setState(() {
        _isLoading = false;
        _isCloudSyncEnabled = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(ok
                ? '✅ Datos de la nube purgados. Tu aplicación ahora está 100% en modo local privado.'
                : 'Ocurrió un inconveniente al purgar los datos de la nube.'),
            backgroundColor: ok ? const Color(0xFF059669) : Colors.red,
          ),
        );
      }
    }
  }

  /// Opción B: Confirmación para eliminar la cuenta y todos los datos por completo
  Future<void> _showDeleteAccountDialog() async {
    final confirmController = TextEditingController();
    bool canProceed = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 26),
              SizedBox(width: 10),
              Text('Eliminar Cuenta Definitivamente', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Esta acción es IRREVERSIBLE y permanente.\n\n'
                  'Se borrarán por completo tus empresas, catálogo de productos, registro de ventas, clientes e historial contable tanto de este teléfono móvil como de la nube.\n\n'
                  'Para confirmar, escribe la palabra "ELIMINAR" a continuación:',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: confirmController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    hintText: 'ELIMINAR',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    setDialogState(() {
                      canProceed = val.trim().toUpperCase() == 'ELIMINAR';
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: canProceed ? Colors.red : Colors.grey.shade300,
                foregroundColor: Colors.white,
              ),
              onPressed: canProceed
                  ? () async {
                      Navigator.pop(ctx);
                      if (_user != null) {
                        setState(() => _isLoading = true);
                        await _supabase.deleteAccountCompletely(
                          userId: _user!.id,
                          userEmail: _user!.email,
                        );
                        if (mounted) {
                          widget.onLogout();
                        }
                      }
                    }
                  : null,
              child: const Text('Eliminar Todo'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B);
    final secondaryTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'Ajustes',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // 1. Tarjeta: Perfil Comercial y Cuenta
          _buildCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 34,
                          backgroundColor: const Color(0xFFECFDF5),
                          backgroundImage: _avatarPath != null && File(_avatarPath!).existsSync()
                              ? FileImage(File(_avatarPath!))
                              : null,
                          child: _avatarPath == null
                              ? Text(
                                  (user?.displayName.isNotEmpty == true ? user!.displayName[0] : 'U').toUpperCase(),
                                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: InkWell(
                            onTap: _showAvatarPickerModal,
                            child: const CircleAvatar(
                              radius: 12,
                              backgroundColor: Color(0xFF059669),
                              child: Icon(Icons.camera_alt, color: Colors.white, size: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.displayName ?? 'Comerciante',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: primaryTextColor),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user?.email ?? '',
                            style: TextStyle(fontSize: 12, color: secondaryTextColor),
                          ),
                          if (user?.phone?.isNotEmpty == true) ...[
                            const SizedBox(height: 2),
                            Text(
                              '📞 ${user!.phone}',
                              style: TextStyle(fontSize: 12, color: secondaryTextColor),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(_isEditingProfile ? Icons.close : Icons.edit_outlined, color: const Color(0xFF059669)),
                      onPressed: () => setState(() => _isEditingProfile = !_isEditingProfile),
                      tooltip: 'Editar datos personales',
                    ),
                  ],
                ),
                if (_isEditingProfile) ...[
                  const Divider(height: 24),
                  TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre o Apodo Comercial',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Teléfono / WhatsApp',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
                      child: _isLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Guardar Cambios'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 2. Tarjeta: Tu Negocio y Equipo
          _buildCard(
            title: 'Negocio y Equipo',
            icon: Icons.storefront_outlined,
            child: Column(
              children: [
                if (_activeBusiness != null) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFECFDF5),
                      child: Icon(Icons.store, color: Color(0xFF059669)),
                    ),
                    title: Text(_activeBusiness!.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: Text('Moneda: ${_activeBusiness!.currency} • Comercio Activo', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  ),
                  const Divider(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFEFF6FF),
                      child: Icon(Icons.group_outlined, color: Color(0xFF2563EB)),
                    ),
                    title: const Text('Equipo de Trabajo y Cajeros', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: const Text('Administrar empleados y roles comerciales', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
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
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 3. Tarjeta: Datos, Nube y Movilidad
          _buildCard(
            title: 'Datos, Respaldo y Nube',
            icon: Icons.cloud_sync_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Switch Nube Opcional
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: const Color(0xFF059669),
                  value: _isCloudSyncEnabled,
                  onChanged: _toggleCloudSync,
                  title: const Text(
                    'Sincronización en la Nube y Multidispositivo',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    _isCloudSyncEnabled
                        ? 'Activo: Tus datos se respaldan de forma segura para usar en varios teléfonos o con empleados.'
                        : 'Modo Local Privado: Tus datos residen únicamente en la memoria de este teléfono.',
                    style: TextStyle(fontSize: 12, color: _isCloudSyncEnabled ? const Color(0xFF059669) : const Color(0xFF64748B)),
                  ),
                ),
                if (_isCloudSyncEnabled) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isManualSyncing ? null : _runManualSync,
                      icon: _isManualSyncing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF059669)))
                          : const Icon(Icons.sync, size: 18),
                      label: Text(_isManualSyncing ? 'Sincronizando...' : 'Sincronizar ahora con la Nube'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF059669),
                        side: const BorderSide(color: Color(0xFF059669)),
                      ),
                    ),
                  ),
                ],
                const Divider(height: 20),

                // Botones Excel (Importar y Exportar)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openExcelImport,
                        icon: const Icon(Icons.file_upload_outlined, size: 18),
                        label: const Text('Importar Excel'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primaryTextColor,
                          side: BorderSide(color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _exportToExcel,
                        icon: const Icon(Icons.file_download_outlined, size: 18),
                        label: const Text('Exportar Excel'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 4. Tarjeta: Preferencias de Apariencia (Modo Oscuro)
          _buildCard(
            title: 'Apariencia de la App',
            icon: Icons.palette_outlined,
            child: AnimatedBuilder(
              animation: ThemeController.instance,
              builder: (context, _) {
                final currentMode = ThemeController.instance.themeMode;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Selecciona el tema visual para Stockealo:',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildThemeOption(
                            label: 'Sistema',
                            icon: Icons.brightness_auto,
                            isSelected: currentMode == ThemeMode.system,
                            onTap: () => ThemeController.instance.setThemeMode(ThemeMode.system),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildThemeOption(
                            label: 'Claro',
                            icon: Icons.light_mode_outlined,
                            isSelected: currentMode == ThemeMode.light,
                            onTap: () => ThemeController.instance.setThemeMode(ThemeMode.light),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildThemeOption(
                            label: 'Oscuro',
                            icon: Icons.dark_mode_outlined,
                            isSelected: currentMode == ThemeMode.dark,
                            onTap: () => ThemeController.instance.setThemeMode(ThemeMode.dark),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 14),

          // 5. Tarjeta: Seguridad de la Cuenta
          _buildCard(
            title: 'Seguridad',
            icon: Icons.shield_outlined,
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: isDark ? const Color(0xFF1E3A8A) : const Color(0xFFEFF6FF),
                    child: Icon(
                      Icons.lock_reset,
                      color: isDark ? const Color(0xFF93C5FD) : const Color(0xFF2563EB),
                    ),
                  ),
                  title: const Text('Cambiar Contraseña', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('Actualiza tu clave de acceso seguro', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  trailing: const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
                  onTap: _showChangePasswordDialog,
                ),
                const Divider(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                    child: Icon(
                      Icons.description_outlined,
                      color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                    ),
                  ),
                  title: const Text('Términos y Privacidad', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: const Text('Protección de datos y condiciones del servicio', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  trailing: const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
                  onTap: () => LegalDocumentScreen.show(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 5. Tarjeta: Zona de Privacidad y Borrado de Datos (Bajas)
          _buildCard(
            title: 'Zona de Privacidad y Borrado',
            icon: Icons.delete_forever_outlined,
            titleColor: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
            borderColor: isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA),
            backgroundColor: isDark ? const Color(0xFF450A0A).withOpacity(0.3) : const Color(0xFFFEF2F2),
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: isDark ? const Color(0xFF7C2D12) : const Color(0xFFFFEDD5),
                    child: Icon(Icons.cloud_off_outlined, color: isDark ? const Color(0xFFFDBA74) : Colors.orange),
                  ),
                  title: Text(
                    'Purgar datos de la Nube',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? const Color(0xFFFDBA74) : const Color(0xFF9A3412)),
                  ),
                  subtitle: Text(
                    'Borra registros en Supabase y conserva datos en este celular',
                    style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFFFED7AA) : const Color(0xFF7C2D12)),
                  ),
                  onTap: _showPurgeCloudDialog,
                ),
                Divider(height: 10, color: isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFED7AA)),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: isDark ? const Color(0xFF991B1B) : const Color(0xFFFEE2E2),
                    child: Icon(Icons.delete_forever, color: isDark ? const Color(0xFFFCA5A5) : Colors.red),
                  ),
                  title: Text(
                    'Eliminar cuenta y datos definitivamente',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isDark ? const Color(0xFFF87171) : Colors.red),
                  ),
                  subtitle: Text(
                    'Borra todo de forma permanente (Nube y Teléfono)',
                    style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFFFECACA) : const Color(0xFF991B1B)),
                  ),
                  onTap: _showDeleteAccountDialog,
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 6. Botón Cerrar Sesión
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Cerrar Sesión', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14)),
              onTap: widget.onLogout,
            ),
          ),

          const SizedBox(height: 18),
          const Center(
            child: Text(
              'Stockealo v1.0.0 • Control de Inventario y Stock',
              style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildThemeOption({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unselectedBg = isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
    final unselectedBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final selectedBg = isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5);
    final selectedText = isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? selectedBg : unselectedBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF059669) : unselectedBorder,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? const Color(0xFF059669) : const Color(0xFF64748B),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? selectedText : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    String? title,
    IconData? icon,
    Color? titleColor,
    Color? borderColor,
    Color? backgroundColor,
    required Widget child,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final defaultBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final defaultTitleColor = isDark ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor ?? defaultBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor ?? defaultBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: titleColor ?? const Color(0xFF059669)),
                  const SizedBox(width: 8),
                ],
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: titleColor ?? defaultTitleColor,
                  ),
                ),
              ],
            ),
            Divider(height: 20, color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ],
          child,
        ],
      ),
    );
  }
}
