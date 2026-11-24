import 'package:flutter/material.dart';

import '../../../../core/design/app_dialog.dart';
import '../../../../core/design/phone_field.dart';
import '../../../../core/design/status_pill.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/countries.dart';

/// Lo que se escribe al abrir o editar una sede
typedef BranchFormData = ({String name, String address, String phone});

/// Abrir o editar una sede (0.18.1, boceto aprobado el 24 nov): una línea que explica
/// qué es una sede, campos con ícono, teléfono con país, «Abrir sede» solo con nombre
/// y aviso si ya hay una sede con ese nombre.
class BranchFormDialog extends StatefulWidget {
  final String title;
  final String actionLabel;

  /// Nombres de las otras sedes (y de la Principal), para no repetir
  final List<String> taken;
  final String? name;
  final String? address;
  final String? phone;
  final String? country;

  /// Solo el nombre (renombrar la Principal)
  final bool onlyName;

  /// «Usarás 1 de 3 cupos de sede», debajo de los campos; null para no mostrarlo
  final String? slotsNote;

  const BranchFormDialog({
    super.key,
    required this.title,
    required this.actionLabel,
    required this.taken,
    this.name,
    this.address,
    this.phone,
    this.country,
    this.onlyName = false,
    this.slotsNote,
  });

  static Future<BranchFormData?> show(
    BuildContext context, {
    required String title,
    required String actionLabel,
    required List<String> taken,
    String? name,
    String? address,
    String? phone,
    String? country,
    bool onlyName = false,
    String? slotsNote,
  }) =>
      showDialog<BranchFormData>(
        context: context,
        builder: (_) => BranchFormDialog(
          title: title,
          actionLabel: actionLabel,
          taken: taken,
          name: name,
          address: address,
          phone: phone,
          country: country,
          onlyName: onlyName,
          slotsNote: slotsNote,
        ),
      );

  /// "  norte   centro " → "norte centro", para comparar sin mayúsculas ni espacios de más
  static String normalize(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  @override
  State<BranchFormDialog> createState() => _BranchFormDialogState();
}

class _BranchFormDialogState extends State<BranchFormDialog> {
  late final _name = TextEditingController(text: widget.name ?? '');
  late final _address = TextEditingController(text: widget.address ?? '');
  late PhoneValue _phone = PhoneValue((widget.phone ?? '').trim().isEmpty ? null : widget.phone, isValid: true);

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  String get _clean => _name.text.trim().replaceAll(RegExp(r'\s+'), ' ');

  bool get _repeated {
    final k = BranchFormDialog.normalize(_clean);
    return k.isNotEmpty && widget.taken.any((t) => BranchFormDialog.normalize(t) == k);
  }

  bool get _canSave => _clean.isNotEmpty && !_repeated && _phone.isValid;

  void _save() {
    if (!_canSave) return;
    Navigator.pop<BranchFormData>(context, (name: _clean, address: _address.text.trim(), phone: _phone.e164 ?? ''));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppDialog(
      icon: Icons.place_outlined,
      tone: AppTone.success,
      title: widget.title,
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.onlyName
                  ? 'Así se llama el local donde empezó tu negocio.'
                  : 'Otro local de tu negocio. Tiene su propio stock, sus ventas y su caja; el catálogo y los clientes son los mismos.',
              style: TextStyle(fontSize: AppText.sizeSmall, height: 1.4, color: c.inkMuted),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: widget.onlyName ? TextInputAction.done : TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Nombre',
                hintText: 'Norte, Centro, Plaza…',
                prefixIcon: const Icon(Icons.storefront_outlined),
                helperText: _repeated ? null : 'Así aparece en el menú y en el recibo',
                errorText: _repeated ? 'Ya tienes una sede «$_clean»' : null,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: widget.onlyName ? (_) => _save() : null,
            ),
            if (!widget.onlyName) ...[
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _address,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Dirección (opcional)', prefixIcon: Icon(Icons.map_outlined)),
              ),
              const SizedBox(height: AppSpace.md),
              PhoneField(
                initialValue: widget.phone,
                defaultCountry: countryByCode(widget.country),
                label: 'Teléfono (opcional)',
                textInputAction: TextInputAction.done,
                onChanged: (v) => setState(() => _phone = v),
              ),
            ],
            if (widget.slotsNote != null) ...[
              const SizedBox(height: AppSpace.md),
              Text(widget.slotsNote!, style: AppText.caption(context)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _canSave ? _save : null, child: Text(widget.actionLabel)),
      ],
    );
  }
}
