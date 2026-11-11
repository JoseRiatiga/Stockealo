import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../design/status_pill.dart';
import '../theme/app_tokens.dart';
import 'barcode_check.dart';
import 'photo_barcode.dart';

/// Cómo se leyó el código
enum CodeSource { camera, photo, manual }

/// Producto que ya tiene un código (para avisar antes de repetirlo)
typedef CodeOwnerLookup = Future<String?> Function(String code);

/// EL lector de códigos de Stockealo (diseño aprobado, referencia «Lince»): Cámara ·
/// Foto · A mano, en un solo lugar. Se usa al crear un producto, al vender, en el
/// buscador, en la entrada de mercancía y para unirse a un negocio con su QR.
///
/// - [scan]: leer y seguir (vender, buscar): devuelve el código apenas lo lee.
/// - [pick]: elegir el código de un producto: revisa el último número («Usar 8»)
///   y avisa si otro producto ya lo tiene, antes de aceptarlo.
///
/// El lector USB funciona en el campo: escribe el código y da Enter.
class CodeReader extends StatefulWidget {
  final String title;
  final String? caption;
  final bool review;
  final String? initial;
  final CodeOwnerLookup? ownerOf;
  final String confirmLabel;

  const CodeReader._({
    required this.title,
    this.caption,
    required this.review,
    this.initial,
    this.ownerOf,
    this.confirmLabel = 'Usar este código',
  });

  /// Leer un código (producto o QR) y devolverlo enseguida
  static Future<String?> scan(BuildContext context, {String title = 'Escanear código', String? caption}) =>
      _open(context, CodeReader._(title: title, caption: caption, review: false));

  /// El código de un producto, revisado. [ownerOf] dice qué producto lo tiene ya (o null).
  static Future<String?> pick(
    BuildContext context, {
    String title = 'Código del producto',
    String? caption,
    String? initial,
    CodeOwnerLookup? ownerOf,
    String confirmLabel = 'Usar este código',
  }) =>
      _open(
        context,
        CodeReader._(title: title, caption: caption, review: true, initial: initial, ownerOf: ownerOf, confirmLabel: confirmLabel),
      );

  static Future<String?> _open(BuildContext context, CodeReader reader) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    if (wide) {
      return showDialog<String>(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(AppSpace.xl),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet - 2)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 960, maxHeight: 720), child: reader),
        ),
      );
    }
    return Navigator.of(context).push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => reader));
  }

  /// Hay cámara para leer códigos en este equipo (en Windows no)
  static bool get cameraAvailable =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  State<CodeReader> createState() => _CodeReaderState();
}

