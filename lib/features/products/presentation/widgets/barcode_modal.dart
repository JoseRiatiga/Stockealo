import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../models/product.dart';
import '../../../../core/theme/app_tokens.dart';

class BarcodeModal extends StatefulWidget {
  final Product product;

  const BarcodeModal({super.key, required this.product});

  static void show(BuildContext context, Product product) {
    showModalBottomSheet(
      showDragHandle: false,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BarcodeModal(product: product),
    );
  }

  @override
  State<BarcodeModal> createState() => _BarcodeModalState();
}

class _BarcodeModalState extends State<BarcodeModal> {
  bool _showQr = false;

  @override
  Widget build(BuildContext context) {

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: context.colors.lineStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.product.name,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppText.sizeHeading,
              fontWeight: FontWeight.bold,
              color: context.colors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Código: ${widget.product.code}',
            style: TextStyle(
              fontSize: AppText.sizeBody,
              color: context.colors.inkMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 20),

          // Selector de formato: Código de Barras o QR
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment<bool>(
                value: false,
                label: Text('Código de Barras'),
                icon: Icon(Icons.line_weight_outlined),
              ),
              ButtonSegment<bool>(
                value: true,
                label: Text('Código QR'),
                icon: Icon(Icons.qr_code_2_outlined),
              ),
            ],
            selected: {_showQr},
            onSelectionChanged: (Set<bool> newSelection) {
              setState(() {
                _showQr = newSelection.first;
              });
            },
          ),
          const SizedBox(height: 24),

          // Contenedor visual del código (fondo blanco limpio para escaneo con cámara)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: context.colors.line,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _showQr
                ? BarcodeWidget(
                    barcode: Barcode.qrCode(),
                    data: widget.product.code,
                    width: 180,
                    height: 180,
                  )
                : BarcodeWidget(
                    barcode: Barcode.code128(),
                    data: widget.product.code,
                    width: double.infinity,
                    height: 90,
                    drawText: true,
                    style: const TextStyle(
                      fontSize: AppText.sizeBody,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
          ),
          const SizedBox(height: 24),

          // Botón para compartir código
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Share.share(
                  'Producto: ${widget.product.name}\nCódigo: ${widget.product.code}\nPrecio: ${CurrencyFormatter.format(widget.product.salePrice)}',
                );
              },
              icon: const Icon(Icons.share_outlined),
              label: const Text('Compartir Código'),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
