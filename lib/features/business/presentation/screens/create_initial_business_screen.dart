import 'package:flutter/material.dart';

import '../../../../core/design/primary_action_button.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/countries.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/currency_options.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../products/presentation/screens/barcode_scanner_screen.dart';
import '../../../team/data/team_repository.dart';
import '../../data/business_repository.dart';
import '../business_identity.dart';

/// Primera pantalla de una cuenta sin negocios: crear el propio o unirse al
/// equipo de alguien más con su código o QR.
class CreateInitialBusinessScreen extends StatefulWidget {
  final String userId;
  final String? userEmail;
  final String? userName;
  final VoidCallback onBusinessCreated;

  /// Si se pasa, muestra "Cerrar sesión" por si entró con la cuenta equivocada
  final VoidCallback? onLogout;

  const CreateInitialBusinessScreen({
    super.key,
    required this.userId,
    this.userEmail,
    this.userName,
    required this.onBusinessCreated,
    this.onLogout,
  });

  @override
  State<CreateInitialBusinessScreen> createState() => _CreateInitialBusinessScreenState();
}

class _CreateInitialBusinessScreenState extends State<CreateInitialBusinessScreen> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();

  // false = crear mi negocio, true = unirme a un equipo
  bool _isJoiningTeam = false;
  bool _isLoading = false;
  bool _triedSubmit = false;

  Country _country = deviceCountry();
  late String _currency = _country.currency;
  String _icon = kBusinessKinds.first.key;
  String _colorKey = AppPalette.businessColors.keys.first;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String? get _firstName {
    final name = (widget.userName ?? AuthRepository.instance.currentUser?.name)?.trim();
    if (name == null || name.isEmpty) return null;
    return name.split(RegExp(r'\s+')).first;
  }

  Future<void> _submitCreateBusiness() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _triedSubmit = true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await BusinessRepository.instance.createBusiness(
        name: name,
        userId: widget.userId,
        currency: _currency,
        country: _country.code,
        icon: _icon,
        color: AppPalette.toHex(AppPalette.businessColors[_colorKey]!),
      );
      if (mounted) widget.onBusinessCreated();
    } catch (e) {
      if (mounted) AppToast.showError(context, 'No se pudo crear el negocio: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _scanQrCode() async {
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (scanned != null && scanned.trim().isNotEmpty) {
      _joinWithCode(scanned.trim());
    }
  }

  Future<void> _joinWithCode(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty) {
      AppToast.showWarning(context, 'Escribe o escanea el código de invitación.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final email = widget.userEmail ?? AuthRepository.instance.currentUser?.email ?? '';
      final name = widget.userName ?? AuthRepository.instance.currentUser?.name;
      final business = await TeamRepository.instance.joinBusinessByCode(
        codeOrId: code,
        userId: widget.userId,
        userEmail: email,
        userName: name,
      );
      if (mounted) {
        AppToast.showSuccess(context, 'Te uniste a ${business.name}');
        widget.onBusinessCreated();
      }
    } catch (e) {
      if (mounted) AppToast.showError(context, e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final greeting = _firstName == null ? 'Hola' : 'Hola, $_firstName';

    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        // Arriba y no centrado: así el encabezado no salta al cambiar de opción
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.md, AppSpace.xl, AppSpace.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: Image.asset('assets/icon/app_icon.png', width: 30, height: 30),
                      ),
                      const SizedBox(width: AppSpace.sm + 2),
                      Expanded(
                        child: Text('Stockealo', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: c.ink)),
                      ),
                      if (widget.onLogout != null)
                        TextButton(
                          onPressed: _isLoading ? null : widget.onLogout,
                          style: TextButton.styleFrom(foregroundColor: c.inkMuted),
                          child: const Text('Cerrar sesión'),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.xxl),
                  Text(
                    greeting,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.inkMuted),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    _isJoiningTeam ? 'Únete a un equipo' : 'Crea tu negocio',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: c.ink),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    _isJoiningTeam
                        ? 'Pídele al dueño su código de invitación o escanea su QR.'
                        : 'Con esto empiezas a llevar tu inventario y tus ventas. Podrás cambiarlo después.',
                    style: TextStyle(fontSize: 15, height: 1.4, color: c.inkMuted),
                  ),
                  const SizedBox(height: AppSpace.xl),
                  _ModeSwitch(
                    joining: _isJoiningTeam,
                    onChanged: _isLoading ? null : (joining) => setState(() => _isJoiningTeam = joining),
                  ),
                  const SizedBox(height: AppSpace.xl),
                  if (_isJoiningTeam) _joinForm(c) else _createForm(c),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(StockealoColors c, {required Widget child}) => Container(
        padding: const EdgeInsets.all(AppSpace.lg),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: c.line),
        ),
        child: child,
      );

  Widget _createForm(StockealoColors c) {
    final color = AppPalette.businessColors[_colorKey]!;
    final name = _nameController.text.trim();
    final nameMissing = _triedSubmit && name.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Vista previa de cómo se verá el negocio en la app
        _card(
          c,
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(15)),
                child: Icon(businessKindFor(_icon).icon, color: Colors.white, size: 26),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Tu negocio' : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: name.isEmpty ? c.inkFaint : c.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_country.flag}  ${_country.name} · $_currency',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.xl),
        TextField(
          controller: _nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submitCreateBusiness(),
          decoration: InputDecoration(
            labelText: 'Nombre del negocio',
            hintText: 'Miscelánea Central',
            errorText: nameMissing ? 'Escribe el nombre de tu negocio' : null,
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        DropdownButtonFormField<String>(
          value: _country.code,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'País'),
          items: [
            for (final country in kCountries)
              DropdownMenuItem(
                value: country.code,
                child: Text('${country.flag}  ${country.name}', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (code) => setState(() {
            _country = countryByCode(code);
            _currency = _country.currency;
          }),
        ),
        const SizedBox(height: AppSpace.lg),
        Row(
          children: [
            SizedBox(
              width: 130,
              child: DropdownButtonFormField<String>(
                value: _currency,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Moneda'),
                items: [
                  for (final option in kAvailableCurrencies.where((o) => o.code != 'OTRA'))
                    DropdownMenuItem(value: option.code, child: Text(option.code)),
                ],
                onChanged: (code) => setState(() => _currency = code ?? _currency),
              ),
            ),
            const SizedBox(width: AppSpace.lg),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: 'Así se verán tus precios: ',
                  style: TextStyle(color: c.inkMuted, fontSize: 13),
                  children: [
                    TextSpan(
                      text: CurrencyFormatter.formatIn(12500, _currency),
                      style: AppText.amount(context, size: 13),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xl),
        BusinessIconField(
          selected: _icon,
          color: color,
          onSelected: (key) => setState(() => _icon = key),
        ),
        const SizedBox(height: AppSpace.xl),
        Text('Color', style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.md,
          runSpacing: AppSpace.md,
          children: [
            for (final entry in AppPalette.businessColors.entries)
              Semantics(
                button: true,
                selected: _colorKey == entry.key,
                label: 'Color ${entry.key}',
                child: GestureDetector(
                  onTap: () => setState(() => _colorKey = entry.key),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: entry.value,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _colorKey == entry.key ? c.ink : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                    child: _colorKey == entry.key ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.xxl),
        PrimaryActionButton(
          label: _isLoading ? 'Creando…' : 'Crear y empezar',
          icon: Icons.arrow_forward_rounded,
          onPressed: _isLoading ? null : _submitCreateBusiness,
        ),
      ],
    );
  }

  Widget _joinForm(StockealoColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          c,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: c.accent.withOpacity(0.12), borderRadius: BorderRadius.circular(13)),
                    child: Icon(Icons.qr_code_scanner_rounded, color: c.accent),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Escanea su código QR',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
                        const SizedBox(height: 2),
                        Text('Lo encuentra en Ajustes › Tu negocio',
                            style: TextStyle(fontSize: 13, color: c.inkMuted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              FilledButton.icon(
                onPressed: _isLoading ? null : _scanQrCode,
                icon: const Icon(Icons.photo_camera_outlined, size: 20),
                label: const Text('Abrir la cámara'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.xl),
        Row(
          children: [
            Expanded(child: Divider(color: c.line)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: Text('o escribe el código', style: TextStyle(fontSize: 13, color: c.inkMuted)),
            ),
            Expanded(child: Divider(color: c.line)),
          ],
        ),
        const SizedBox(height: AppSpace.xl),
        TextField(
          controller: _codeController,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          textInputAction: TextInputAction.done,
          onSubmitted: _isLoading ? null : _joinWithCode,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 2.5, color: c.ink),
          decoration: const InputDecoration(
            labelText: 'Código de invitación',
            hintText: '6CC1-4831',
          ),
        ),
        const SizedBox(height: AppSpace.xxl),
        PrimaryActionButton(
          label: _isLoading ? 'Verificando…' : 'Unirme al equipo',
          icon: Icons.group_add_rounded,
          onPressed: _isLoading ? null : () => _joinWithCode(_codeController.text),
        ),
      ],
    );
  }
}

/// Selector de dos opciones: crear un negocio propio o unirse a uno existente
class _ModeSwitch extends StatelessWidget {
  final bool joining;
  final ValueChanged<bool>? onChanged;

  const _ModeSwitch({required this.joining, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    Widget option(bool value, IconData icon, String label) {
      final selected = joining == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: selected,
          child: GestureDetector(
            onTap: onChanged == null ? null : () => onChanged!(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(vertical: AppSpace.sm + 2),
              decoration: BoxDecoration(
                color: selected ? c.surface : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.control - 2),
                border: Border.all(color: selected ? c.line : Colors.transparent),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: selected ? c.accent : c.inkMuted),
                  const SizedBox(width: AppSpace.sm),
                  Flexible(
                    child: Text(
                      label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: selected ? c.ink : c.inkMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: BorderRadius.circular(AppRadius.control + 2),
      ),
      child: Row(
        children: [
          option(false, Icons.storefront_rounded, 'Soy el dueño'),
          option(true, Icons.group_add_rounded, 'Me invitaron'),
        ],
      ),
    );
  }
}
