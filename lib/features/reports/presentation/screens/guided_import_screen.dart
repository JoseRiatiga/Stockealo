import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/design/app_card.dart';
import '../../../../core/design/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../data/guided_import.dart';

/// Inventario › Importar desde Excel (0.12.0): elegir el archivo, confirmar qué
/// es cada columna, ver cómo quedarán los productos y elegir qué hacer con los que
/// ya existen. Antes de importar se guarda una copia para poder deshacer.
class GuidedImportScreen extends StatefulWidget {
  final String businessId;

  const GuidedImportScreen({super.key, required this.businessId});

  /// true si se importó algo
  static Future<bool?> open(BuildContext context, {required String businessId}) =>
      Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => GuidedImportScreen(businessId: businessId)));

  @override
  State<GuidedImportScreen> createState() => _GuidedImportScreenState();
}

class _GuidedImportScreenState extends State<GuidedImportScreen> {
  String? _fileName;
  List<ImportTable> _tables = const [];
  ImportTable? _table;
  int _headerRow = 0;
  Map<int, ImportField> _mapping = const {};
  bool _updateExisting = true;
  StockMode _stockMode = StockMode.replace;
  bool _working = false;

  List<String> get _header => _table == null || _headerRow >= _table!.rows.length ? const [] : _table!.rows[_headerRow];

