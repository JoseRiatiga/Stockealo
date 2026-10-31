import '../../../../core/theme/app_tokens.dart';
import '../../../../core/design/phone_field.dart';
import '../../../../core/utils/countries.dart';
import '../../../business/presentation/business_identity.dart';
import '../widgets/change_password_dialog.dart';
import '../widgets/up_to_date_dialog.dart';
import '../widgets/settings_cards.dart';
import '../../../business/presentation/active_business_scope.dart';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../core/design/app_time_picker.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/image_helper.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../auth/models/app_user.dart';
import '../../../business/data/business_repository.dart';
import '../../../business/models/business.dart';
import '../../../business/presentation/screens/business_info_screen.dart';
import '../../../business/presentation/widgets/business_selector_modal.dart';
import '../../../legal/presentation/screens/legal_document_screen.dart';
import '../../../reports/data/excel_export_service.dart';
import '../../../reports/presentation/widgets/excel_import_modal.dart';
import '../../../team/data/team_repository.dart';
import '../../../../core/theme/theme_controller.dart';
import '../../../../core/services/update_service.dart';
import '../../../../core/widgets/update_dialog.dart';
import '../../../../core/widgets/modern_dialog.dart';
import '../../../../core/widgets/image_source_picker_modal.dart';
import '../../../backup/data/auto_backup_service.dart';
import '../../../pro/data/pro_service.dart';
import '../../../pro/presentation/screens/pro_screen.dart';
import '../../../../core/services/phone_alerts_service.dart';
import '../../../backup/data/backup_service.dart';
import '../../../../core/widgets/app_toast.dart';

class ProfileScreen extends StatefulWidget {
  final VoidCallback onLogout;

