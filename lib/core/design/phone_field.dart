import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_tokens.dart';
import '../utils/countries.dart';

/// Teléfono escrito en un [PhoneField]
class PhoneValue {
  /// Número completo con prefijo ("+573001234567"); null si está vacío
  final String? e164;

  /// Vacío o con el largo correcto para el país
  final bool isValid;

  const PhoneValue(this.e164, {required this.isValid});
}

/// Campo de teléfono con selector de país: `[🇨🇴 +57 ▾] [300 123 4567]`.
///
/// [initialValue] puede venir con prefijo o ser un número antiguo sin él; en ese
/// caso se toma como de [defaultCountry] (el país del negocio o del teléfono).
class PhoneField extends StatefulWidget {
  final String? initialValue;
  final Country defaultCountry;
  final String label;
  final ValueChanged<PhoneValue> onChanged;
  final TextInputAction? textInputAction;

  const PhoneField({
    super.key,
    this.initialValue,
    required this.defaultCountry,
    this.label = 'Teléfono / WhatsApp',
    required this.onChanged,
    this.textInputAction,
  });

  @override
  State<PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<PhoneField> {
  late Country _country;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final parts = PhoneNumbers.split(widget.initialValue, fallback: widget.defaultCountry);
    _country = parts.country;
    _controller = TextEditingController(text: parts.national);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isEmpty => _controller.text.trim().isEmpty;
  bool get _isValid => _isEmpty || PhoneNumbers.isValidNational(_controller.text, _country);

  void _notify() {
    final digits = _controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    widget.onChanged(PhoneValue(
      digits.isEmpty ? null : '+${_country.dialCode}$digits',
      isValid: _isValid,
    ));
  }

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<Country>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in kCountries)
              ListTile(
                leading: Text(c.flag, style: const TextStyle(fontSize: 22)),
                title: Text(c.name),
                trailing: Text('+${c.dialCode}', style: AppText.amount(ctx, size: 14, weight: FontWeight.w500)),
                selected: c.code == _country.code,
                onTap: () => Navigator.pop(ctx, c),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _country = picked);
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final showError = !_isEmpty && !_isValid;
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.phone,
      textInputAction: widget.textInputAction,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')), LengthLimitingTextInputFormatter(15)],
      onChanged: (_) {
        setState(() {});
        _notify();
      },
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: '${_country.phoneDigits} dígitos',
        errorText: showError ? 'Debe tener ${_country.phoneDigits} dígitos' : null,
        prefixIcon: Semantics(
          button: true,
          label: 'País del teléfono: ${_country.name}',
          child: InkWell(
            onTap: _pickCountry,
            borderRadius: BorderRadius.circular(AppRadius.control),
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpace.md, right: AppSpace.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_country.flag, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text('+${_country.dialCode}', style: AppText.amount(context, size: 15, weight: FontWeight.w500)),
                  Icon(Icons.arrow_drop_down_rounded, color: c.inkMuted),
                  Container(width: 1, height: 22, color: c.line, margin: const EdgeInsets.only(left: 4)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
