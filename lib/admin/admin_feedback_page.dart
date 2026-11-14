import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme/app_tokens.dart';
import '../core/widgets/app_toast.dart';
import '../features/feedback/data/feedback_service.dart';
import 'admin_widgets.dart';
import '../core/design/app_dialog.dart';

/// Panel › Sugerencias y fallos: lo que envían los usuarios desde Ajustes › Ayuda.
/// Se cambia el estado y se responde; la respuesta la ve quien escribió.
class AdminFeedbackPage extends StatefulWidget {
  const AdminFeedbackPage({super.key});

  @override
  State<AdminFeedbackPage> createState() => _AdminFeedbackPageState();
}

class _AdminFeedbackPageState extends State<AdminFeedbackPage> {
  final _service = FeedbackService.instance;
  String? _status = 'NUEVO';
  String? _kind;
  List<AppFeedback> _items = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.adminList(status: _status, kind: _kind);
      if (mounted) setState(() => _items = items);
    } catch (e) {
      if (mounted) setState(() => _error = FeedbackService.errorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(AppFeedback f) async {
    var status = f.status == 'NUEVO' ? 'REVISION' : f.status;
    final reply = TextEditingController(text: f.adminReply ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AppDialog(
      title: f.kindLabel,
      content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SelectableText(f.message),
                  const SizedBox(height: AppSpace.md),
                  Text(
                    [
                      f.userEmail,
                      if (f.businessName != null) '${f.businessName}${f.userRole == null ? '' : ' (${f.userRole})'}',
                      if (f.area != null) 'en ${f.area}',
                      if (f.appVersion != null) 'versión ${f.appVersion}',
                      if (f.platform != null) f.platform!,
                      '${f.createdAt.day}/${f.createdAt.month}/${f.createdAt.year}',
                    ].join(' · '),
                    style: const TextStyle(fontSize: AppText.sizeCaption),
                  ),
                  if (f.contactPhone != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          final digits = f.contactPhone!.replaceAll(RegExp(r'[^0-9]'), '');
                          launchUrl(Uri.parse('https://wa.me/$digits'), mode: LaunchMode.externalApplication);
                        },
                        icon: const Icon(Icons.chat_outlined, size: 18),
                        label: Text('WhatsApp ${f.contactPhone}'),
                      ),
                    ),
                  const SizedBox(height: AppSpace.md),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.sm,
                    children: [
                      for (final e in AppFeedback.statuses.entries)
                        ChoiceChip(
                          label: Text(e.key == 'NUEVO' ? 'Nuevo' : e.value),
                          selected: status == e.key,
                          onSelected: (_) => setLocal(() => status = e.key),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.md),
                  TextField(
                    controller: reply,
                    minLines: 3,
                    maxLines: 6,
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Respuesta (la ve el usuario en la app)',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
      actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cerrar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
),
      ),
    );
    final text = reply.text;
    reply.dispose();
    if (saved != true) return;
    try {
      await _service.adminUpdate(f.id, status: status, reply: text);
      if (mounted) AppToast.show(context, message: 'Guardado', type: ToastType.success);
      await _load();
    } catch (e) {
      if (mounted) AppToast.show(context, message: e.toString().replaceFirst('Exception: ', ''), type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = AdminLoadState(
      loading: _loading,
      error: _error,
      empty: _items.isEmpty,
      emptyText: 'No hay mensajes con ese filtro.',
      onRetry: _load,
    );
    return AdminPage(
      title: 'Sugerencias y fallos',
      subtitle: 'Lo que escriben los usuarios desde Ajustes › Ayuda',
      onRefresh: _load,
      children: [
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final (value, label) in const [('NUEVO', 'Nuevos'), ('REVISION', 'En revisión'), ('RESUELTO', 'Resueltos'), ('DESCARTADO', 'Descartados'), (null, 'Todos')])
              ChoiceChip(
                label: Text(label),
                selected: _status == value,
                onSelected: (_) {
                  setState(() => _status = value);
                  _load();
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpace.sm),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final (value, label) in const [(null, 'Todo'), ('FALLO', 'Fallos'), ('IDEA', 'Ideas'), ('PREGUNTA', 'Preguntas')])
              ChoiceChip(
                label: Text(label),
                selected: _kind == value,
                onSelected: (_) {
                  setState(() => _kind = value);
                  _load();
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        if (state.blocking)
          state
        else
          for (final f in _items)
            AdminCard(
              child: InkWell(
                onTap: () => _open(f),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      switch (f.kind) {
                        'FALLO' => Icons.bug_report_outlined,
                        'IDEA' => Icons.lightbulb_outline,
                        _ => Icons.help_outline_outlined,
                      },
                      color: f.kind == 'FALLO' ? c.danger : c.accent,
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.message, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.ink)),
                          const SizedBox(height: 2),
                          Text(
                            [
                              f.userEmail,
                              if (f.businessName != null) f.businessName!,
                              if (f.area != null) f.area!,
                              '${f.createdAt.day}/${f.createdAt.month}',
                            ].join(' · '),
                            style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted),
                          ),
                        ],
                      ),
                    ),
                    Text(f.status == 'NUEVO' ? 'Nuevo' : f.statusLabel,
                        style: TextStyle(fontSize: AppText.sizeCaption, fontWeight: FontWeight.w700, color: f.status == 'NUEVO' ? c.warning : c.inkMuted)),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