  const ProfileScreen({super.key, required this.onLogout});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with ActiveBusinessAware {
  @override
  void onActiveBusinessChanged() => _onBusinessChanged();

  final _authRepo = AuthRepository.instance;
  final _businessRepo = BusinessRepository.instance;
  final _supabase = SupabaseService.instance;

  late TextEditingController _nameController;
  late TextEditingController _phoneController;

  AppUser? _user;
  Business? _activeBusiness;
  String _currentBusinessRole = 'OWNER';
  String? _avatarPath;
  bool _isLoading = false;
  bool _isEditingProfile = false;
  bool _isCloudSyncEnabled = false;
  bool _isManualSyncing = false;
  bool _isCheckingUpdate = false;
  String _currentAppVersion = '1.0.0';

  // Copias automáticas en el celular
  bool _autoBackupEnabled = true;
  bool _isBackingUp = false;
  List<AutoBackup> _autoBackups = const [];

  // Avisos en el celular
  bool _stockAlerts = false;
  bool _summaryAlerts = false;
  int _summaryHour = PhoneAlertsService.defaultSummaryHour;

  @override
  void initState() {
    super.initState();
    _user = _authRepo.currentUser;
    _nameController = TextEditingController(text: _user?.name ?? '');
    _phoneController = TextEditingController(text: _user?.phone ?? '');
    _avatarPath = _user?.avatarPath;
    _loadActiveBusiness();
    _loadCloudSyncStatus();
    _loadAppVersion();
    _loadAutoBackups();
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    final alerts = PhoneAlertsService.instance;
    if (!alerts.isSupported) return;
    try {
      final stock = await alerts.stockAlertsEnabled();
      final summary = await alerts.summaryEnabled();
      final hour = await alerts.summaryHour();
      if (mounted) {
        setState(() {
          _stockAlerts = stock;
          _summaryAlerts = summary;
          _summaryHour = hour;
        });
      }
    } catch (_) {}
  }

  Future<void> _setAlert(bool stock, bool value) async {
    final alerts = PhoneAlertsService.instance;
    final ok = stock ? await alerts.setStockAlerts(value) : await alerts.setSummary(value);
    if (!mounted) return;
    if (!ok) {
      AppToast.showWarning(
        context,
        'Android no dio permiso para mostrar avisos. Puedes activarlo en Ajustes del celular › Apps › Stockealo › Notificaciones.',
      );
      return;
    }
    setState(() => stock ? _stockAlerts = value : _summaryAlerts = value);
  }

  static String _hourLabel(int hour) {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h:00 ${hour < 12 ? 'a. m.' : 'p. m.'}';
  }

  Future<void> _pickSummaryHour() async {
    final picked = await showAppTimePicker(
      context,
      initialTime: TimeOfDay(hour: _summaryHour, minute: 0),
      helpText: 'Hora del resumen',
    );
    if (picked == null || !mounted) return;
    await PhoneAlertsService.instance.setSummaryHour(picked.hour);
    setState(() => _summaryHour = picked.hour);
  }

  void _openAlerts() {
    SettingsSubpage.open(context, title: 'Avisos', refresh: _refresh, children: () {
      final c = context.colors;
      return [
        SettingsGroup(label: 'En la barra del celular', children: [
          SettingsRow.toggle(
            icon: Icons.inventory_2_outlined,
            title: 'Stock bajo',
            subtitle: 'Cuando un producto llega a su mínimo o se agota',
            value: _stockAlerts,
            onChanged: (v) => _setAlert(true, v),
          ),
          SettingsRow.toggle(
            icon: Icons.summarize_outlined,
            title: 'Resumen del día',
            subtitle: 'Ventas, ganancia y lo que falta reponer',
            value: _summaryAlerts,
            onChanged: (v) => _setAlert(false, v),
          ),
          if (_summaryAlerts)
            SettingsRow(
              icon: Icons.schedule_rounded,
              title: 'Hora del resumen',
              subtitle: _hourLabel(_summaryHour),
              onTap: _pickSummaryHour,
            ),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: Text(
            'Se calculan con lo registrado en este celular. Cada persona del equipo elige sus avisos en su propio celular.',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: c.inkMuted),
          ),
        ),
      ];
    });
  }

  Future<void> _loadAutoBackups() async {
    final auto = AutoBackupService.instance;
    if (!auto.isSupported) return;
    try {
      final enabled = await auto.isEnabled();
      final copies = await auto.list();
      if (mounted) {
        setState(() {
          _autoBackupEnabled = enabled;
          _autoBackups = copies;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleAutoBackup(bool value) async {
    await AutoBackupService.instance.setEnabled(value);
    setState(() => _autoBackupEnabled = value);
    if (value) {
      await AutoBackupService.instance.runIfDue();
      await _loadAutoBackups();
    }
  }

  Future<void> _backupNow() async {
    setState(() => _isBackingUp = true);
    try {
      await AutoBackupService.instance.backupNow();
      await _loadAutoBackups();
      if (mounted) AppToast.showSuccess(context, 'Copia guardada en este celular');
    } catch (e) {
      if (mounted) AppToast.showError(context, 'No se pudo hacer la copia: $e');
    } finally {
      if (mounted) setState(() => _isBackingUp = false);
    }
  }

  /// "hoy 8:15 a. m.", "ayer 7:02 p. m." o "28/10 9:30 a. m."
  static String _backupWhen(DateTime date) {
    final now = DateTime.now();
    final day = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final time = '$hour:${date.minute.toString().padLeft(2, '0')} ${date.hour < 12 ? 'a. m.' : 'p. m.'}';
    if (day == today) return 'hoy $time';
    if (day == today.subtract(const Duration(days: 1))) return 'ayer $time';
    return '${date.day}/${date.month} $time';
  }

  String get _autoBackupSummary {
    if (!_autoBackupEnabled) return 'Apagada: no se guardan copias nuevas';
    if (_autoBackups.isEmpty) return 'Una copia al día, sin internet. Guarda la última semana';
    return 'Última copia: ${_backupWhen(_autoBackups.first.date)} · Guarda la última semana';
  }

  Future<void> _pickAutoBackup() async {
    await _loadAutoBackups();
    if (!mounted) return;
    if (_autoBackups.isEmpty) {
      AppToast.showInfo(context, 'Todavía no hay copias. Toca "Hacer una copia ahora".');
      return;
    }
    final chosen = await showModalBottomSheet<AutoBackup>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final c = ctx.colors;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.sm),
                child: Text('Volver a una copia', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.ink)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.md),
                child: Text(
                  'Elige cómo estaban tus datos. Lo que hayas hecho después de esa copia se pierde.',
                  style: TextStyle(fontSize: 13.5, color: c.inkMuted),
                ),
              ),
              for (final copy in _autoBackups)
                ListTile(
                  leading: Icon(Icons.history_rounded, color: c.accent),
                  title: Text(_backupWhen(copy.date), style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
                  subtitle: Text('${(copy.bytes / 1024).ceil()} KB', style: TextStyle(color: c.inkMuted)),
                  trailing: Icon(Icons.chevron_right_rounded, color: c.inkFaint),
                  onTap: () => Navigator.pop(ctx, copy),
                ),
              const SizedBox(height: AppSpace.md),
            ],
          ),
        );
      },
    );
    if (chosen == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = ctx.colors;
        return AlertDialog(
          title: const Text('¿Volver a esta copia?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tus datos en este celular quedarán como estaban ${_backupWhen(chosen.date)}.'),
              if (_isCloudSyncEnabled) ...[
                const SizedBox(height: AppSpace.md),
                Container(
                  padding: const EdgeInsets.all(AppSpace.md),
                  decoration: BoxDecoration(
                    color: c.warning.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Text(
                    'Con la nube activa, lo que ya está en la nube volverá a aparecer al sincronizar.',
                    style: TextStyle(fontSize: 13, height: 1.35, color: c.ink),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Volver a esta copia')),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    try {
      await AutoBackupService.instance.restore(chosen);
      await _loadAutoBackups();
      if (mounted) AppToast.showSuccess(context, 'Listo: tus datos volvieron a esa copia');
    } catch (e) {
      if (mounted) AppToast.showError(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _onBusinessChanged() {
    if (mounted) {
      _loadActiveBusiness();
    }
  }

  Future<void> _loadAppVersion() async {
    final ver = await UpdateService.instance.getCurrentVersion();
    if (mounted) {
      setState(() => _currentAppVersion = ver);
    }
  }

  Future<void> _handleCheckForUpdates() async {
    setState(() => _isCheckingUpdate = true);
    final updateInfo = await UpdateService.instance.checkForUpdate();
    if (!mounted) return;
    setState(() => _isCheckingUpdate = false);

    if (updateInfo.hasUpdate) {
      UpdateDialog.show(context, updateInfo);
    } else if (updateInfo.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(updateInfo.errorMessage!),
          backgroundColor: Colors.orange.shade800,
        ),
      );
    } else {
      UpToDateDialog.show(context, updateInfo.currentVersion);
    }
  }

  Future<void> _loadCloudSyncStatus() async {
    final enabled = await _supabase.isCloudSyncEnabled();
    if (mounted) {
      setState(() => _isCloudSyncEnabled = enabled);
    }
  }

  Future<void> _loadActiveBusiness() async {
    final current = ActiveBusinessScope.read(context);
    Business? biz = current;
    if (biz == null && _user != null) {
      biz = await _businessRepo.getActiveBusiness(_user!.id, _user!.email);
    }
    if (biz != null) ProService.instance.refresh(biz.id);
    String role = 'OWNER';
    if (biz != null && _user != null) {
      role = await TeamRepository.instance.getUserRoleInBusiness(
        businessId: biz.id,
        userId: _user!.id,
        userEmail: _user!.email,
      );
    }
    if (mounted) {
      setState(() {
        _activeBusiness = biz;
        _currentBusinessRole = role;
      });
    }
  }

  Future<void> _openBusinessSelector() async {
    if (_user == null) return;
    final changed = await BusinessSelectorModal.show(
      context,
      userId: _user!.id,
      onLogout: widget.onLogout,
    );
    if (changed == true) {
      _loadActiveBusiness();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _refresh.dispose();
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
          content: Text('Modo Local Privado activo. Tus datos se guardan únicamente en este equipo.'),
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

  ImageProvider? _getAvatarImageProvider(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final cleanPath = path.trim();
    if (cleanPath.startsWith('http://') || cleanPath.startsWith('https://') || cleanPath.startsWith('blob:')) {
      return NetworkImage(cleanPath);
    }
    if (!kIsWeb) {
      try {
        final file = File(cleanPath);
        if (file.existsSync()) {
          return FileImage(file);
        }
      } catch (_) {}
    }
    return null;
  }

  void _showAvatarPickerModal() {
    ImageSourcePickerModal.show(
      context,
      title: 'Foto de Perfil',
      subtitle: 'Elige cómo actualizar tu foto de cuenta',
      hasExistingImage: _avatarPath != null && _avatarPath!.isNotEmpty,
      onSelected: (source) => _pickAvatar(source),
      onRemove: () {
        setState(() => _avatarPath = null);
        _saveProfile();
      },
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

  Future<void> _exportBackup() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await BackupService.instance.exportBackup();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _restoreBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Restaurar un respaldo?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Los datos de esta cuenta en este teléfono se reemplazarán por los del archivo. '
              'Lo que no esté en el respaldo se perderá. Te recomendamos exportar un respaldo antes.',
            ),
            // Con la nube activa, la siguiente sincronización vuelve a traer lo que está allá
            if (_isCloudSyncEnabled) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFD97706).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Tienes la sincronización en la nube activa: lo que ya está en la nube volverá '
                  'a aparecer al sincronizar. El respaldo sirve para recuperar datos perdidos, '
                  'no para borrar los que están en la nube.',
                  style: TextStyle(fontSize: 13, color: Color(0xFFB45309), height: 1.35),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elegir archivo')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final restored = await BackupService.instance.importBackup();
      if (restored) {
        messenger.showSnackBar(const SnackBar(content: Text('Respaldo restaurado.'), backgroundColor: Color(0xFF059669)));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', '')), backgroundColor: Colors.red));
    }
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
    final confirmed = await ModernConfirmDialog.show(
      context: context,
      title: 'Purgar datos de la Nube',
      message: '¿Deseas eliminar únicamente tus copias en la nube?\n\n'
          '• Se borrarán tus registros en la nube.\n'
          '• Tus datos en este dispositivo seguirán 100% INTACTOS.\n'
          '• La app volverá al Modo Local Privado.',
      icon: Icons.cloud_off_rounded,
      iconColor: Colors.orange,
      confirmText: 'Purgar Nube',
      confirmColor: Colors.orange,
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
        builder: (context, setDialogState) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return ModernDialog(
            icon: Icons.warning_amber_rounded,
            iconColor: const Color(0xFFDC2626),
            title: 'Eliminar Cuenta Definitivamente',
            subtitle: 'Esta acción es irreversible y permanente',
            maxWidth: 440,
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Se borrarán por completo tus empresas, catálogo de productos, registro de ventas, clientes e historial contable tanto de este dispositivo como de la nube.\n\n'
                  'Para confirmar, escribe la palabra "ELIMINAR" a continuación:',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
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
            actions: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(
                    color: isDark ? const Color(0xFF26214A) : const Color(0xFFCBD5E1),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onPressed: () => Navigator.pop(ctx),
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
                  backgroundColor: canProceed ? const Color(0xFFDC2626) : Colors.grey.shade400,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: canProceed
                    ? () async {
                        Navigator.pop(ctx);
                        if (_user != null) {
                          final messenger = ScaffoldMessenger.of(this.context);
                          setState(() => _isLoading = true);
                          try {
                            await _supabase.deleteAccountCompletely();
                          } catch (e) {
                            if (mounted) {
                              setState(() => _isLoading = false);
                              messenger.showSnackBar(
                                SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                              );
                            }
                            return;
                          }
                          if (mounted) {
                            widget.onLogout();
                          }
                        }
                      }
                    : null,
                child: const Text('Eliminar Todo', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Avisa a las subpantallas abiertas que el estado cambió (nube, sincronización…)
  final _refresh = ValueNotifier<int>(0);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _refresh.value++;
  }

  String get _roleLabel => switch (_currentBusinessRole.toUpperCase()) {
        'OWNER' => 'Dueño',
        'ADMIN' => 'Admin',
        _ => 'Cajero',
      };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = ThemeController.instance;

    return Scaffold(
      backgroundColor: c.paper,
      body: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final double hPadding = math.max(AppSpace.lg, (constraints.maxWidth - 720) / 2);
              return ListenableBuilder(
                listenable: theme,
                builder: (context, _) => ListView(
                  padding: EdgeInsets.fromLTRB(
                    hPadding,
                    MediaQuery.of(context).padding.top + AppSpace.lg,
                    hPadding,
                    MediaQuery.of(context).padding.bottom + 96,
                  ),
                  children: [
                    // En escritorio el encabezado de la app ya lo muestra
                    if (MediaQuery.sizeOf(context).width < 850)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpace.xs, bottom: AppSpace.xl),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Ajustes', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: c.ink)),
                            Text('Haz que la app sea tuya.', style: TextStyle(fontSize: 15, color: c.inkMuted)),
                          ],
                        ),
                      ),
                    _profileGroup(c),
                    SettingsGroup(children: [
                      SettingsRow.toggle(
                        icon: Theme.of(context).brightness == Brightness.dark
                            ? Icons.dark_mode_outlined
                            : Icons.light_mode_outlined,
                        title: 'Modo oscuro',
                        subtitle: 'Toca para cambiar el ambiente',
                        value: Theme.of(context).brightness == Brightness.dark,
                        onChanged: (v) => theme.setThemeMode(v ? ThemeMode.dark : ThemeMode.light),
                      ),
                    ]),
                    if (_activeBusiness != null)
                      SettingsGroup(children: [
                        ValueListenableBuilder<ProStatus>(
                          valueListenable: ProService.instance.status,
                          builder: (context, pro, _) => SettingsRow(
                            icon: Icons.workspace_premium_outlined,
                            title: pro.active ? 'Stockealo Pro · activo' : 'Stockealo Pro',
                            subtitle: pro.active
                                ? (pro.lifetime ? '${pro.kindLabel} permanente' : '${pro.kindLabel} hasta el ${pro.endsAt!.day}/${pro.endsAt!.month}/${pro.endsAt!.year}')
                                : 'Tienda en línea, cobro de fiados y más',
                            onTap: () => ProScreen.open(context, _activeBusiness!),
                          ),
                        ),
                      ]),
                    SettingsGroup(label: 'Tu negocio', children: [
                      if (_activeBusiness != null)
                        SettingsRow(
                          leading: BusinessAvatar(business: _activeBusiness!, size: 36),
                          title: _activeBusiness!.name,
                          subtitle: '$_roleLabel · Información, equipo y auditoría',
                          onTap: _openBusinessInfo,
                        )
                      else
                        SettingsRow(
                          icon: Icons.storefront_outlined,
                          title: 'Elegir un negocio',
                          subtitle: 'Selecciona o crea uno para empezar',
                          onTap: _openBusinessSelector,
                        ),
                    ]),
                    SettingsGroup(label: 'Personalización', children: [
                      SettingsRow(
                        icon: Icons.palette_outlined,
                        title: 'Apariencia',
                        subtitle: [
                          ThemeController.accentLabel(theme.accentChoice),
                          ThemeController.textScales[theme.textScale]!,
                          if (theme.reduceTransparency) 'Sin transparencias',
                        ].join(' · '),
                        onTap: _openAppearance,
                      ),
                      if (PhoneAlertsService.instance.isSupported)
                        SettingsRow(
                          icon: Icons.notifications_none_rounded,
                          title: 'Avisos',
                          subtitle: [
                            if (_stockAlerts) 'Stock bajo',
                            if (_summaryAlerts) 'Resumen a las ${_hourLabel(_summaryHour)}',
                          ].join(' · ').ifEmpty('Apagados'),
                          onTap: _openAlerts,
                        ),
                    ]),
                    SettingsGroup(label: 'Datos', children: [
                      SettingsRow(
                        icon: _isCloudSyncEnabled ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                        title: 'Nube y respaldo',
                        subtitle: _isCloudSyncEnabled ? 'Respaldo automático en la nube' : 'Solo en este equipo',
                        onTap: _openData,
                      ),
                    ]),
                    SettingsGroup(label: 'Privacidad y seguridad', children: [
                      SettingsRow(
                        icon: Icons.lock_outline_rounded,
                        title: 'Cambiar contraseña',
                        subtitle: 'Tu clave de acceso',
                        onTap: _user == null ? null : () => ChangePasswordDialog.show(context, userId: _user!.id),
                      ),
                      SettingsRow(
                        icon: Icons.shield_outlined,
                        title: 'Términos y privacidad',
                        subtitle: 'Cómo cuidamos tus datos',
                        onTap: () => LegalDocumentScreen.show(context),
                      ),
                      SettingsRow(
                        icon: Icons.delete_outline_rounded,
                        title: 'Borrar datos',
                        subtitle: 'Purgar la nube o eliminar la cuenta',
                        danger: true,
                        onTap: _openDeletion,
                      ),
                    ]),
                    SettingsGroup(label: 'Acerca de', children: [
                      if (!kIsWeb)
                        SettingsRow(
                          icon: Icons.system_update_outlined,
                          title: 'Stockealo $_currentAppVersion',
                          subtitle: 'Buscar actualizaciones',
                          onTap: _isCheckingUpdate ? null : _handleCheckForUpdates,
                          trailing: _isCheckingUpdate
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : null,
                        ),
                      SettingsRow(
                        icon: Icons.logout_rounded,
                        title: 'Cerrar sesión',
                        danger: true,
                        onTap: widget.onLogout,
                      ),
                    ]),
                    Center(
                      child: Text(
                        'Stockealo $_currentAppVersion · Control de inventario',
                        style: TextStyle(fontSize: 12, color: c.inkFaint),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          // Barra de cambios sin guardar, sobre la barra de pestañas
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom,
            child: const PendingChangesBar(useSafeArea: false),
          ),
        ],
      ),
    );
  }

  Widget _profileGroup(StockealoColors c) {
    final user = _user;
    final avatar = _getAvatarImageProvider(_avatarPath);
    final initial = (user?.displayName.isNotEmpty == true ? user!.displayName[0] : 'U').toUpperCase();
    return SettingsGroup(children: [
      Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          children: [
            Row(
              children: [
                Semantics(
                  button: true,
                  label: 'Cambiar foto',
                  child: InkWell(
                    onTap: _showAvatarPickerModal,
                    customBorder: const CircleBorder(),
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: c.successSoft,
                          backgroundImage: avatar,
                          child: avatar == null
                              ? Text(initial,
                                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.accent))
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: CircleAvatar(
                            radius: 10,
                            backgroundColor: c.accent,
                            child: Icon(Icons.camera_alt_rounded, color: c.onAccent, size: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user?.displayName ?? 'Comerciante',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
                      Text(
                        [
                          if (user?.email.isNotEmpty == true) user!.email,
                          if (user?.phone?.isNotEmpty == true) user!.phone!
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: c.inkMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: _isEditingProfile ? 'Cancelar' : 'Editar tus datos',
                  icon: Icon(_isEditingProfile ? Icons.close_rounded : Icons.edit_outlined, color: c.inkMuted),
                  onPressed: () => setState(() => _isEditingProfile = !_isEditingProfile),
                ),
              ],
            ),
            if (_isEditingProfile) ...[
              const SizedBox(height: AppSpace.lg),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Nombre', prefixIcon: Icon(Icons.person_outline)),
              ),
              const SizedBox(height: AppSpace.md),
              PhoneField(
                initialValue: _phoneController.text,
                defaultCountry: deviceCountry(),
                label: 'WhatsApp',
                onChanged: (value) => _phoneController.text = value.e164 ?? '',
              ),
              const SizedBox(height: AppSpace.md),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isLoading ? null : _saveProfile,
                  child: _isLoading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Guardar'),
                ),
              ),
            ],
          ],
        ),
      ),
    ]);
  }

  Future<void> _openBusinessInfo() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BusinessInfoScreen(business: _activeBusiness!, onLogout: widget.onLogout)),
    );
    _loadActiveBusiness();
  }

  void _openAppearance() {
    SettingsSubpage.open(
      context,
      title: 'Apariencia',
      refresh: Listenable.merge([ThemeController.instance, _refresh]),
      children: _appearanceChildren,
    );
  }

  List<Widget> _appearanceChildren() {
    final theme = ThemeController.instance;
    final business = _activeBusiness;
    final choices = <String>[
      'brand',
      if (AppPalette.fromHex(business?.color) != null && AppPalette.fromHex(business?.color) != AppPalette.brand)
        'business',
      for (final color in AppPalette.businessColors.values)
        if (color != AppPalette.brand) AppPalette.toHex(color),
    ];
    return [
      SettingsGroup(children: [
        SettingsRow.toggle(
          icon: Icons.brightness_auto_outlined,
          title: 'Como el teléfono',
          subtitle: 'Claro u oscuro según el ajuste del sistema',
          value: theme.themeMode == ThemeMode.system,
          onChanged: (v) => theme.setThemeMode(v
              ? ThemeMode.system
              : (MediaQuery.platformBrightnessOf(context) == Brightness.dark ? ThemeMode.dark : ThemeMode.light)),
        ),
      ]),
      SettingsPanel(
        label: 'Color del tema',
        value: ThemeController.accentLabel(theme.accentChoice),
        child: Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final choice in choices)
              _AccentDot(
                color: theme.accentFor(choice),
                selected: theme.accentChoice == choice,
                label: ThemeController.accentLabel(choice),
                icon: choice == 'business' ? Icons.storefront_rounded : null,
                onTap: () => theme.setAccentChoice(choice),
              ),
          ],
        ),
      ),
      SettingsPanel(
        label: 'Tamaño de letra',
        value: ThemeController.textScales[theme.textScale],
        child: Row(
          children: [
            for (final entry in ThemeController.textScales.entries) ...[
              if (entry.key != ThemeController.textScales.keys.first) const SizedBox(width: AppSpace.sm),
              Expanded(
                child: _TextSizeOption(
                  scale: entry.key,
                  label: entry.value,
                  selected: theme.textScale == entry.key,
                  onTap: () => theme.setTextScale(entry.key),
                ),
              ),
            ],
          ],
        ),
      ),
      SettingsGroup(label: 'Accesibilidad', children: [
        SettingsRow.toggle(
          icon: Icons.blur_off_rounded,
          title: 'Reducir transparencias',
          subtitle: 'Barras sólidas; útil en celulares lentos',
          value: theme.reduceTransparency,
          onChanged: theme.setReduceTransparency,
        ),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
        child: Text(
          'Los cambios se ven al instante. Guárdalos con "Revisar" o vuelve atrás con "Descartar".',
          style: TextStyle(fontSize: 12.5, color: context.colors.inkMuted),
        ),
      ),
    ];
  }

  void _openData() {
    // La copia del día puede haber terminado después de cargar Ajustes
    _loadAutoBackups();
    SettingsSubpage.open(context, title: 'Nube y respaldo', refresh: _refresh, children: () {
      final c = context.colors;
      return [
        SettingsGroup(children: [
          SettingsRow.toggle(
            icon: Icons.cloud_sync_outlined,
            title: 'Sincronización en la nube',
            subtitle: _isCloudSyncEnabled
                ? 'Respaldo automático y datos compartidos con tu equipo'
                : 'Tus datos se guardan solo en este equipo',
            value: _isCloudSyncEnabled,
            onChanged: _toggleCloudSync,
          ),
          if (_isCloudSyncEnabled)
            SettingsRow(
              icon: Icons.sync_rounded,
              title: _isManualSyncing ? 'Sincronizando…' : 'Sincronizar ahora',
              subtitle: 'Sube y baja los últimos cambios',
              onTap: _isManualSyncing ? null : _runManualSync,
              trailing: _isManualSyncing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
            ),
        ]),
        SettingsGroup(label: 'Excel', children: [
          SettingsRow(
            icon: Icons.file_upload_outlined,
            title: 'Importar inventario',
            subtitle: 'Carga productos desde un archivo de Excel',
            onTap: _openExcelImport,
          ),
          SettingsRow(
            icon: Icons.file_download_outlined,
            title: 'Exportar a Excel',
            subtitle: 'Inventario, ventas y clientes',
            onTap: _exportToExcel,
          ),
        ]),
        if (AutoBackupService.instance.isSupported)
          SettingsGroup(label: 'Copias automáticas', children: [
            SettingsRow.toggle(
              icon: Icons.history_rounded,
              title: 'Copia diaria en este celular',
              subtitle: _autoBackupSummary,
              value: _autoBackupEnabled,
              onChanged: _toggleAutoBackup,
            ),
            SettingsRow(
              icon: Icons.save_outlined,
              title: _isBackingUp ? 'Guardando copia…' : 'Hacer una copia ahora',
              subtitle: 'Guarda tus datos tal como están en este momento',
              onTap: _isBackingUp ? null : _backupNow,
              trailing: _isBackingUp
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
            ),
            SettingsRow(
              icon: Icons.restore_rounded,
              title: 'Volver a una copia',
              subtitle: 'Deshace un error, como borrar productos sin querer',
              onTap: _pickAutoBackup,
            ),
          ]),
        if (BackupService.instance.isSupported)
          SettingsGroup(label: 'Respaldo en archivo', children: [
            SettingsRow(
              icon: Icons.backup_outlined,
              title: 'Exportar respaldo',
              subtitle: 'Guarda una copia completa en un archivo',
              onTap: _exportBackup,
            ),
            SettingsRow(
              icon: Icons.settings_backup_restore_rounded,
              title: 'Restaurar respaldo',
              subtitle: 'Recupera los datos desde un archivo',
              onTap: _restoreBackup,
            ),
          ]),
        if (!_isCloudSyncEnabled)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
            child: Text(
              'Las copias diarias viven en este celular: si lo pierdes, se pierden con él. '
              'Activa la nube o exporta un respaldo en archivo de vez en cuando.',
              style: TextStyle(fontSize: 12.5, color: c.inkMuted),
            ),
          ),
      ];
    });
  }