  List<ImportRow> get _rows =>
      _table == null || !_mapping.containsValue(ImportField.name) ? const [] : GuidedImport.buildRows(_table!, _headerRow, _mapping);

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'csv', 'xls'],
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) return;
    try {
      final tables = GuidedImport.read(file.bytes!, file.name);
      final sheet = GuidedImport.productSheet(tables);
      setState(() {
        _fileName = file.name;
        _tables = tables;
        _selectTable(sheet ?? (tables.isEmpty ? null : tables.first));
      });
      if (sheet == null && mounted) {
        AppToast.showWarning(context, 'No encontramos los títulos de las columnas. Elige la fila y qué es cada columna.');
      }
    } on FormatException catch (e) {
      if (mounted) AppToast.showWarning(context, e.message);
    } catch (e) {
      if (mounted) AppToast.showError(context, 'No se pudo leer el archivo: $e');
    }
  }

  void _selectTable(ImportTable? t) {
    _table = t;
    if (t == null) return;
    final h = GuidedImport.headerRowOf(t);
    _headerRow = h < 0 ? 0 : h;
    _mapping = GuidedImport.guessMapping(_header);
  }

  void _setHeaderRow(int row) => setState(() {
        _headerRow = row;
        _mapping = GuidedImport.guessMapping(_header);
      });

  Future<void> _downloadTemplate() async {
    final bytes = Uint8List.fromList(GuidedImport.template());
    const name = 'Plantilla_productos_Stockealo.xlsx';
    const mime = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    if (kIsWeb) {
      await Share.shareXFiles([XFile.fromData(bytes, name: name, mimeType: mime)]);
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$name';
    await File(path).writeAsBytes(bytes);
    await Share.shareXFiles([XFile(path, mimeType: mime)], subject: 'Plantilla de productos');
  }

  Future<void> _import() async {
    final rows = _rows;
    final valid = rows.where((r) => r.name.isNotEmpty).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Importar $valid productos?'),
        content: Text(
          '${_updateExisting ? 'Los que ya existen se actualizan' : 'Los que ya existen se dejan como están'}'
          '${_stockMode == StockMode.add ? ' y su stock se suma' : ''}.\n\n'
          'Antes de importar guardamos una copia: si algo sale mal, la recuperas en Ajustes › Nube y respaldo › Volver a una copia.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Importar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _working = true);
    try {
      final out = await GuidedImport.apply(
        businessId: widget.businessId,
        rows: rows,
        updateExisting: _updateExisting,
        stockMode: _stockMode,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Importación lista'),
          content: Text([
            '${out.created} productos nuevos',
            '${out.updated} actualizados',
            if (out.skipped > 0) '${out.skipped} omitidos (sin nombre, repetidos o ya existentes)',
            if (out.backedUp) '\nSe guardó una copia antes de importar.',
          ].join('\n')),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Listo'))],
        ),
      );
      if (mounted) Navigator.pop(context, out.created + out.updated > 0);
    } catch (e) {
      if (mounted) AppToast.showError(context, 'No se pudo importar: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final rows = _rows;
    final withIssues = rows.where((r) => r.issues.isNotEmpty).length;
    final noName = rows.where((r) => r.name.isEmpty).length;
    final hasName = _mapping.containsValue(ImportField.name);

    Widget step(String n, String title) => Padding(
          padding: const EdgeInsets.only(top: AppSpace.xl, bottom: AppSpace.sm),
          child: Text('$n. $title', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
        );

    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(title: const Text('Importar desde Excel')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.xxl),
          children: [
            Text('Trae los productos que ya tienes en un Excel. Te mostramos cómo quedarán antes de guardar nada.',
                style: TextStyle(fontSize: 13, color: c.inkMuted)),
            step('1', 'Elige el archivo'),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_fileName ?? 'Archivo .xlsx o .csv', style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
                  const SizedBox(height: AppSpace.sm),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _working ? null : _pick,
                          icon: const Icon(Icons.upload_file_outlined, size: 18),
                          label: Text(_fileName == null ? 'Elegir archivo' : 'Cambiar archivo'),
                        ),
                      ),
                    ],
                  ),
                  TextButton(onPressed: _downloadTemplate, child: const Text('¿No tienes Excel? Descarga la plantilla')),
                ],
              ),
            ),
            if (_table != null) ...[
              step('2', 'Confirma qué es cada columna'),
              if (_tables.length > 1)
                DropdownButtonFormField<ImportTable>(
                  key: ValueKey(_table),
initialValue: _table,
                  decoration: const InputDecoration(labelText: 'Hoja con los productos'),
                  items: [for (final t in _tables) DropdownMenuItem(value: t, child: Text(t.name))],
                  onChanged: (t) => setState(() => _selectTable(t)),
                ),
              const SizedBox(height: AppSpace.sm),
              DropdownButtonFormField<int>(
                key: ValueKey(_headerRow),
initialValue: _headerRow,
                decoration: const InputDecoration(labelText: 'Fila de los títulos'),
                items: [
                  for (var i = 0; i < _table!.rows.length && i < 15; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text('Fila ${i + 1}: ${_table!.rows[i].where((x) => x.isNotEmpty).take(3).join(' · ')}',
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => _setHeaderRow(v ?? 0),
              ),
              const SizedBox(height: AppSpace.md),
              for (var i = 0; i < _header.length; i++)
                if (_header[i].isNotEmpty || (_table!.rows.length > _headerRow + 1 && i < _table!.rows[_headerRow + 1].length))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_header[i].isEmpty ? 'Columna ${i + 1}' : '«${_header[i]}»',
                                  style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
                              if (_table!.rows.length > _headerRow + 1 && i < _table!.rows[_headerRow + 1].length)
                                Text('Ej.: ${_table!.rows[_headerRow + 1][i]}',
                                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.inkMuted)),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpace.sm),
                        DropdownButton<ImportField>(
                          value: _mapping[i] ?? ImportField.ignore,
                          items: [for (final f in ImportField.values) DropdownMenuItem(value: f, child: Text(f.label))],
                          onChanged: (f) => setState(() {
                            final next = {..._mapping};
                            // Cada campo va en una sola columna
                            if (f != null && f != ImportField.ignore) {
                              next.updateAll((k, v) => v == f ? ImportField.ignore : v);
                            }
                            next[i] = f ?? ImportField.ignore;
                            _mapping = next;
                          }),
                        ),
                      ],
                    ),
                  ),
              if (!hasName)
                AppCard(
                  color: c.warningSoft,
                  child: Text('Elige qué columna tiene el nombre del producto: sin eso no se puede importar.',
                      style: TextStyle(color: c.ink)),
                ),
              if (hasName) ...[
                step('3', 'Revisa cómo quedarán'),
                Text(
                  '${rows.length - noName} productos'
                  '${withIssues > 0 ? ' · $withIssues con avisos' : ''}'
                  '${noName > 0 ? ' · $noName sin nombre (no se importan)' : ''}',
                  style: TextStyle(fontWeight: FontWeight.w600, color: c.ink),
                ),
                const SizedBox(height: AppSpace.sm),
                for (final r in rows.take(10)) ...[
                  AppCard(
                    color: r.issues.isEmpty ? null : c.warningSoft,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Fila ${r.line} · ${r.name.isEmpty ? '(sin nombre)' : r.name}',
                            style: TextStyle(fontWeight: FontWeight.w600, color: c.ink)),
                        Text(
                          [
                            if (r.code != null) 'Código ${r.code}',
                            if (r.price != null) 'Precio ${CurrencyFormatter.format(r.price!)}',
                            if (r.cost != null) 'Costo ${CurrencyFormatter.format(r.cost!)}',
                            if (r.stock != null) 'Stock ${r.stock}',
                            if (r.category != null) r.category!,
                          ].join(' · '),
                          style: TextStyle(fontSize: 12, color: c.inkMuted),
                        ),
                        for (final issue in r.issues) Text(issue, style: TextStyle(fontSize: 12, color: c.warning)),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpace.xs),
                ],
                if (rows.length > 10)
                  Text('… y ${rows.length - 10} filas más.', style: TextStyle(fontSize: 12, color: c.inkMuted)),
                step('4', 'Elige qué hacer'),
                Text('Si un producto ya existe (mismo código o nombre)', style: TextStyle(fontSize: 13, color: c.inkMuted)),
                const SizedBox(height: AppSpace.xs),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: Text('Actualizarlo')),
                    ButtonSegment(value: false, label: Text('Dejarlo igual')),
                  ],
                  selected: {_updateExisting},
                  onSelectionChanged: (v) => setState(() => _updateExisting = v.first),
                ),
                if (_updateExisting) ...[
                  const SizedBox(height: AppSpace.md),
                  Text('Su stock', style: TextStyle(fontSize: 13, color: c.inkMuted)),
                  const SizedBox(height: AppSpace.xs),
                  SegmentedButton<StockMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: StockMode.replace, label: Text('Reemplazar')),
                      ButtonSegment(value: StockMode.add, label: Text('Sumar')),
                    ],
                    selected: {_stockMode},
                    onSelectionChanged: (v) => setState(() => _stockMode = v.first),
                  ),
                ],
                const SizedBox(height: AppSpace.xl),
                FilledButton.icon(
                  onPressed: _working || rows.length == noName ? null : _import,
                  icon: const Icon(Icons.download_done_rounded),
                  label: Text(_working ? 'Importando…' : 'Importar ${rows.length - noName} productos'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
