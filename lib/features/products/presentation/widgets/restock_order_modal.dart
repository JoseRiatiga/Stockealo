import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../business/models/business.dart';
import '../../data/product_repository.dart';
import '../../models/product.dart';

class RestockOrderItem {
  final Product product;
  int orderQty;
  bool isSelected;

  RestockOrderItem({
    required this.product,
    required this.orderQty,
    this.isSelected = true,
  });
}

class RestockOrderModal extends StatefulWidget {
  final Business business;
  final String? userName;

  const RestockOrderModal({
    super.key,
    required this.business,
    this.userName,
  });

  static Future<void> show(
    BuildContext context, {
    required Business business,
    String? userName,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RestockOrderModal(
        business: business,
        userName: userName,
      ),
    );
  }

  @override
  State<RestockOrderModal> createState() => _RestockOrderModalState();
}

class _RestockOrderModalState extends State<RestockOrderModal> {
  final _productRepo = ProductRepository();
  final _searchController = TextEditingController();

  List<RestockOrderItem> _items = [];
  List<Product> _allProducts = [];
  bool _isLoading = true;
  String _searchFilter = '';

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    final restockProducts = await _productRepo.getRestockProducts(widget.business.id);
    _allProducts = await _productRepo.getAllProducts(widget.business.id);