  void _openDeletion() {
    SettingsSubpage.open(context, title: 'Borrar datos', children: () {
      return [
        SettingsGroup(children: [
          SettingsRow(
            icon: Icons.cloud_off_outlined,
            title: 'Purgar datos de la nube',
            subtitle: 'Borra la copia en la nube y conserva la de este equipo',
            danger: true,
            onTap: _showPurgeCloudDialog,
          ),
          SettingsRow(
            icon: Icons.delete_forever_outlined,
            title: 'Eliminar cuenta y datos',
            subtitle: 'Borra todo para siempre, en la nube y en este equipo',
            danger: true,
            onTap: _showDeleteAccountDialog,
          ),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          child: Text(
            'Antes de borrar te pediremos confirmarlo. Eliminar la cuenta no se puede deshacer.',
            style: TextStyle(fontSize: 12.5, color: context.colors.inkMuted),
          ),
        ),
      ];
    });
  }
}

/// Círculo para elegir el color de la app
class _AccentDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  const _AccentDot({required this.color, required this.selected, required this.label, this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Color $label',
        child: InkResponse(
          onTap: onTap,
          radius: 28,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 48,
            height: 48,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: selected ? color : Colors.transparent, width: 2.5),
            ),
            child: Container(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: selected
                  ? Icon(Icons.check_rounded, color: c.onAccent, size: 20)
                  : (icon != null ? Icon(icon, color: Colors.white, size: 18) : null),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opción "Aa" de tamaño de letra
class _TextSizeOption extends StatelessWidget {
  final double scale;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TextSizeOption({required this.scale, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Letra $label',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? c.accent.withOpacity(0.12) : c.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: selected ? c.accent : Colors.transparent, width: 1.5),
          ),
          // Sin escalar: cada opción muestra su tamaño real, no el elegido
          child: MediaQuery.withNoTextScaling(
            child: Text(
              'Aa',
              style: TextStyle(
                fontSize: 16 * scale,
                fontWeight: FontWeight.w700,
                color: selected ? c.accent : c.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
