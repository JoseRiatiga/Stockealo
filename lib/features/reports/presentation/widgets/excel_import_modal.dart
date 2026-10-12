import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../data/excel_import_service.dart';

class ExcelImportModal extends StatefulWidget {
  final String businessId;
  final VoidCallback onImportCompleted;

  const ExcelImportModal({
    super.key,
    required this.businessId,
    required this.onImportCompleted,
  });

  static Future<void> show(BuildContext context, {required String businessId, required VoidCallback onImportCompleted}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExcelImportModal(
        businessId: businessId,
        onImportCompleted: onImportCompleted,
      ),
    );
  }

  @override
  State<ExcelImportModal> createState() => _ExcelImportModalState();
}

class _ExcelImportModalState extends State<ExcelImportModal> {
  final _importService = ExcelImportService.instance;
  ImportPreview? _preview;
  bool _isLoading = false;
  bool _updateExisting = true;
  String? _errorMessage;

  Future<void> _pickFile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final preview = await _importService.inspectExcel(path);
        if (mounted) {
          setState(() {
            _preview = preview;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _runImport() async {
    if (_preview == null) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _importService.executeImport(
        filePath: _preview!.filePath,
        businessId: widget.businessId,
        updateExisting: _updateExisting,
      );

      if (!mounted) return;

      if (result.success) {
        Navigator.pop(context);
        widget.onImportCompleted();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF059669),
            duration: const Duration(seconds: 4),
            content: Text(
              '✅ Importación exitosa:\n• ${result.productsImported} productos nuevos añadidos\n• ${result.productsUpdated} productos actualizados\n• ${result.customersImported} clientes registrados.',
            ),
          ),
        );
      } else {
        setState(() {
          _errorMessage = result.errorMessage ?? 'Error desconocido al importar.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceAll('Exception: ', '');
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 24,
        left: 20,
        right: 20,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.file_upload_outlined, color: Color(0xFF059669), size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Importar Inventario desde Excel',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                      ),
                      Text(
                        'Carga masiva de productos y clientes (.xlsx)',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 24),

            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (_preview == null) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.table_view_outlined, size: 48, color: Color(0xFF059669)),
                    const SizedBox(height: 12),
                    const Text(
                      'Selecciona tu archivo de Excel',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Puedes usar una copia exportada de Stockealo o cualquier plantilla con columnas de Nombre, Precio y Stock.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _pickFile,
                      icon: _isLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.folder_open, size: 20),
                      label: const Text('Elegir archivo .xlsx'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Tarjeta de vista previa
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.check_circle_outline, color: Color(0xFF16A34A), size: 22),
                        SizedBox(width: 8),
                        Text(
                          'Archivo analizado correctamente',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF166534)),
                        ),
                      ],
                    ),
                    const Divider(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '${_preview!.productsFound}',
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                                ),
                                const Text('Productos', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '${_preview!.customersFound}',
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                                ),
                                const Text('Clientes', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_preview!.productSampleNames.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Muestra detectada: ${_preview!.productSampleNames.take(3).join(', ')}...',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF475569), fontStyle: FontStyle.italic),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeColor: const Color(0xFF059669),
                title: const Text('Actualizar existentes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: const Text('Si el producto ya existe por código o nombre, actualizar su stock y precios.', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                value: _updateExisting,
                onChanged: (val) => setState(() => _updateExisting = val),
              ),

              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : () => setState(() => _preview = null),
                      child: const Text('Cambiar archivo'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _runImport,
                      icon: _isLoading
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.file_download_done, size: 20),
                      label: const Text('Importar a Stockealo'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
