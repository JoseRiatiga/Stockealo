import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../business/models/business.dart';
import '../../models/product.dart';
import '../../../reports/data/catalog_pdf_service.dart';
import 'story_catalog_modal.dart';

class CatalogGeneratorModal extends StatefulWidget {
  final Business business;

  const CatalogGeneratorModal({super.key, required this.business});

  static Future<void> show({
    required BuildContext context,
    required Business business,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CatalogGeneratorModal(business: business),
    );
  }

  @override
  State<CatalogGeneratorModal> createState() => _CatalogGeneratorModalState();
}

class _CatalogGeneratorModalState extends State<CatalogGeneratorModal> {
  final _pdfService = CatalogPdfService.instance;
  final _authRepo = AuthRepository.instance;
  final _phoneController = TextEditingController();

  List<Product> _allInStockProducts = [];
  List<String> _categories = ['Todas'];
  String _selectedCategory = 'Todas';
  bool _showExactStock = false;
  int _itemsPerPage = 4; // 1, 2, 4, 6

  bool _isLoading = true;
  bool _isGenerating = false;
  double _progress = 0.0;
  String _statusMessage = '';

  File? _generatedFile;
  String? _savedPathLabel;
  bool _isPublicDownload = false;
  bool _isSavingToDownloads = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);

    // 1. Obtener teléfono del usuario autenticado
    final currentUser = _authRepo.currentUser;
    if (currentUser?.phone != null && currentUser!.phone!.trim().isNotEmpty) {
      _phoneController.text = currentUser.phone!.trim();
    }

    // 2. Cargar todos los productos con stock > 0
    try {
      final db = await AppDatabase.instance.database;
      final maps = await db.query(
        'products',
        where: 'business_id = ? AND is_active = 1 AND stock > 0',
        whereArgs: [widget.business.id],
        orderBy: 'category ASC, name ASC',
      );

      final products = maps.map((m) => Product.fromMap(m)).toList();
      final catSet = <String>{'Todas'};
      for (final p in products) {
        if (p.category.trim().isNotEmpty) {
          catSet.add(p.category.trim());
        }
      }

      if (mounted) {
        setState(() {
          _allInStockProducts = products;
          _categories = catSet.toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppToast.show(context, message: 'Error cargando inventario: $e', type: ToastType.error);
      }
    }
  }

  List<Product> get _filteredProducts {
    if (_selectedCategory == 'Todas') {
      return _allInStockProducts;
    }
    return _allInStockProducts
        .where((p) => p.category.toLowerCase() == _selectedCategory.toLowerCase())
        .toList();
  }

  Future<void> _generatePdf() async {
    final targets = _filteredProducts;
    if (targets.isEmpty) {
      AppToast.show(context, message: 'No hay productos disponibles en esta categoría.', type: ToastType.warning);
      return;
    }

    setState(() {
      _isGenerating = true;
      _progress = 0.05;
      _statusMessage = 'Iniciando generación de catálogo...';
    });

    try {
      final file = await _pdfService.generateCatalogPdf(
        business: widget.business,
        products: targets,
        contactPhone: _phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : null,
        showExactStock: _showExactStock,
        categoryFilter: _selectedCategory,
        itemsPerPage: _itemsPerPage,
        onProgress: (p, msg) {
          if (mounted) {
            setState(() {
              _progress = p;
              _statusMessage = msg;
            });
          }
        },
      );

      // Guardar automáticamente en el almacenamiento local / Descargas
      final savedResult = await _pdfService.saveToDownloads(
        pdfFile: file,
        businessName: widget.business.name,
      );

      if (mounted) {
        setState(() {
          _isGenerating = false;
          _generatedFile = savedResult.file;
          _savedPathLabel = savedResult.pathLabel;
          _isPublicDownload = savedResult.isPublicDownload;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        AppToast.show(context, message: 'Error generando PDF: $e', type: ToastType.error);
      }
    }
  }

  Future<void> _manualSaveToDownloads() async {
    if (_generatedFile == null) return;
    setState(() => _isSavingToDownloads = true);

    try {
      final savedResult = await _pdfService.saveToDownloads(
        pdfFile: _generatedFile!,
        businessName: widget.business.name,
      );

      if (mounted) {
        setState(() {
          _isSavingToDownloads = false;
          _generatedFile = savedResult.file;
          _savedPathLabel = savedResult.pathLabel;
          _isPublicDownload = savedResult.isPublicDownload;
        });

        AppToast.show(
          context,
          message: 'Guardado con éxito en: ${savedResult.pathLabel}',
          type: ToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingToDownloads = false);
        AppToast.show(
          context,
          message: 'Error al guardar archivo: $e',
          type: ToastType.error,
        );
      }
    }
  }

  Future<void> _shareFile() async {
    if (_generatedFile == null) return;
    final fileName = p.basename(_generatedFile!.path);

    // Compartir explícitamente como archivo PDF con mimeType y nombre
    await Share.shareXFiles(
      [
        XFile(
          _generatedFile!.path,
          mimeType: 'application/pdf',
          name: fileName,
        ),
      ],
      subject: 'Catálogo de Productos - ${widget.business.name}',
    );
  }

  Future<void> _openFile() async {
    if (_generatedFile == null) return;
    final res = await OpenFilex.open(_generatedFile!.path);
    if (res.type != ResultType.done && mounted) {
      AppToast.show(
        context,
        message: 'No se pudo abrir el visor: ${res.message}',
        type: ToastType.warning,
      );
    }
  }

  String _getFileSize(File file) {
    try {
      final bytes = file.lengthSync();
      if (bytes < 1024) return '$bytes B';
      if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final primaryTextColor = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B);
    final secondaryTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final cardBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Barra de arrastre superior
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Cabecera del Modal
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFDC2626), size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Catálogo de Productos en PDF',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: primaryTextColor,
                          ),
                        ),
                        Text(
                          'Genera un documento profesional para enviar por WhatsApp',
                          style: TextStyle(fontSize: 12, color: secondaryTextColor),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 36),
                    child: CircularProgressIndicator(color: Color(0xFF059669)),
                  ),
                )
              else if (_allInStockProducts.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cardBorder),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.inventory_2_outlined, size: 44, color: Color(0xFF94A3B8)),
                      const SizedBox(height: 10),
                      Text(
                        'No hay productos en stock',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: primaryTextColor),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Actualmente no tienes productos con existencias disponibles en "${widget.business.name}". Registra stock para generar tu catálogo.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: secondaryTextColor),
                      ),
                    ],
                  ),
                )
              else if (_isGenerating)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _progress,
                          minHeight: 10,
                          backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                          valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF059669)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        _statusMessage,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${(_progress * 100).toInt()}% completado',
                        style: TextStyle(fontSize: 11, color: secondaryTextColor),
                      ),
                    ],
                  ),
                )
              else if (_generatedFile != null)
                // Vista de Éxito y Acciones de Archivo y Compartir
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Cabecera de éxito
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF059669).withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 28),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '¡Catálogo PDF generado!',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: primaryTextColor,
                                  ),
                                ),
                                Text(
                                  '${_filteredProducts.length} productos en stock listos',
                                  style: TextStyle(fontSize: 12, color: secondaryTextColor),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Tarjeta con información del archivo y ubicación
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: cardBorder),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDC2626).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFDC2626), size: 24),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.basename(_generatedFile!.path),
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                          color: primaryTextColor,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Documento PDF • ${_getFileSize(_generatedFile!)}',
                                        style: TextStyle(fontSize: 11, color: secondaryTextColor),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              child: Divider(height: 1, color: cardBorder),
                            ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.folder_rounded, color: Color(0xFF059669), size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Guardado localmente en tu teléfono:',
                                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: secondaryTextColor),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _savedPathLabel ?? p.basename(_generatedFile!.path),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF059669),
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        _isPublicDownload
                                            ? 'Encuéntralo en tu app de "Archivos" o carpeta "Descargas".'
                                            : 'Almacenado localmente en el dispositivo.',
                                        style: TextStyle(fontSize: 10.5, color: secondaryTextColor),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Botón 1: Compartir PDF (WhatsApp / Apps)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _shareFile,
                          icon: const Icon(Icons.share_rounded, size: 20),
                          label: const Text(
                            'Compartir PDF (WhatsApp / Apps)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF059669),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Botones 2 y 3: Guardar copia en Descargas y Abrir y Ver PDF
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isSavingToDownloads ? null : _manualSaveToDownloads,
                              icon: _isSavingToDownloads
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF059669)),
                                    )
                                  : const Icon(Icons.download_rounded, size: 18),
                              label: Text(_isSavingToDownloads ? 'Guardando...' : 'Guardar Copia'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: primaryTextColor,
                                side: BorderSide(color: cardBorder),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _openFile,
                              icon: const Icon(Icons.visibility_rounded, size: 18),
                              label: const Text('Abrir y Ver'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF059669),
                                side: const BorderSide(color: Color(0xFF059669)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Botón para generar otro catálogo con otros filtros
                      Center(
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _generatedFile = null;
                              _savedPathLabel = null;
                            });
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Generar otro catálogo', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            foregroundColor: secondaryTextColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                // Formulario de Configuración del Catálogo
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Resumen de productos disponibles
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: cardBorder),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.inventory_2, color: Color(0xFF059669), size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${_filteredProducts.length} productos en stock',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: primaryTextColor),
                                ),
                                Text(
                                  'Solo se incluirán productos con inventario disponible',
                                  style: TextStyle(fontSize: 11, color: secondaryTextColor),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Selector de Categoría
                    Text(
                      'Categoría a Incluir:',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryTextColor),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cardBorder),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedCategory,
                          isExpanded: true,
                          dropdownColor: cardBg,
                          items: _categories.map((cat) {
                            final count = cat == 'Todas'
                                ? _allInStockProducts.length
                                : _allInStockProducts.where((p) => p.category.toLowerCase() == cat.toLowerCase()).length;
                            return DropdownMenuItem<String>(
                              value: cat,
                              child: Text(
                                '$cat ($count productos)',
                                style: TextStyle(fontSize: 13, color: primaryTextColor),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _selectedCategory = val);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Teléfono de Contacto para Pedidos
                    Text(
                      'Teléfono de Contacto (para WhatsApp en el PDF):',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryTextColor),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: 'Ej: 314 806 7908',
                        prefixIcon: const Icon(Icons.phone_android_rounded, color: Color(0xFF059669), size: 20),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Switch: Mostrar cantidad de stock o solo "Disponible"
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cardBorder),
                      ),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Mostrar unidades exactas de stock',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: primaryTextColor),
                        ),
                        subtitle: Text(
                          _showExactStock
                              ? 'Mostrará: "Stock: 12 und."'
                              : 'Mostrará discretamente: "Disponible"',
                          style: TextStyle(fontSize: 11, color: secondaryTextColor),
                        ),
                        value: _showExactStock,
                        activeColor: const Color(0xFF059669),
                        onChanged: (val) => setState(() => _showExactStock = val),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Selector de Densidad de Productos por Página
                    Text(
                      'Productos por Página:',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryTextColor),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _buildDensityOption(1, '1 Prod.', 'Hero', isDark, cardBorder, primaryTextColor),
                        const SizedBox(width: 6),
                        _buildDensityOption(2, '2 Prod.', 'Dúo', isDark, cardBorder, primaryTextColor),
                        const SizedBox(width: 6),
                        _buildDensityOption(4, '4 Prod.', 'Grilla', isDark, cardBorder, primaryTextColor),
                        const SizedBox(width: 6),
                        _buildDensityOption(6, '6 Prod.', 'Lista', isDark, cardBorder, primaryTextColor),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Botón Principal de Generación PDF
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _generatePdf,
                        icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
                        label: Text(
                          'Descargar Catálogo PDF (${_filteredProducts.length} productos)',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Botón Especial para Historias de Redes Sociales (PNG 9:16)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          StoryCatalogModal.show(
                            context: context,
                            business: widget.business,
                            products: _filteredProducts,
                            contactPhone: _phoneController.text.trim().isNotEmpty
                                ? _phoneController.text.trim()
                                : null,
                            itemsPerPage: _itemsPerPage == 6 ? 4 : _itemsPerPage,
                          );
                        },
                        icon: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF8B5CF6), size: 18),
                        label: const Text(
                          'Crear Historias para Redes (PNG 9:16)',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6)),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF8B5CF6), width: 1.3),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDensityOption(int count, String label, String sublabel, bool isDark, Color cardBorder, Color primaryTextColor) {
    final isSelected = _itemsPerPage == count;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _itemsPerPage = count),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF059669).withOpacity(0.15)
                : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF059669) : cardBorder,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? const Color(0xFF059669) : primaryTextColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                sublabel,
                style: TextStyle(
                  fontSize: 9.5,
                  color: isSelected ? const Color(0xFF059669) : const Color(0xFF94A3B8),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
