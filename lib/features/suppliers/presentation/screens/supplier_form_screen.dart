import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design/content_width.dart';
import '../../../../core/design/phone_field.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/countries.dart';
import '../../../business/data/business_repository.dart';
import '../../data/supplier_repository.dart';
import '../../models/supplier.dart';
import '../../../../core/design/app_dialog.dart';

/// Ficha del proveedor. Solo el nombre es obligatorio; lo demás va en "Más datos".
class SupplierFormScreen extends StatefulWidget {
  final String businessId;
  final Supplier? supplier;

  /// Nombre ya escrito (por ejemplo desde el buscador de proveedores)
  final String? initialName;

  const SupplierFormScreen({super.key, required this.businessId, this.supplier, this.initialName});

  /// Devuelve el proveedor guardado, o null si se canceló
  static Future<Supplier?> open(BuildContext context, {required String businessId, Supplier? supplier, String? initialName}) =>
      Navigator.of(context).push<Supplier>(MaterialPageRoute(
        builder: (_) => SupplierFormScreen(businessId: businessId, supplier: supplier, initialName: initialName),
      ));

  @override
  State<SupplierFormScreen> createState() => _SupplierFormScreenState();
}

class _SupplierFormScreenState extends State<SupplierFormScreen> {
  final _repo = SupplierRepository.instance;
  late final Supplier? _s = widget.supplier;

  late final _name = TextEditingController(text: _s?.name ?? widget.initialName ?? '');
  late final _contact = TextEditingController(text: _s?.contactName ?? '');
  late final _email = TextEditingController(text: _s?.email ?? '');
  late final _taxId = TextEditingController(text: _s?.taxId ?? '');
  late final _deliveryDays = TextEditingController(text: _s?.deliveryDays?.toString() ?? '');
  late final _minOrder = TextEditingController(text: _s?.minOrder == null ? '' : _s!.minOrder!.toStringAsFixed(0));
  late final _creditDays = TextEditingController(text: _s?.creditDays?.toString() ?? '');
  late final _notes = TextEditingController(text: _s?.notes ?? '');

  late PhoneValue _phone = PhoneValue(_s?.phone, isValid: true);
  late String? _visitDay = _s?.visitDay;
  late bool _credit = _s?.isCredit ?? false;
  bool _saving = false;

  bool get _hasExtraData =>
      (_s?.taxId ?? '').isNotEmpty ||
      (_s?.email ?? '').isNotEmpty ||
      (_s?.visitDay ?? '').isNotEmpty ||
      _s?.deliveryDays != null ||
      _s?.minOrder != null ||
      (_s?.isCredit ?? false) ||
      (_s?.notes ?? '').isNotEmpty;

