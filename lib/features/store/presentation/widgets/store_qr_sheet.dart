import 'dart:typed_data';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../../../../core/design/app_dialog.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/share_images.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../business/models/business.dart';
import '../../../products/models/product.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../data/online_store_service.dart';
import '../../../reports/data/pdf_type.dart';

/// QR de la tienda para el mostrador (0.16.0, fase 3): imagen para compartir o cartel
/// en PDF para imprimir
class StoreQrSheet {
  static Future<void> show(BuildContext context, {required Business business, required OnlineStoreConfig store}) {
    final key = GlobalKey();
    return AppSheet.show<void>(
      context: context,
      title: 'QR de tu tienda',
      subtitle: 'Pégalo en el mostrador o compártelo. Al escanearlo abre tu tienda.',
      builder: (ctx) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: RepaintBoundary(
              key: key,
              child: StoreQrCard(businessName: business.name, url: store.url),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          FilledButton.icon(
            icon: const Icon(Icons.share_outlined),
            label: const Text('Compartir imagen'),
            onPressed: () async {
              try {
                await shareImages([key], baseName: 'QR_${business.name}', text: 'Pide aquí: ${store.url}');
              } catch (e) {
                if (ctx.mounted) AppToast.showError(ctx, '$e');
              }
            },
          ),
          const SizedBox(height: AppSpace.sm),
          OutlinedButton.icon(
            icon: const Icon(Icons.print_outlined),
            label: const Text('Cartel para imprimir (PDF)'),
            onPressed: () async {
              try {
                final bytes = await posterPdf(businessName: business.name, url: store.url);
                await Share.shareXFiles(
                  [XFile.fromData(bytes, mimeType: 'application/pdf', name: 'Cartel_QR_${business.name.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_')}.pdf')],
                );
              } catch (e) {
                if (ctx.mounted) AppToast.showError(ctx, '$e');
              }
            },
          ),
        ],
      ),
    );
  }

  /// Cartel de media carta: «Escanea y pide aquí», el QR grande y la dirección
  static Future<Uint8List> posterPdf({required String businessName, required String url}) async {
    final doc = pw.Document(title: 'QR · $businessName');
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(36),
        build: (_) => pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          children: [
            pw.Text(businessName, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: PdfPt.title, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            pw.Text('Escanea y pide aquí', style: const pw.TextStyle(fontSize: PdfPt.subtitle)),
            pw.SizedBox(height: 18),
            pw.BarcodeWidget(barcode: pw.Barcode.qrCode(), data: url, width: 230, height: 230),
            pw.SizedBox(height: 16),
            pw.Text(url.replaceFirst('https://', ''), style: const pw.TextStyle(fontSize: PdfPt.body)),
            pw.SizedBox(height: 4),
            pw.Text('Pedidos por WhatsApp · Hecho con Stockealo', style: const pw.TextStyle(fontSize: PdfPt.caption, color: PdfColors.grey600)),
          ],
        ),
      ),
    );
    return doc.save();
  }
}

/// La tarjeta del QR (también la usa el catálogo en pantalla)
class StoreQrCard extends StatelessWidget {
  final String businessName;
  final String url;
  final double size;
  const StoreQrCard({super.key, required this.businessName, required this.url, this.size = 220});

  @override
  Widget build(BuildContext context) {
    // Fondo blanco y QR negro siempre: así lo lee cualquier cámara, también en modo oscuro
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(businessName, textAlign: TextAlign.center, style: AppText.title(context, color: Colors.black)),
          const SizedBox(height: AppSpace.xs),
          Text('Escanea y pide aquí', style: AppText.body(context, color: Colors.black)),
          const SizedBox(height: AppSpace.md),
          BarcodeWidget(barcode: Barcode.qrCode(), data: url, width: size, height: size, color: Colors.black, backgroundColor: Colors.white),
          const SizedBox(height: AppSpace.sm),
          Text(url.replaceFirst('https://', ''), style: AppText.small(context, color: Colors.black)),
        ],
      ),
    );
  }
}

/// «Compartir» un producto: el link abre la tienda con ese producto primero (0.16.0)
class ProductShare {
  static Future<void> share(BuildContext context, {required Product product}) async {
    OnlineStoreConfig? store;
    try {
      store = await OnlineStoreService.instance.getMine(product.businessId);
    } catch (_) {}
    if (!context.mounted) return;
    if (store == null || !store.enabled) {
      AppToast.showWarning(context, 'Publica tu tienda en línea para compartir productos con un link.');
      return;
    }
    await Share.share('Mira ${product.name} a ${CurrencyFormatter.format(product.salePrice)}: ${store.productUrl(product.id)}');
  }
}
