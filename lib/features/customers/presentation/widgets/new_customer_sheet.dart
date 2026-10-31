import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/design/phone_field.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/countries.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../business/presentation/active_business_scope.dart';
import '../../data/customer_repository.dart';

/// Hoja inferior para registrar un cliente. El teléfono lleva selector de país,
/// con el país del negocio por defecto. Devuelve true si se guardó.
class NewCustomerSheet extends StatefulWidget {
  final String businessId;

  const NewCustomerSheet({super.key, required this.businessId});

  static Future<bool?> show(BuildContext context, {required String businessId}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => NewCustomerSheet(businessId: businessId),
    );
  }

  @override
  State<NewCustomerSheet> createState() => _NewCustomerSheetState();
}

class _NewCustomerSheetState extends State<NewCustomerSheet> {
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _debtController = TextEditingController();
  PhoneValue _phone = const PhoneValue(null, isValid: true);
  bool _triedSubmit = false;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _debtController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || !_phone.isValid) {
      setState(() => _triedSubmit = true);
      return;
    }
    setState(() => _saving = true);
    await CustomerRepository.instance.createCustomer(
      businessId: widget.businessId,
      name: name,
      phone: _phone.e164,
      address: _addressController.text.trim(),
      initialDebt: CurrencyFormatter.parse(_debtController.text),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final country = countryByCode(ActiveBusinessScope.read(context)?.country);
    final nameMissing = _triedSubmit && _nameController.text.trim().isEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpace.xl, 0, AppSpace.xl, AppSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Nuevo cliente', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              Text('Solo el nombre es obligatorio', style: TextStyle(color: c.inkMuted, fontSize: 13)),
              const SizedBox(height: AppSpace.xl),
              TextField(
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Nombre',
                  hintText: 'Ana Gómez',
                  errorText: nameMissing ? 'Escribe el nombre del cliente' : null,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              PhoneField(
                defaultCountry: country,
                label: 'WhatsApp',
                textInputAction: TextInputAction.next,
                onChanged: (value) => setState(() => _phone = value),
              ),
              const SizedBox(height: AppSpace.lg),
              TextField(
                controller: _addressController,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Dirección (opcional)'),
              ),
              const SizedBox(height: AppSpace.lg),
              TextField(
                controller: _debtController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Ya me debe (opcional)',
                  helperText: 'Si ya tiene un fiado pendiente, escribe cuánto',
                  prefixText: '${CurrencyFormatter.currencySymbol} ',
                ),
              ),
              const SizedBox(height: AppSpace.xxl),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: c.onAccent))
                    : const Text('Guardar cliente'),
              ),
              const SizedBox(height: AppSpace.sm),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            ],
          ),
        ),
      ),
    );
  }
}
