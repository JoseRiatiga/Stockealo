import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/design/app_dialog.dart';

/// Nombre de una categoría, para crearla o renombrarla. No deja repetir una que ya
/// existe con otra escritura ("ropa" / "Ropa"): al crear, propone elegir esa.
class CategoryNameDialog extends StatefulWidget {
  final List<String> existing;

  /// Al renombrar: el nombre actual
  final String? initial;

  const CategoryNameDialog({super.key, required this.existing, this.initial});

  /// Devuelve el nombre limpio, o null si se cancela. Al crear, si ya existe una
  /// igual, devuelve el nombre de esa.
  static Future<String?> show(BuildContext context, {required List<String> existing, String? initial}) =>
      showDialog<String>(context: context, builder: (_) => CategoryNameDialog(existing: existing, initial: initial));

  /// "  bebidas   frías " → "Bebidas frías"
  static String clean(String raw) {
    final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
  }

  @override
  State<CategoryNameDialog> createState() => _CategoryNameDialogState();
}

class _CategoryNameDialogState extends State<CategoryNameDialog> {
  late final _name = TextEditingController(text: widget.initial ?? '');

  bool get _renaming => widget.initial != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _clean => CategoryNameDialog.clean(_name.text);

  /// Otra categoría con el mismo nombre (sin contar la que se está renombrando)
  String? get _existingMatch {
    final key = _clean.toLowerCase();
    if (key.isEmpty) return null;
    for (final e in widget.existing) {
      if (e.trim().toLowerCase() == key && e != widget.initial) return e;
    }
    return null;
  }

  bool get _canSave {
    if (_clean.isEmpty) return false;
    if (!_renaming) return true;
    // Renombrar a otra que ya existe uniría categorías sin querer: no se permite
    return _existingMatch == null && _clean != widget.initial;
  }

  void _save() {
    if (!_canSave) return;
    Navigator.pop(context, _renaming ? _clean : (_existingMatch ?? _clean));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final match = _existingMatch;
    String? helper;
    if (match != null) {
      helper = _renaming ? 'Ya tienes una categoría "$match".' : 'Ya tienes "$match": se elegirá esa.';
    }
    return AppDialog(
title: _renaming ? 'Renombrar categoría' : 'Nueva categoría',
content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _renaming
                  ? 'Los productos de "${widget.initial}" pasan con el nombre nuevo.'
                  : 'Agrupa tus productos para encontrarlos rápido y filtrar el inventario.',
              style: TextStyle(fontSize: AppText.sizeSmall, height: 1.4, color: c.inkMuted),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'Nombre',
                hintText: 'Ej. Bebidas, Accesorios, Ferretería',
                helperText: helper,
                helperStyle: TextStyle(color: _renaming ? c.danger : c.inkMuted),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _canSave ? _save : null,
          child: Text(_renaming ? 'Guardar' : (match == null ? 'Crear' : 'Elegir')),
        ),
      ],
);
  }
}