    final List<RestockOrderItem> items = [];
    for (final p in restockProducts) {
      // Cálculo inteligente de sugerencia: reponer hasta el doble del stock mínimo
      final suggested = p.minStock > 0
          ? (p.minStock * 2 - p.stock).clamp(1, 9999)
          : (p.stock <= 0 ? 10 : 5);

      items.add(RestockOrderItem(
        product: p,
        orderQty: suggested,
        isSelected: true,
      ));
    }

    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
    }
  }

  void _showAddOtherProductSheet() {
    final available = _allProducts
        .where((p) => !_items.any((item) => item.product.id == p.id))
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1E293B)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = available
                .where((p) =>
                    p.name.toLowerCase().contains(query.toLowerCase()) ||
                    p.code.toLowerCase().contains(query.toLowerCase()))
                .toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Agregar Producto del Catálogo',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Buscar por nombre o código...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (val) => setModalState(() => query = val),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No se encontraron productos'))
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final p = filtered[index];
                              return ListTile(
                                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text('Stock actual: ${p.stock} • Cód: ${p.code}'),
                                trailing: const Icon(Icons.add_circle_outline, color: Color(0xFF059669)),
                                onTap: () {
                                  setState(() {
                                    _items.insert(
                                      0,
                                      RestockOrderItem(
                                        product: p,
                                        orderQty: p.minStock > 0 ? p.minStock : 5,
                                        isSelected: true,
                                      ),
                                    );
                                  });
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _editQuantity(RestockOrderItem item) {
    final controller = TextEditingController(text: '${item.orderQty}');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(item.product.name, style: const TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ingresa la cantidad a solicitar al proveedor:', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Unidades a pedir',
                suffixText: 'unid.',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim()) ?? 0;
              if (parsed > 0) {
                setState(() => item.orderQty = parsed);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Aceptar'),
          ),
        ],
      ),
    );
  }

  String _buildOrderText() {
    final selectedItems = _items.where((i) => i.isSelected && i.orderQty > 0).toList();
    final dateStr = DateFormat('dd/MM/yyyy hh:mm a').format(DateTime.now());
    final sender = widget.userName ?? 'Administrador';

    int totalUnits = 0;
    double estimatedCost = 0.0;

    final buffer = StringBuffer();
    buffer.writeln('📦 *ORDEN DE PEDIDO A PROVEEDOR*');
    buffer.writeln('🏪 *${widget.business.name.toUpperCase()}*');
    buffer.writeln('📅 Fecha: $dateStr');
    buffer.writeln('👤 Solicitado por: $sender');
    buffer.writeln('────────────────────────');
    buffer.writeln('*PRODUCTOS SOLICITADOS:*');

    for (final item in selectedItems) {
      final p = item.product;
      final codeInfo = p.code.isNotEmpty ? ' (Cód: ${p.code})' : '';
      buffer.writeln('• ${item.orderQty}x ${p.name}$codeInfo');
      totalUnits += item.orderQty;
      if (p.purchasePrice > 0) {
        estimatedCost += (p.purchasePrice * item.orderQty);
      }
    }

    buffer.writeln('────────────────────────');
    buffer.writeln('📊 *RESUMEN:*');
    buffer.writeln('• Total de productos: ${selectedItems.length}');
    buffer.writeln('• Total de unidades: $totalUnits unid.');
    if (estimatedCost > 0) {
      buffer.writeln('• Costo estimado: ${CurrencyFormatter.format(estimatedCost)}');
    }
    buffer.writeln('');
    buffer.writeln('💬 _Por favor confirmar recepción y tiempo estimado de entrega. ¡Muchas gracias!_');

    return buffer.toString();
  }

  Future<void> _shareViaWhatsApp() async {
    final text = _buildOrderText();
    await Share.share(text, subject: 'Orden de Pedido - ${widget.business.name}');
  }

  void _copyOrderText() {
    final text = _buildOrderText();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📋 Orden de pedido copiada al portapapeles.'),
        backgroundColor: Color(0xFF059669),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    final selectedItems = _items.where((i) => i.isSelected && i.orderQty > 0).toList();
    final int totalProductsSelected = selectedItems.length;
    int totalUnitsSelected = 0;
    double totalEstimatedInvestment = 0.0;

    for (final item in selectedItems) {
      totalUnitsSelected += item.orderQty;
      if (item.product.purchasePrice > 0) {
        totalEstimatedInvestment += (item.product.purchasePrice * item.orderQty);
      }
    }

    final filteredItems = _items.where((i) {
      if (_searchFilter.isEmpty) return true;
      final query = _searchFilter.toLowerCase();
      return i.product.name.toLowerCase().contains(query) ||
          i.product.code.toLowerCase().contains(query);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.90,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.local_shipping_outlined,
                    color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pedido a Proveedor',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Generador inteligente de reposición',
                        style: TextStyle(fontSize: 12, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Search & Action Controls
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Filtrar lista...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchFilter = '');
                                },
                              )
                            : null,
                      ),
                      onChanged: (val) => setState(() => _searchFilter = val),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _showAddOtherProductSheet,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Agregar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF059669),
                    side: const BorderSide(color: Color(0xFF059669)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Select All / Deselect All Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_items.length} sugeridos para reposición',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                ),
                TextButton(
                  onPressed: () {
                    final allSelected = _items.every((i) => i.isSelected);
                    setState(() {
                      for (final i in _items) {
                        i.isSelected = !allSelected;
                      }
                    });
                  },
                  child: Text(
                    _items.every((i) => i.isSelected) ? 'Deseleccionar todo' : 'Seleccionar todo',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Items List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF059669)))
                : _items.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.check_circle_outline, size: 64, color: Color(0xFF059669)),
                              const SizedBox(height: 16),
                              const Text(
                                '¡Inventario en orden!',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'No hay productos agotados ni con stock bajo según sus niveles mínimos.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                onPressed: _showAddOtherProductSheet,
                                icon: const Icon(Icons.add),
                                label: const Text('Agregar productos manualmente'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        itemCount: filteredItems.length,
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          final p = item.product;
                          final isOutOfStock = p.isOutOfStock;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: item.isSelected ? const Color(0xFF059669).withOpacity(0.5) : borderColor,
                                width: item.isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  // Checkbox
                                  Checkbox(
                                    value: item.isSelected,
                                    activeColor: const Color(0xFF059669),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                    onChanged: (val) {
                                      setState(() => item.isSelected = val ?? false);
                                    },
                                  ),

                                  // Product details
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            // Stock pill
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isOutOfStock
                                                    ? (isDark ? const Color(0xFF7F1D1D).withOpacity(0.4) : const Color(0xFFFEE2E2))
                                                    : (isDark ? const Color(0xFF78350F).withOpacity(0.4) : const Color(0xFFFEF3C7)),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                isOutOfStock ? 'Agotado (0)' : 'Stock: ${p.stock} / Mín: ${p.minStock}',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: isOutOfStock
                                                      ? (isDark ? const Color(0xFFFCA5A5) : const Color(0xFFDC2626))
                                                      : (isDark ? const Color(0xFFFCD34D) : const Color(0xFFD97706)),
                                                ),
                                              ),
                                            ),
                                            if (p.purchasePrice > 0) ...[
                                              const SizedBox(width: 8),
                                              Text(
                                                'Costo: ${CurrencyFormatter.format(p.purchasePrice)}',
                                                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // Stepper Controls
                                  Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, size: 22),
                                        color: const Color(0xFF64748B),
                                        onPressed: () {
                                          if (item.orderQty > 1) {
                                            setState(() => item.orderQty--);
                                          }
                                        },
                                      ),
                                      InkWell(
                                        onTap: () => _editQuantity(item),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: isDark ? const Color(0xFF334155) : const Color(0xFFF1F5F9),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            '${item.orderQty}',
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_outline, size: 22),
                                        color: const Color(0xFF059669),
                                        onPressed: () {
                                          setState(() => item.orderQty++);
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // Bottom Bar (Summary & WhatsApp Order Button)
          Container(
            padding: EdgeInsets.fromLTRB(
              20,
              14,
              20,
              MediaQuery.of(context).padding.bottom + 16,
            ),
            decoration: BoxDecoration(
              color: cardBg,
              border: Border(top: BorderSide(color: borderColor)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$totalProductsSelected productos seleccionados',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          '$totalUnitsSelected unidades en total',
                          style: TextStyle(fontSize: 11, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                        ),
                      ],
                    ),
                    if (totalEstimatedInvestment > 0)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Inversión estimada:',
                            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                          Text(
                            CurrencyFormatter.format(totalEstimatedInvestment),
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF059669)),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Botón Copiar
                    IconButton.filledTonal(
                      onPressed: selectedItems.isEmpty ? null : _copyOrderText,
                      icon: const Icon(Icons.copy_outlined, size: 20),
                      tooltip: 'Copiar orden de pedido',
                    ),
                    const SizedBox(width: 8),

                    // Botón Enviar WhatsApp
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: selectedItems.isEmpty ? null : _shareViaWhatsApp,
                        icon: const Icon(Icons.share, size: 20),
                        label: const Text(
                          'Enviar Pedido por WhatsApp',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF059669),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
