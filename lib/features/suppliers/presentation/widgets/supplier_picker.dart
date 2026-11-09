import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../data/supplier_repository.dart';
import '../../models/supplier.dart';
import '../screens/supplier_form_screen.dart';

/// Hoja para elegir un proveedor: buscador, lista y "Nuevo proveedor" con el
/// nombre que se escribió. Devuelve el elegido o null.
class SupplierPicker {
  static Future<Supplier?> pick(BuildContext context, {required String businessId}) async {
    final suppliers = await SupplierRepository.instance.getSuppliers(businessId);
    if (!context.mounted) return null;
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _PickerSheet(suppliers: suppliers),
    );
    if (result is Supplier) return result;
    if (result is _NewSupplier && context.mounted) {
      return SupplierFormScreen.open(context, businessId: businessId, initialName: result.name);
    }
    return null;
  }
}

class _NewSupplier {
  final String name;
  const _NewSupplier(this.name);
}

class _PickerSheet extends StatefulWidget {
  final List<Supplier> suppliers;
  const _PickerSheet({required this.suppliers});

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final q = _query.trim().toLowerCase();
    final list = widget.suppliers.where((s) => q.isEmpty || s.name.toLowerCase().contains(q)).toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.lg,
          AppSpace.lg,
          MediaQuery.of(context).viewInsets.bottom + AppSpace.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Elige el proveedor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: c.ink)),
            const SizedBox(height: AppSpace.md),
            TextField(
              autofocus: widget.suppliers.isNotEmpty,
              textCapitalization: TextCapitalization.words,
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(hintText: 'Buscar o escribir uno nuevo', prefixIcon: Icon(Icons.search)),
            ),
            const SizedBox(height: AppSpace.sm),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: c.successSoft,
                child: Icon(Icons.add_rounded, color: c.success),
              ),
              title: Text(
                q.isEmpty ? 'Nuevo proveedor' : 'Nuevo proveedor "${_query.trim()}"',
                style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
              ),
              onTap: () => Navigator.pop(context, _NewSupplier(_query.trim())),
            ),
            Divider(color: c.line, height: 1),
            Expanded(
              child: list.isEmpty
                  ? Center(
                      child: Text(
                        widget.suppliers.isEmpty ? 'Aún no tienes proveedores.' : 'Ninguno coincide.',
                        style: TextStyle(color: c.inkMuted),
                      ),
                    )
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => Divider(color: c.line, height: 1),
                      itemBuilder: (_, i) {
                        final s = list[i];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: c.surfaceMuted,
                            child: Text(s.name.characters.first.toUpperCase(), style: TextStyle(color: c.ink)),
                          ),
                          title: Text(s.name, style: TextStyle(color: c.ink, fontWeight: FontWeight.w600)),
                          subtitle: Text(s.summary, style: TextStyle(color: c.inkMuted, fontSize: 12)),
                          onTap: () => Navigator.pop(context, s),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "¿Tienes proveedor?": apagado no pide nada; encendido deja elegir o crear uno.
class SupplierToggleField extends StatefulWidget {
  final String businessId;
  final String? supplierId;
  final ValueChanged<String?> onChanged;

  const SupplierToggleField({super.key, required this.businessId, required this.supplierId, required this.onChanged});

  @override
  State<SupplierToggleField> createState() => _SupplierToggleFieldState();
}

class _SupplierToggleFieldState extends State<SupplierToggleField> {
  late bool _on = widget.supplierId != null;
  Supplier? _supplier;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.supplierId;
    if (id == null) return;
    final s = await SupplierRepository.instance.getSupplier(id);
    if (mounted) setState(() => _supplier = s);
  }

  Future<void> _choose() async {
    final s = await SupplierPicker.pick(context, businessId: widget.businessId);
    if (s == null || !mounted) return;
    setState(() => _supplier = s);
    widget.onChanged(s.id);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          SwitchListTile(
            value: _on,
            title: Text('¿Tienes proveedor?', style: TextStyle(color: c.ink, fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: Text(
              _on ? 'Sirve para pedirle y registrar lo que llega' : 'Opcional',
              style: TextStyle(color: c.inkMuted, fontSize: 12),
            ),
            onChanged: (v) {
              setState(() => _on = v);
              if (!v) {
                widget.onChanged(null);
              } else if (_supplier == null) {
                _choose();
              } else {
                widget.onChanged(_supplier!.id);
              }
            },
          ),
          if (_on)
            ListTile(
              leading: Icon(Icons.storefront_outlined, color: c.inkMuted),
              title: Text(
                _supplier?.name ?? 'Elegir proveedor',
                style: TextStyle(color: _supplier == null ? c.accent : c.ink, fontWeight: FontWeight.w600),
              ),
              subtitle: _supplier == null ? null : Text(_supplier!.summary, style: TextStyle(color: c.inkMuted, fontSize: 12)),
              trailing: Text('Cambiar', style: TextStyle(color: c.accent, fontWeight: FontWeight.w600)),
              onTap: _choose,
            ),
        ],
      ),
    );
  }
}
