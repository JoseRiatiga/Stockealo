import '../widgets/create_business_sheet.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/countries.dart';
import '../../../profile/presentation/widgets/settings_cards.dart';
import '../business_identity.dart';
import '../active_business_scope.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../team/data/team_repository.dart';
import '../../../team/models/business_member.dart';
import '../../../team/presentation/screens/activity_screen.dart';
import '../../../team/presentation/screens/employees_screen.dart';
import '../../data/business_repository.dart';
import '../../models/business.dart';
import '../widgets/business_selector_modal.dart';

class BusinessInfoScreen extends StatefulWidget {
  final Business business;
  final VoidCallback onLogout;

  const BusinessInfoScreen({
    super.key,
    required this.business,
    required this.onLogout,
  });

  @override
  State<BusinessInfoScreen> createState() => _BusinessInfoScreenState();
}

class _BusinessInfoScreenState extends State<BusinessInfoScreen> {
  late Business _business;
  final _businessRepo = BusinessRepository.instance;
  final _teamRepo = TeamRepository.instance;

  String _userRole = 'OWNER';
  bool _isLoadingMetrics = true;
  int _productsCount = 0;
  int _salesCount = 0;
  double _salesTotalAmount = 0.0;
  int _customersCount = 0;
  List<BusinessMember> _members = [];
  bool _isCloudSync = false;

  @override
  void initState() {
    super.initState();
    _business = widget.business;
    _loadAllInfo();
  }

