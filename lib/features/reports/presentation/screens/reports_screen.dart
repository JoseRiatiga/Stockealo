import 'package:flutter/material.dart';

import '../../../../core/design/content_width.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../business/models/business.dart';
import '../../../business/presentation/active_business_scope.dart';
import '../../../pro/data/pro_service.dart';
import '../../data/report_export_service.dart';
import 'profit_report_screen.dart';

/// Reportes: el dueño elige qué descargar, de qué periodo y si va todo en un solo
/// Excel (una hoja por parte) o en un archivo por cada parte.
class ReportsScreen extends StatefulWidget {
  final Business business;
  final String userId;
  final String userEmail;

  /// Lo que llega marcado (desde Inventario, solo inventario; desde Ajustes, todo)
  final Set<ReportSection> initial;

  /// Es la pestaña Reportes del menú principal (sin botón de volver)
  final bool embedded;

  const ReportsScreen({
    super.key,
    required this.business,
    required this.userId,
    required this.userEmail,
    this.initial = const {...ReportSection.values},
    this.embedded = false,
  });

  static Future<void> open(
    BuildContext context, {
    required Business business,
    required String userId,
    required String userEmail,
    Set<ReportSection> initial = const {...ReportSection.values},
  }) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ReportsScreen(business: business, userId: userId, userEmail: userEmail, initial: initial),
      ));

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

enum _PeriodChoice { today, week, month, all, custom }

class _ReportsScreenState extends State<ReportsScreen> {
  /// Servicios y Comisiones solo aparecen con Pro Servicios
  List<ReportSection> get _available => ReportSection.available(services: ProService.instance.status.value.services);
  late final Set<ReportSection> _sections = {...widget.initial.where(_available.contains)};
  _PeriodChoice _choice = _PeriodChoice.month;
  DateTimeRange? _custom;
  bool _singleFile = true;
  bool _working = false;

  ReportPeriod get _period => switch (_choice) {
        _PeriodChoice.today => ReportPeriod.today(),
        _PeriodChoice.week => ReportPeriod.thisWeek(),
        _PeriodChoice.month => ReportPeriod.thisMonth(),
        _PeriodChoice.all => ReportPeriod.all,
        _PeriodChoice.custom =>
          _custom == null ? ReportPeriod.thisMonth() : ReportPeriod.range(_custom!.start, _custom!.end),
      };

