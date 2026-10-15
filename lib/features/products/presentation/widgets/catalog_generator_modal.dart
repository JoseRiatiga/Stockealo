import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../business/models/business.dart';
import '../../models/product.dart';
import '../../../reports/data/catalog_pdf_service.dart';

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

  bool _isLoading = true;
  bool _isGenerating = false;
  double _progress = 0.0;
  String _statusMessage = '';

  File? _generatedFile;

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
        onProgress: (p, msg) {
          if (mounted) {
            setState(() {
              _progress = p;
              _statusMessage = msg;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isGenerating = false;
          _generatedFile = file;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        AppToast.show(context, message: 'Error generando PDF: $e', type: ToastType.error);
      }
    }
  }

  Future<void> _shareFile() async {
    if (_generatedFile == null) return;
    final phone = _phoneController.text.trim();
    final text = '🛍️ ¡Hola! Te comparto nuestro catálogo de productos en existencia de *${widget.business.name}*.'
        '${phone.isNotEmpty ? '\n\n📲 Escríbenos al WhatsApp $phone para tomar tu pedido.' : ''}';

    await Share.shareXFiles(
      [XFile(_generatedFile!.path)],
      text: text,
      subject: 'Catálogo de Productos - ${widget.business.name}',
    );
  }

  Future<void> _openFile() async {
    if (_generatedFile == null) return;
    await OpenFilex.open(_generatedFile!.path);
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
                // Vista de Éxito y Acciones de Compartir
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF064E3B).withOpacity(0.2) : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 46),
                      const SizedBox(height: 10),
                      Text(
                        '¡Catálogo generado con éxito!',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF065F46),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_filteredProducts.length} productos listos para compartir en alta resolución.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Botón Compartir
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _shareFile,
                          icon: const Icon(Icons.share_rounded, size: 20),
                          label: const Text('Compartir por WhatsApp / Enviar', style: TextStyle(fontWeight: FontWeight.bold)),
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

                      // Botón Abrir PDF
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _openFile,
                          icon: const Icon(Icons.visibility_rounded, size: 18),
                          label: const Text('Abrir y Ver PDF'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF065F46),
                            side: BorderSide(color: isDark ? const Color(0xFF059669) : const Color(0xFF059669)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                    const SizedBox(height: 18),

                    // Botón Principal de Generación
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _generatePdf,
                        icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
                        label: Text(
                          'Generar Catálogo (${_filteredProducts.length} productos)',
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
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