class _CodeReaderState extends State<CodeReader> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  late CodeSource _source;
  bool _photoAvailable = false;
  MobileScannerController? _camera;

  /// La línea de ayuda que cambia según el paso
  String _status = '';
  AppTone _statusTone = AppTone.neutral;
  Uint8List? _photo;
  String? _format;
  CodeSource? _readWith;
  String? _owner;
  bool _checkingOwner = false;

  @override
  void initState() {
    super.initState();
    _field.text = widget.initial ?? '';
    _source = CodeReader.cameraAvailable && !widget.review ? CodeSource.camera : CodeSource.manual;
    if (_source == CodeSource.camera) _startCamera();
    _setHelp();
    PhotoBarcode.available.then((v) {
      if (mounted) setState(() => _photoAvailable = v);
    });
    if (_field.text.isNotEmpty) _lookupOwner();
  }

  @override
  void dispose() {
    _camera?.dispose();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startCamera() {
    _camera ??= MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  }

  void _setHelp() {
    _statusTone = AppTone.neutral;
    _status = switch (_source) {
      CodeSource.camera => 'Apunta la cámara al código de barras o al QR.',
      CodeSource.photo => 'Elige una foto donde se vea el código: del producto, una captura o un archivo.',
      CodeSource.manual => 'Escribe el código o pásalo con el lector de código de barras.',
    };
  }

  void _choose(CodeSource s) {
    if (s == _source) return;
    setState(() {
      _source = s;
      if (s == CodeSource.camera) {
        _startCamera();
      } else {
        _camera?.dispose();
        _camera = null;
      }
      if (s == CodeSource.manual) _focus.requestFocus();
      _setHelp();
    });
  }

  /// Llegó un código (cámara, foto o lector): pasa al campo y se revisa
  void _found(String code, {String? format, required CodeSource via}) {
    final clean = code.trim();
    if (clean.isEmpty) return;
    if (!widget.review) {
      Navigator.of(context).pop(clean);
      return;
    }
    setState(() {
      _field.text = clean;
      _format = format;
      _readWith = via;
      _statusTone = AppTone.success;
      _status = via == CodeSource.photo ? 'Código encontrado en la foto. Lo pasamos al campo.' : 'Código leído. Lo pasamos al campo.';
    });
    _lookupOwner();
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _photo = bytes;
      _statusTone = AppTone.neutral;
      _status = 'Buscando un código en la foto…';
    });
    try {
      final found = await PhotoBarcode.read(file);
      if (!mounted) return;
      if (found == null) {
        setState(() {
          _statusTone = AppTone.warning;
          _status = 'No encontramos un código en esa foto. Prueba con otra más cerca, o escríbelo a mano.';
        });
      } else {
        _found(found.code, format: found.format, via: CodeSource.photo);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _statusTone = AppTone.danger;
          _status = 'No se pudo leer la foto. Escribe el código a mano.';
        });
      }
    }
  }

  Future<void> _lookupOwner() async {
    final code = _field.text.trim();
    final lookup = widget.ownerOf;
    if (!widget.review || lookup == null || code.isEmpty) {
      setState(() => _owner = null);
      return;
    }
    setState(() => _checkingOwner = true);
    final owner = await lookup(code);
    if (!mounted || _field.text.trim() != code) return;
    setState(() {
      _owner = owner;
      _checkingOwner = false;
    });
  }

  void _submit() {
    final code = _field.text.trim();
    if (code.isEmpty) return;
    if (!widget.review) {
      Navigator.of(context).pop(code);
      return;
    }
    final check = BarcodeCheck.of(code);
    if (!check.valid || _owner != null || _checkingOwner) return;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final twoColumns = box.maxWidth >= 720;
            final left = _readerSide();
            final right = _codeSide();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(AppSpace.lg + 4, 0, AppSpace.lg + 4, AppSpace.lg + 4),
                    child: twoColumns
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [Expanded(child: left), const SizedBox(width: AppSpace.xl - 2), Expanded(child: right)],
                          )
                        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [left, const SizedBox(height: AppSpace.lg), right]),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _header() {
    final c = context.colors;
    final usb = !CodeReader.cameraAvailable || kIsWeb;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.lg + 4, AppSpace.lg + 2, AppSpace.md, AppSpace.lg),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(AppRadius.control)),
            child: Icon(Icons.qr_code_scanner_outlined, size: 20, color: c.onAccent),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.caption != null) SectionLabel(widget.caption!.toUpperCase(), padding: EdgeInsets.zero),
                Text(widget.title, style: AppText.heading(context)),
              ],
            ),
          ),
          if (usb) ...[
            const StatusPill('Lector USB listo', tone: AppTone.neutral, dot: true),
            const SizedBox(width: AppSpace.sm),
          ],
          IconButton(
            tooltip: 'Cerrar',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.close_outlined, color: c.inkMuted),
          ),
        ],
      ),
    );
  }

  /// Izquierda: las tres formas de leer y el visor
  Widget _readerSide() {
    final c = context.colors;
    final tabs = <(CodeSource, String, IconData)>[
      if (CodeReader.cameraAvailable) (CodeSource.camera, 'Cámara', Icons.photo_camera_outlined),
      if (_photoAvailable) (CodeSource.photo, 'Foto', Icons.image_outlined),
      (CodeSource.manual, 'A mano', Icons.keyboard_outlined),
    ];
    final t = ToneColors.of(context, _statusTone);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(AppRadius.control)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (s, label, icon) in tabs)
                Semantics(
                  button: true,
                  selected: s == _source,
                  child: Material(
                    color: s == _source ? c.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.tile - 1),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.tile - 1),
                      onTap: () => _choose(s),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md + 2, vertical: AppSpace.sm),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(icon, size: 16, color: s == _source ? c.onAccent : c.inkMuted),
                            const SizedBox(width: 6),
                            Text(label,
                                style: AppText.body(context,
                                    weight: s == _source ? FontWeight.w700 : FontWeight.w600, color: s == _source ? c.onAccent : c.ink)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: SizedBox(
            height: 300,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: AppPalette.paperDark),
                if (_source == CodeSource.camera && _camera != null)
                  MobileScanner(
                    controller: _camera!,
                    onDetect: (capture) {
                      final found = capture.barcodes.where((b) => (b.rawValue ?? '').isNotEmpty).firstOrNull;
                      if (found != null) _found(found.rawValue!, via: CodeSource.camera);
                    },
                    errorBuilder: (context, error, _) => _viewerMessage(Icons.no_photography_outlined, 'No se pudo abrir la cámara. Usa Foto o A mano.'),
                  ),
                if (_source == CodeSource.photo)
                  _photo == null
                      ? _viewerMessage(Icons.image_outlined, 'Toca para elegir una foto', onTap: _pickPhoto)
                      : GestureDetector(onTap: _pickPhoto, child: Image.memory(_photo!, fit: BoxFit.contain)),
                if (_source == CodeSource.manual)
                  _viewerMessage(Icons.keyboard_outlined, 'Listo para el lector de código de barras'),
                // Esquinas del visor
                IgnorePointer(child: CustomPaint(painter: _CornersPainter(c.accent))),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md - 2),
        Semantics(
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                switch (_statusTone) {
                  AppTone.success => Icons.check_outlined,
                  AppTone.warning || AppTone.danger => Icons.error_outline,
                  _ => Icons.info_outline,
                },
                size: 16,
                color: _statusTone == AppTone.neutral ? c.inkMuted : t.text,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(_status, style: AppText.small(context, color: _statusTone == AppTone.neutral ? c.inkMuted : t.text)),
              ),
            ],
          ),
        ),
        if (_source == CodeSource.photo && _photo != null) ...[
          const SizedBox(height: AppSpace.sm),
          TextButton.icon(onPressed: _pickPhoto, icon: const Icon(Icons.image_outlined, size: 18), label: const Text('Elegir otra foto')),
        ],
      ],
    );
  }

  Widget _viewerMessage(IconData icon, String text, {VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 36, color: AppPalette.inkMutedDark),
                const SizedBox(height: AppSpace.sm),
                Text(text, textAlign: TextAlign.center, style: AppText.body(context, color: AppPalette.inkDark)),
              ],
            ),
          ),
        ),
      );

  /// Derecha: el campo, la revisión del último número y si ya existe
  Widget _codeSide() {
    final c = context.colors;
    final code = _field.text.trim();
    final check = code.isEmpty ? null : BarcodeCheck.of(code);
    final ok = check != null && check.valid;
    final bad = check != null && !check.valid;
    final canUse = code.isNotEmpty && (!widget.review || (ok && _owner == null && !_checkingOwner));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Código', style: AppText.body(context, weight: FontWeight.w600)),
        const SizedBox(height: AppSpace.sm),
        TextField(
          controller: _field,
          focusNode: _focus,
          autofocus: _source == CodeSource.manual,
          textInputAction: TextInputAction.done,
          style: AppText.mono(context, size: AppText.sizeHeading - 2, weight: FontWeight.w600).copyWith(letterSpacing: 1.4),
          onChanged: (_) {
            setState(() {
              _format = null;
              _readWith = CodeSource.manual;
            });
            _lookupOwner();
          },
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: 'Ej. 7702004003508',
            suffixIcon: check == null || !check.checked
                ? null
                : Padding(
                    padding: const EdgeInsets.only(right: AppSpace.md),
                    child: Center(
                      widthFactor: 1,
                      child: Text(ok ? 'Válido' : 'No cuadra',
                          style: AppText.small(context, weight: FontWeight.w700, color: ok ? c.success : c.danger)),
                    ),
                  ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
              borderSide: BorderSide(color: bad ? c.danger : c.accent, width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
              borderSide: BorderSide(color: bad ? c.danger : c.accent, width: 2),
            ),
          ),
        ),
        if (widget.review && check != null && check.checked) ...[
          const SizedBox(height: AppSpace.md),
          _digits(check),
          const SizedBox(height: AppSpace.sm),
          Text(check.explanation, style: AppText.small(context, color: c.ink)),
        ],
        if (widget.review && check != null) ...[
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(child: _fact('Formato', _format ?? check.format)),
              const SizedBox(width: AppSpace.sm + 2),
              Expanded(
                child: _fact('Leído con', switch (_readWith) {
                  CodeSource.camera => 'Cámara',
                  CodeSource.photo => 'Foto',
                  _ => 'A mano o lector',
                }),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          if (bad)
            _notice(
              AppTone.danger,
              '«$code» no cuadra: el último número debería ser ${check.expected}.',
              action: ('Usar ${check.expected}', () {
                setState(() => _field.text = check.fixed!);
                _lookupOwner();
              }),
            )
          else if (_checkingOwner)
            _notice(AppTone.neutral, 'Revisando si otro producto lo tiene…')
          else if (_owner != null)
            _notice(AppTone.danger, 'Ya lo tiene «$_owner». Dos productos no pueden tener el mismo código.')
          else if (widget.ownerOf != null)
            _notice(AppTone.success, 'Ningún otro producto tiene este código.'),
        ],
        const SizedBox(height: AppSpace.lg),
        SizedBox(
          height: 50,
          child: FilledButton(onPressed: canUse ? _submit : null, child: Text(widget.confirmLabel)),
        ),
      ],
    );
  }

  /// Los números en cajitas, cada uno con su peso; el último es el de control
  Widget _digits(BarcodeCheck check) {
    final c = context.colors;
    final tone = ToneColors.of(context, check.valid ? AppTone.success : AppTone.danger);
    final digits = check.code.split('');
    return ExcludeSemantics(
      child: Row(
        children: [
          for (var i = 0; i < digits.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: i == digits.length - 1 ? tone.soft : c.paper,
                  borderRadius: BorderRadius.circular(AppRadius.small),
                  border: Border.all(color: i == digits.length - 1 ? tone.strong : c.line, width: i == digits.length - 1 ? 2 : 1),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(digits[i],
                        style: AppText.mono(context, size: AppText.sizeTitle, weight: FontWeight.w700, color: i == digits.length - 1 ? tone.text : c.ink)),
                    FittedBox(
                      child: Text(i == digits.length - 1 ? 'control' : '×${check.weights[i]}', style: AppText.caption(context)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fact(String label, String value) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm + 2),
      decoration: BoxDecoration(border: Border.all(color: c.line), borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.caption(context)),
          Text(value, style: AppText.body(context, weight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _notice(AppTone tone, String text, {(String, VoidCallback)? action}) {
    final t = ToneColors.of(context, tone);
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm + 2, AppSpace.sm, AppSpace.sm + 2),
      decoration: BoxDecoration(color: t.soft, borderRadius: BorderRadius.circular(AppRadius.control)),
      child: Row(
        children: [
          Icon(tone == AppTone.success ? Icons.check_outlined : Icons.error_outline, size: 18, color: t.text),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text(text, style: AppText.small(context, weight: FontWeight.w600, color: t.text))),
          if (action != null)
            FilledButton(
              onPressed: action.$2,
              style: FilledButton.styleFrom(backgroundColor: context.colors.danger, minimumSize: const Size(0, 36)),
              child: Text(action.$1),
            ),
        ],
      ),
    );
  }
}

/// Las cuatro esquinas del visor, en el color del negocio
class _CornersPainter extends CustomPainter {
  final Color color;
  const _CornersPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 14.0, len = 26.0;
    final p = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final w = size.width, h = size.height;
    for (final (x, y, dx, dy) in [(inset, inset, 1.0, 1.0), (w - inset, inset, -1.0, 1.0), (inset, h - inset, 1.0, -1.0), (w - inset, h - inset, -1.0, -1.0)]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, y + dy * len)
          ..lineTo(x, y)
          ..lineTo(x + dx * len, y),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CornersPainter old) => old.color != color;
}