  @override
  void dispose() {
    for (final c in [_name, _contact, _email, _taxId, _deliveryDays, _minOrder, _creditDays, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || !_phone.isValid) {
      setState(() {});
      return;
    }
    setState(() => _saving = true);
    final base = _s ?? _repo.newSupplier(widget.businessId, _name.text);
    final supplier = Supplier(
      id: base.id,
      businessId: base.businessId,
      name: _name.text.trim(),
      contactName: _text(_contact),
      phone: _phone.e164,
      email: _text(_email),
      taxId: _text(_taxId),
      visitDay: _visitDay,
      deliveryDays: int.tryParse(_deliveryDays.text.trim()),
      minOrder: double.tryParse(_minOrder.text.trim()),
      paymentTerms: _credit ? 'CREDITO' : 'CONTADO',
      creditDays: _credit ? int.tryParse(_creditDays.text.trim()) : null,
      notes: _text(_notes),
      createdAt: base.createdAt,
      updatedAt: DateTime.now(),
    );
    await _repo.saveSupplier(supplier);
    if (mounted) Navigator.pop(context, supplier);
  }

  Future<void> _delete() async {
    final s = _s;
    if (s == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppDialog(
title: '¿Quitar proveedor?',
content: Text('Se quita "${s.name}". Sus productos quedan sin proveedor y las entradas de mercancía se conservan.'),
actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: ctx.colors.danger),
            child: const Text('Quitar'),
          ),
        ],
),
    );
    if (ok != true) return;
    await _repo.deleteSupplier(s);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final country = countryByCode(BusinessRepository.instance.currentActiveBusiness?.country);
    final nameMissing = _name.text.trim().isEmpty;

    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(
        title: Text(_s == null ? 'Nuevo proveedor' : 'Editar proveedor'),
        actions: [
          if (_s != null)
            IconButton(icon: const Icon(Icons.delete_outline_outlined), tooltip: 'Quitar proveedor', onPressed: _delete),
        ],
      ),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.lg),
          children: [
            TextField(
              controller: _name,
              autofocus: _s == null && (widget.initialName ?? '').isEmpty,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Nombre del proveedor',
                hintText: 'Ej. Distribuidora El Sol',
                prefixIcon: Icon(Icons.storefront_outlined),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            PhoneField(
              initialValue: _s?.phone,
              defaultCountry: country,
              label: 'WhatsApp',
              textInputAction: TextInputAction.next,
              onChanged: (v) => setState(() => _phone = v),
            ),
            const SizedBox(height: AppSpace.lg),
            TextField(
              controller: _contact,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Persona de contacto (opcional)',
                hintText: 'Ej. Carlos, el vendedor',
                prefixIcon: Icon(Icons.person_outline_outlined),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: _hasExtraData,
                tilePadding: EdgeInsets.zero,
                title: Text('Más datos', style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
                subtitle: Text('NIT, día de visita, entrega, forma de pago', style: TextStyle(color: c.inkMuted, fontSize: AppText.sizeCaption)),
                childrenPadding: const EdgeInsets.only(bottom: AppSpace.lg),
                children: [
                  TextField(
                    controller: _taxId,
                    decoration: const InputDecoration(labelText: 'NIT o documento', prefixIcon: Icon(Icons.badge_outlined)),
                  ),
                  const SizedBox(height: AppSpace.md),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Correo', prefixIcon: Icon(Icons.mail_outline_outlined)),
                  ),
                  const SizedBox(height: AppSpace.md),
                  DropdownButtonFormField<String?>(
                    isExpanded: true,
                    key: ValueKey(_visitDay),
initialValue: _visitDay,
                    decoration: const InputDecoration(labelText: 'Día en que pasa', prefixIcon: Icon(Icons.event_outlined)),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('No tiene día fijo')),
                      for (final d in Supplier.weekDays) DropdownMenuItem<String?>(value: d, child: Text(d)),
                    ],
                    onChanged: (v) => setState(() => _visitDay = v),
                  ),
                  const SizedBox(height: AppSpace.md),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _deliveryDays,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(labelText: 'Entrega en', suffixText: 'días'),
                        ),
                      ),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: TextField(
                          controller: _minOrder,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: const InputDecoration(labelText: 'Pedido mínimo', prefixText: '\$ '),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.lg),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Forma de pago', style: TextStyle(color: c.inkMuted, fontSize: AppText.sizeSmall)),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: false, label: Text('Contado')),
                      ButtonSegment(value: true, label: Text('Crédito')),
                    ],
                    selected: {_credit},
                    onSelectionChanged: (v) => setState(() => _credit = v.first),
                  ),
                  if (_credit) ...[
                    const SizedBox(height: AppSpace.md),
                    TextField(
                      controller: _creditDays,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'Plazo para pagar', suffixText: 'días', hintText: '30'),
                    ),
                  ],
                  const SizedBox(height: AppSpace.md),
                  TextField(
                    controller: _notes,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Notas', alignLabelWithHint: true),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            FilledButton(
              onPressed: _saving || nameMissing || !_phone.isValid ? null : _save,
              child: Text(_saving ? 'Guardando...' : 'Guardar proveedor'),
            ),
          ],
        ),
      ),
    );
  }
}
