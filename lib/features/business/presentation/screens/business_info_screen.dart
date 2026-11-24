import '../../../../core/design/country_flag.dart';
import '../widgets/create_business_sheet.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/countries.dart';
import '../../../profile/presentation/widgets/settings_cards.dart';
import '../business_identity.dart';
import '../active_business_scope.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../widgets/business_trash.dart';
import 'package:flutter/services.dart';
import '../../../../core/services/supabase_service.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../team/data/team_repository.dart';
import '../../data/business_repository.dart';
import '../../models/business.dart';
import '../widgets/business_selector_modal.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/permissions/permissions.dart';
import '../../models/ticket_info.dart';

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

  bool get _canEdit => Permissions.can(_userRole, Perm.businessInfo);

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

  Future<void> _editTicketInfo() async {
    final info = TicketInfo.of(_business);
    final taxId = TextEditingController(text: info.taxId ?? '');
    final address = TextEditingController(text: info.address ?? '');
    final phone = TextEditingController(text: info.phone ?? '');
    final footer = TextEditingController(text: info.footer ?? '');
    final ok = await AppSheet.show<bool>(
      context: context,
      title: 'Datos del recibo',
      subtitle: 'Salen debajo del nombre del negocio en cada recibo. Todo es opcional.',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(controller: taxId, maxLength: 30, decoration: const InputDecoration(labelText: 'NIT o documento', hintText: 'Ej.: 900.123.456-7')),
          TextField(
            controller: address,
            maxLength: 80,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Dirección', hintText: 'Ej.: Cra. 7 # 12-34, Centro'),
          ),
          TextField(controller: phone, maxLength: 20, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Teléfono')),
          TextField(
            controller: footer,
            maxLength: 80,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Despedida', hintText: 'Ej.: ¡Gracias por preferirnos! Vuelve pronto'),
          ),
          const SizedBox(height: AppSpace.sm),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    final next = TicketInfo(
      taxId: taxId.text.trim().isEmpty ? null : taxId.text.trim(),
      address: address.text.trim().isEmpty ? null : address.text.trim(),
      phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
      footer: footer.text.trim().isEmpty ? null : footer.text.trim(),
    );
    for (final f in [taxId, address, phone, footer]) {
      f.dispose();
    }
    if (ok != true || !mounted) return;
    final saved = await BusinessRepository.instance.updateBusiness(id: _business.id, ticketInfo: next.encode() ?? '');
    if (!mounted) return;
    if (saved != null) setState(() => _business = saved);
    AppToast.showSuccess(context, 'Datos del recibo guardados.');
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
        'Solo el dueño fundador puede eliminar o enviar a la papelera este negocio.',
      );
      return;
    }

    final confirmed = await BusinessTrash.confirmMove(context, _business);

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

  String get _roleLabel => Permissions.labelOf(_userRole);

  IconData get _roleIcon => switch (_userRole.toUpperCase()) {
        'OWNER' => Icons.workspace_premium_outlined,
        'ADMIN' => Icons.admin_panel_settings_outlined,
        _ => Icons.point_of_sale_outlined,
      };

  void _copyBusinessId() {
    Clipboard.setData(ClipboardData(text: _business.id));
    AppToast.show(context, message: 'ID copiado', type: ToastType.info);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // El mismo encabezado que el resto de la app (0.16.7, hallazgo 56)
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(
        title: const Text('Tu negocio'),
        actions: [
          IconButton(tooltip: 'Cambiar de negocio', onPressed: _switchBusiness, icon: const Icon(Icons.swap_horiz_outlined)),
          const SizedBox(width: AppSpace.sm),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
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
                              // Datos del tiquete (0.15.0): NIT, dirección, teléfono y despedida
                              SettingsGroup(label: 'Recibo', children: [
                                SettingsRow(
                                  icon: Icons.receipt_long_outlined,
                                  title: 'Datos del recibo',
                                  subtitle: () {
                                    final info = TicketInfo.of(_business);
                                    if (info.isEmpty) return 'NIT, dirección, teléfono y tu despedida';
                                    return [...info.headerLines, if (info.footer != null) '«${info.footer}»'].join(' · ');
                                  }(),
                                  onTap: _canEdit ? _editTicketInfo : null,
                                ),
                              ]),
                              SettingsGroup(label: 'Detalles', children: [
                                SettingsRow(
                                  icon: Icons.event_outlined,
                                  title: 'Creado el',
                                  subtitle: _formatDate(_business.createdAt),
                                ),
                                SettingsRow(
                                  icon: Icons.fingerprint_outlined,
                                  title: 'ID del negocio',
                                  subtitle: _business.id,
                                  onTap: _copyBusinessId,
                                  trailing: Icon(Icons.copy_outlined, size: 20, color: c.inkFaint),
                                ),
                              ]),
                              SettingsGroup(children: [
                                SettingsRow(
                                  icon: Icons.delete_outline_outlined,
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
              Text(text, style: TextStyle(fontSize: AppText.sizeSmall, fontWeight: FontWeight.w600, color: c.inkMuted)),
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
            style: TextStyle(fontSize: AppText.sizeHeading, fontWeight: FontWeight.w800, color: c.ink),
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
                child: CountryLabel(
                  country: country,
                  text: '${country.name} · ${_business.currency}',
                  style: TextStyle(fontSize: AppText.sizeSmall, fontWeight: FontWeight.w600, color: c.inkMuted),
                ),
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Text(description, textAlign: TextAlign.center, style: TextStyle(fontSize: AppText.sizeBody, color: c.inkMuted)),
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
                      textStyle: const TextStyle(fontSize: AppText.sizeBodyLarge, fontWeight: FontWeight.w600),
                    ),
                    icon: Icon(Icons.edit_outlined, size: 18, color: c.inkMuted),
                    label: const Text('Editar negocio'),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock_outline, size: 16, color: c.inkFaint),
                      const SizedBox(width: AppSpace.xs),
                      Flexible(
                        child: Text(
                          'Solo el dueño o un administrador puede editarlo',
                          style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