  bool get _needsPeriod => _sections.any((s) => s.usesPeriod);

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _custom ?? DateTimeRange(start: DateTime(now.year, now.month), end: now),
      helpText: 'Elige el periodo',
      saveText: 'Listo',
    );
    if (range != null) {
      setState(() {
        _custom = range;
        _choice = _PeriodChoice.custom;
      });
    }
  }

  Future<void> _download() async {
    setState(() => _working = true);
    try {
      final files = await ReportExportService.instance.export(
        business: widget.business,
        userId: widget.userId,
        userEmail: widget.userEmail,
        sections: _sections,
        period: _period,
        singleFile: _singleFile,
      );
      if (!mounted) return;
      AppToast.show(
        context,
        message: files.length == 1 ? 'Listo: ${files.first}' : 'Listo: ${files.length} archivos',
        type: ToastType.success,
      );
    } catch (e) {
      if (mounted) AppToast.show(context, message: e.toString().replaceFirst('Exception: ', ''), type: ToastType.error);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget title(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(0, AppSpace.lg, 0, AppSpace.sm),
          child: Text(t, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
        );
    final allChecked = _sections.length == _available.length;

    // En el computador la pestaña ya tiene su título arriba; en el celular, la
    // barra de abajo pasa por encima del final de la lista
    final wide = MediaQuery.of(context).size.width >= 850;
    return Scaffold(
      backgroundColor: c.paper,
      appBar: widget.embedded && wide
          ? null
          : AppBar(
              title: const Text('Reportes'),
              backgroundColor: c.paper,
              automaticallyImplyLeading: !widget.embedded,
            ),
      body: ContentWidth(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpace.lg,
            widget.embedded && wide ? AppSpace.lg : AppSpace.sm,
            AppSpace.lg,
            AppSpace.xxl + (widget.embedded ? MediaQuery.of(context).padding.bottom + 88 : 0),
          ),
          children: [
            Text(
              'Elige qué quieres descargar en Excel. Puedes bajarlo todo junto o cada parte por separado.',
              style: TextStyle(fontSize: 14, height: 1.4, color: c.inkMuted),
            ),
            title('1. ¿Qué incluir?'),
            // Material y no Container: las casillas dibujan su toque sobre él (Flutter 3.47 lo exige)
            Material(
              color: c.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
                side: BorderSide(color: c.line),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  CheckboxListTile(
                    value: allChecked,
                    onChanged: (v) => setState(() {
                      _sections.clear();
                      if (v == true) _sections.addAll(_available);
                    }),
                    title: const Text('Todo', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Divider(height: 1, color: c.line),
                  for (final s in _available)
                    CheckboxListTile(
                      value: _sections.contains(s),
                      onChanged: (v) => setState(() => v == true ? _sections.add(s) : _sections.remove(s)),
                      title: Text(s.label),
                      subtitle: Text(s.description, style: TextStyle(fontSize: 12.5, color: c.inkMuted)),
                    ),
                ],
              ),
            ),
            if (_needsPeriod) ...[
              title('2. Periodo'),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final (choice, label) in const [
                    (_PeriodChoice.today, 'Hoy'),
                    (_PeriodChoice.week, 'Esta semana'),
                    (_PeriodChoice.month, 'Este mes'),
                    (_PeriodChoice.all, 'Todo'),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: _choice == choice,
                      onSelected: (_) => setState(() => _choice = choice),
                    ),
                  ChoiceChip(
                    avatar: const Icon(Icons.date_range_rounded, size: 18),
                    label: Text(_choice == _PeriodChoice.custom ? _period.label : 'Elegir fechas'),
                    selected: _choice == _PeriodChoice.custom,
                    onSelected: (_) => _pickRange(),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: Text(
                  'Aplica a ventas, movimientos y ganancias. El inventario y los clientes salen como están hoy.',
                  style: TextStyle(fontSize: 12.5, color: c.inkMuted),
                ),
              ),
            ],
            title('${_needsPeriod ? 3 : 2}. ¿Cómo lo quieres?'),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, icon: Icon(Icons.description_outlined), label: Text('Un solo Excel')),
                ButtonSegment(value: false, icon: Icon(Icons.copy_all_outlined), label: Text('Un archivo por cada uno')),
              ],
              selected: {_singleFile},
              onSelectionChanged: _sections.length <= 1 ? null : (v) => setState(() => _singleFile = v.first),
            ),
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: Text(
                _sections.length <= 1
                    ? 'Con una sola parte sale un solo archivo.'
                    : _singleFile
                        ? 'Un archivo con ${_sections.length} hojas, una por cada parte.'
                        : '${_sections.length} archivos separados.',
                style: TextStyle(fontSize: 12.5, color: c.inkMuted),
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: _sections.isEmpty || _working ? null : _download,
              icon: _working
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.download_rounded),
              label: Text(_working ? 'Preparando…' : 'Descargar'),
            ),
            if (_sections.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: Text('Marca al menos una parte.', style: TextStyle(fontSize: 12.5, color: c.warning)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pestaña Reportes del menú principal: usa el negocio activo y la cuenta en sesión
/// Pestaña Reportes (0.12.0): reúne Ganancias y Descargar Excel. Es el único
/// lugar de los reportes; Ventas e Inicio ya no tienen accesos propios.
class ReportsTab extends StatefulWidget {
  final String userRole;
  const ReportsTab({super.key, required this.userRole});

  /// Solo el dueño y los administradores ven reportes (tienen costos y ganancias)
  static bool allowed(String role) => role == 'OWNER' || role == 'ADMIN';

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  bool _excel = false;

  String get userRole => widget.userRole;
  static bool allowed(String role) => ReportsTab.allowed(role);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final business = ActiveBusinessScope.of(context);
    final user = AuthRepository.instance.currentUser;
    if (business == null || user == null || !allowed(userRole)) {
      return Scaffold(
        backgroundColor: c.paper,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Text(
              business == null
                  ? 'Elige un negocio para ver sus reportes.'
                  : 'Solo el dueño o un administrador pueden descargar reportes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkMuted),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: c.paper,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.md, AppSpace.lg, 0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, icon: Icon(Icons.insights_rounded), label: Text('Ganancias')),
                    ButtonSegment(value: true, icon: Icon(Icons.table_chart_outlined), label: Text('Descargar Excel')),
                  ],
                  selected: {_excel},
                  onSelectionChanged: (v) => setState(() => _excel = v.first),
                ),
              ),
            ),
          ),
          Expanded(
            child: _excel
                ? ReportsScreen(
                    key: ValueKey('reports-${business.id}'),
                    business: business,
                    userId: user.id,
                    userEmail: user.email,
                    embedded: true,
                  )
                : ProfitReportScreen(key: ValueKey('profit-${business.id}'), business: business, embedded: true),
          ),
        ],
      ),
    );
  }
}
