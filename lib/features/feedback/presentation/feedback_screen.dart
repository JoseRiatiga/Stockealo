import 'package:flutter/material.dart';

import '../../../core/design/app_card.dart';
import '../../../core/design/content_width.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_toast.dart';
import '../../business/models/business.dart';
import '../data/feedback_service.dart';

/// Ajustes › Ayuda › Sugerencias y fallos: contarle al equipo de Stockealo algo
/// que no funciona, una idea o una pregunta, y ver la respuesta.
class FeedbackScreen extends StatefulWidget {
  final Business? business;

  const FeedbackScreen({super.key, this.business});

  static Future<void> open(BuildContext context, {Business? business}) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => FeedbackScreen(business: business)));

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _message = TextEditingController();
  final _phone = TextEditingController();
  String _kind = 'FALLO';
  String? _area;
  bool _contact = false;
  bool _sending = false;
  late Future<List<AppFeedback>> _mine = FeedbackService.instance.mine();

  @override
  void dispose() {
    _message.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_message.text.trim().length < 3) {
      AppToast.showWarning(context, 'Cuéntanos qué pasó o qué se te ocurre.');
      return;
    }
    setState(() => _sending = true);
    try {
      await FeedbackService.instance.submit(
        kind: _kind,
        message: _message.text,
        area: _area,
        businessId: widget.business?.id,
        contactPhone: _contact ? _phone.text : null,
      );
      if (!mounted) return;
      _message.clear();
      setState(() {
        _area = null;
        _mine = FeedbackService.instance.mine();
      });
      AppToast.showSuccess(context, '¡Gracias! Lo recibimos y te respondemos aquí mismo.');
    } catch (e) {
      if (mounted) AppToast.showError(context, e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final hint = switch (_kind) {
      'FALLO' => 'Qué estabas haciendo y qué pasó. Ej.: al cobrar en efectivo la app se cerró.',
      'IDEA' => 'Qué te gustaría que hiciera Stockealo.',
      _ => 'Escribe tu pregunta.',
    };
    return Scaffold(
      backgroundColor: c.paper,
      appBar: AppBar(title: const Text('Sugerencias y fallos')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.xxl),
          children: [
            Text('Lo lee el equipo de Stockealo. Así mejoramos la app para tu negocio.',
                style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted)),
            const SizedBox(height: AppSpace.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.sm,
                    children: [
                      for (final e in AppFeedback.kinds.entries)
                        ChoiceChip(label: Text(e.value), selected: _kind == e.key, onSelected: (_) => setState(() => _kind = e.key)),
                    ],
                  ),
                  const SizedBox(height: AppSpace.md),
                  Text('¿En qué parte de la app?', style: TextStyle(fontSize: AppText.sizeSmall, color: c.inkMuted)),
                  const SizedBox(height: AppSpace.xs),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.sm,
                    children: [
                      for (final a in AppFeedback.areas)
                        ChoiceChip(
                          label: Text(a),
                          selected: _area == a,
                          onSelected: (v) => setState(() => _area = v ? a : null),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.md),
                  TextField(
                    controller: _message,
                    minLines: 4,
                    maxLines: 8,
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(labelText: 'Mensaje', hintText: hint, alignLabelWithHint: true),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _contact,
                    onChanged: (v) => setState(() => _contact = v),
                    title: const Text('Pueden escribirme por WhatsApp'),
                  ),
                  if (_contact)
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Tu WhatsApp', hintText: '+57 300 123 4567'),
                    ),
                  const SizedBox(height: AppSpace.sm),
                  Text('Enviamos también la versión de la app, tu equipo y el negocio, para encontrar el problema más rápido.',
                      style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkFaint)),
                  const SizedBox(height: AppSpace.md),
                  FilledButton.icon(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send_outlined, size: 18),
                    label: Text(_sending ? 'Enviando…' : 'Enviar'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            Text('Lo que he enviado', style: TextStyle(fontSize: AppText.sizeBodyLarge, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: AppSpace.sm),
            FutureBuilder<List<AppFeedback>>(
              future: _mine,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(padding: EdgeInsets.all(AppSpace.lg), child: Center(child: CircularProgressIndicator()));
                }
                final list = snap.data ?? const <AppFeedback>[];
                if (list.isEmpty) {
                  return Text('Todavía no has enviado nada.', style: TextStyle(color: c.inkMuted));
                }
                return Column(
                  children: [
                    for (final f in list) ...[
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${f.kindLabel}${f.area == null ? '' : ' · ${f.area}'} · ${f.createdAt.day}/${f.createdAt.month}',
                                    style: TextStyle(fontSize: AppText.sizeCaption, color: c.inkMuted),
                                  ),
                                ),
                                Text(f.statusLabel,
                                    style: TextStyle(
                                      fontSize: AppText.sizeCaption,
                                      fontWeight: FontWeight.w700,
                                      color: f.status == 'RESUELTO' ? c.success : (f.status == 'DESCARTADO' ? c.inkFaint : c.info),
                                    )),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(f.message, style: TextStyle(color: c.ink)),
                            if (f.adminReply != null) ...[
                              const SizedBox(height: AppSpace.sm),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(AppSpace.sm),
                                decoration: BoxDecoration(color: c.successSoft, borderRadius: BorderRadius.circular(AppRadius.control)),
                                child: Text('Stockealo: ${f.adminReply}', style: TextStyle(color: c.ink, fontSize: AppText.sizeSmall)),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpace.sm),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