  Future<void> _loadAllInfo() async {
    setState(() => _isLoadingMetrics = true);
    try {
      final user = AuthRepository.instance.currentUser;
      if (user != null) {
        final role = await _teamRepo.getUserRoleInBusiness(
          businessId: _business.id,
          userId: user.id,
          userEmail: user.email,
        );
        _userRole = role;
      }

      final members = await _teamRepo.getMembers(_business.id);
      var isCloud = await SupabaseService.instance.isCloudSyncEnabled();
      if (members.length > 1 && !isCloud) {
        await SupabaseService.instance.setCloudSyncEnabled(true);
        isCloud = true;
      }

      // Auditoría y métricas desde SQLite local
      final db = await AppDatabase.instance.database;

      final prodRes = await db.rawQuery(
        'SELECT COUNT(*) as count FROM products WHERE business_id = ? AND is_active = 1',
        [_business.id],
      );
      final productsCount = (prodRes.first['count'] as num?)?.toInt() ?? 0;

      final salesRes = await db.rawQuery(
        'SELECT COUNT(*) as count, COALESCE(SUM(total), 0) as total_sum FROM sales WHERE business_id = ?',
        [_business.id],
      );
      final salesCount = (salesRes.first['count'] as num?)?.toInt() ?? 0;
      final salesTotal = (salesRes.first['total_sum'] as num?)?.toDouble() ?? 0.0;

      final custRes = await db.rawQuery(
        'SELECT COUNT(*) as count FROM customers WHERE business_id = ?',
        [_business.id],
      );
      final customersCount = (custRes.first['count'] as num?)?.toInt() ?? 0;

      if (mounted) {
        setState(() {
          _isCloudSync = isCloud || members.length > 1;
          _members = members;
          _productsCount = productsCount;
          _salesCount = salesCount;
          _salesTotalAmount = salesTotal;
          _customersCount = customersCount;
        });
      }
    } catch (e) {
      debugPrint('Error cargando información del negocio: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingMetrics = false;
        });
      }
    }
  }

  bool get _canEdit => _userRole == 'OWNER' || _userRole == 'ADMIN';

  Future<void> _editBusinessDetails() async {
    if (!_canEdit) {
      AppToast.showPermission(
        context,
        'Solo el dueño o administradores pueden editar los datos del negocio.',
      );
      return;
    }

    final saved = await CreateBusinessSheet.edit(context, _business);
    if (saved != null && mounted) setState(() => _business = saved);
  }

  void _copyInviteCode() {
    if (!_canEdit) {
      AppToast.show(
        context,
        message: 'Solo el dueño o administrador pueden ver o compartir el código de invitación.',
        type: ToastType.warning,
      );
      return;
    }
    Clipboard.setData(ClipboardData(text: _business.inviteCode));
    AppToast.show(
      context,
      message: 'Código de invitación ${_business.inviteCode} copiado al portapapeles',
      type: ToastType.info,
    );
  }

  Future<void> _openEmployeesScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeesScreen(business: _business),
      ),
    );
    _loadAllInfo();
  }

  Future<void> _switchBusiness() async {
    final user = AuthRepository.instance.currentUser;
    if (user == null) return;
    final changed = await BusinessSelectorModal.show(
      context,
      userId: user.id,
      onLogout: widget.onLogout,
    );
    if (changed == true && mounted) {
      final active = ActiveBusinessScope.read(context);
      if (active != null) {
        setState(() => _business = active);
        _loadAllInfo();
      }
    }
  }

  Future<void> _handleDeleteBusiness() async {
    if (_userRole != 'OWNER') {
      AppToast.showPermission(
        context,
        'Solo el dueño fundador puede eliminar o enviar a la papelera esta empresa.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Mover a la papelera?'),
        content: Text(
          'El negocio "${_business.name}" se enviará a la papelera durante 7 días. Podrás restaurarlo o se eliminará de forma definitiva al finalizar el plazo.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: ctx.colors.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mover a la papelera'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _businessRepo.softDeleteBusiness(_business.id);
      if (mounted) {
        AppToast.show(
          context,
          message: 'Negocio enviado a la papelera',
          type: ToastType.warning,
        );
        Navigator.pop(context, true);
      }
    }
  }

  String _formatDate(DateTime dt) {
    const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String get _roleLabel => switch (_userRole.toUpperCase()) {
        'OWNER' => 'Dueño',
        'ADMIN' => 'Administrador',
        _ => 'Cajero',
      };

  IconData get _roleIcon => switch (_userRole.toUpperCase()) {
        'OWNER' => Icons.workspace_premium_rounded,
        'ADMIN' => Icons.admin_panel_settings_rounded,
        _ => Icons.point_of_sale_rounded,
      };

  void _copyBusinessId() {
    Clipboard.setData(ClipboardData(text: _business.id));
    AppToast.show(context, message: 'ID copiado', type: ToastType.info);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.md, AppSpace.md),
              child: Row(
                children: [
                  _RoundButton(icon: Icons.chevron_left_rounded, label: 'Atrás', onTap: () => Navigator.pop(context)),
                  Expanded(
                    child: Text(
                      'Tu negocio',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink),
                    ),
                  ),
                  _RoundButton(icon: Icons.swap_horiz_rounded, label: 'Cambiar de negocio', onTap: _switchBusiness),
                ],
              ),
            ),
            Expanded(
              child: _isLoadingMetrics
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final double hPadding = math.max(AppSpace.lg, (constraints.maxWidth - 720) / 2);
                        return RefreshIndicator(
                          onRefresh: _loadAllInfo,
                          child: ListView(
                            padding: EdgeInsets.fromLTRB(hPadding, 0, hPadding, AppSpace.xxl),
                            children: [
                              _identityCard(c),
                              const SizedBox(height: AppSpace.xl),
                              SettingsPanel(label: 'Resumen', child: _metrics(c)),
                              SettingsGroup(label: 'Equipo', children: [
                                SettingsRow(
                                  icon: Icons.qr_code_2_rounded,
                                  title: 'Código de invitación',
                                  subtitle: _canEdit
                                      ? '${_business.inviteCode} · toca para copiarlo'
                                      : 'Solo el dueño o un administrador lo comparte',
                                  onTap: _copyInviteCode,
                                  trailing: _canEdit ? Icon(Icons.copy_rounded, size: 20, color: c.inkFaint) : null,
                                ),
                                SettingsRow(
                                  icon: Icons.groups_rounded,
                                  title: 'Miembros y permisos',
                                  subtitle: _members.length == 1 ? 'Solo tú' : '${_members.length} personas',
                                  onTap: _openEmployeesScreen,
                                ),
                                // Control del dueño: el cajero no ve la actividad del equipo
                                if (_canEdit)
                                  SettingsRow(
                                    icon: Icons.history_rounded,
                                    title: 'Actividad del equipo',
                                    subtitle: 'Quién vendió, cambió precios o ajustó el stock',
                                    onTap: () => ActivityScreen.open(context, _business),
                                  ),
                              ]),
                              SettingsGroup(label: 'Detalles', children: [
                                SettingsRow(
                                  icon: Icons.event_rounded,
                                  title: 'Creado el',
                                  subtitle: _formatDate(_business.createdAt),
                                ),
                                SettingsRow(
                                  icon: Icons.fingerprint_rounded,
                                  title: 'ID del negocio',
                                  subtitle: _business.id,
                                  onTap: _copyBusinessId,
                                  trailing: Icon(Icons.copy_rounded, size: 20, color: c.inkFaint),
                                ),
                              ]),
                              SettingsGroup(children: [
                                SettingsRow(
                                  icon: Icons.delete_outline_rounded,
                                  title: 'Mover a la papelera',
                                  subtitle: _userRole == 'OWNER'
                                      ? 'Se guarda 7 días por si cambias de opinión'
                                      : 'Solo el dueño puede hacerlo',
                                  danger: true,
                                  onTap: _handleDeleteBusiness,
                                ),
                              ]),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _identityCard(StockealoColors c) {
    final country = countryByCode(_business.country);
    final description = _business.description?.trim() ?? '';
    Widget pill(IconData icon, String text) => Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm + 2, vertical: AppSpace.xs),
          decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.pill)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: c.inkMuted),
              const SizedBox(width: AppSpace.xs),
              Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.inkMuted)),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(AppSpace.xl),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          BusinessAvatar(business: _business, size: 72),
          const SizedBox(height: AppSpace.md),
          Text(
            _business.name,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c.ink),
          ),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              pill(_roleIcon, _roleLabel),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm + 2, vertical: AppSpace.xs),
                decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.pill)),
                child: Text(
                  '${country.flag} ${country.name} · ${_business.currency}',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.inkMuted),
                ),
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Text(description, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.inkMuted)),
          ],
          const SizedBox(height: AppSpace.lg),
          SizedBox(
            width: double.infinity,
            child: _canEdit
                // Neutro: no compite con el color del negocio que está justo arriba
                ? OutlinedButton.icon(
                    onPressed: _editBusinessDetails,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      backgroundColor: c.surfaceMuted,
                      foregroundColor: c.ink,
                      side: BorderSide(color: c.line),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.control)),
                      textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                    ),
                    icon: Icon(Icons.edit_outlined, size: 18, color: c.inkMuted),
                    label: const Text('Editar negocio'),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 16, color: c.inkFaint),
                      const SizedBox(width: AppSpace.xs),
                      Flexible(
                        child: Text(
                          'Solo el dueño o un administrador puede editarlo',
                          style: TextStyle(fontSize: 13, color: c.inkMuted),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _metrics(StockealoColors c) {
    Widget tile(IconData icon, String value, String label, {Color? color}) => Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.control)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsIcon(icon, color: color),
              const SizedBox(height: AppSpace.sm),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.amount(context, size: 18, weight: FontWeight.w800, color: c.ink),
              ),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
            ],
          ),
        );

    final tiles = [
      tile(Icons.inventory_2_outlined, '$_productsCount', _productsCount == 1 ? 'Producto activo' : 'Productos activos'),
      tile(Icons.receipt_long_outlined, CurrencyFormatter.format(_salesTotalAmount),
          _salesCount == 1 ? '1 venta' : '$_salesCount ventas'),
      tile(Icons.people_outline_rounded, '$_customersCount', _customersCount == 1 ? 'Cliente' : 'Clientes'),
      tile(
        _isCloudSync ? Icons.cloud_done_outlined : Icons.phone_android_rounded,
        _isCloudSync ? 'En la nube' : 'Local',
        _isCloudSync ? 'Respaldo automático' : 'Solo en este equipo',
        color: _isCloudSync ? c.success : c.inkMuted,
      ),
    ];
    return Column(
      children: [
        Row(children: [Expanded(child: tiles[0]), const SizedBox(width: AppSpace.sm), Expanded(child: tiles[1])]),
        const SizedBox(height: AppSpace.sm),
        Row(children: [Expanded(child: tiles[2]), const SizedBox(width: AppSpace.sm), Expanded(child: tiles[3])]),
      ],
    );
  }
}

/// Botón redondo de la barra superior (atrás, cambiar de negocio)
class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _RoundButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle, border: Border.all(color: c.line)),
            child: Icon(icon, color: c.ink, size: 22),
          ),
        ),
      ),
    );
  }
}
