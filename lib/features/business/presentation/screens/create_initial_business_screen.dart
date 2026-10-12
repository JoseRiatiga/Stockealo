import 'package:flutter/material.dart';
import '../../../../core/utils/currency_options.dart';
import '../../data/business_repository.dart';

class CreateInitialBusinessScreen extends StatefulWidget {
  final String userId;
  final VoidCallback onBusinessCreated;

  const CreateInitialBusinessScreen({
    super.key,
    required this.userId,
    required this.onBusinessCreated,
  });

  @override
  State<CreateInitialBusinessScreen> createState() => _CreateInitialBusinessScreenState();
}

class _CreateInitialBusinessScreenState extends State<CreateInitialBusinessScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessRepo = BusinessRepository.instance;

  final _nameController = TextEditingController();
  String _selectedCurrency = 'COP';
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _businessRepo.createBusiness(
        name: _nameController.text.trim(),
        userId: widget.userId,
        currency: _selectedCurrency,
      );

      if (mounted) {
        widget.onBusinessCreated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.storefront,
                      size: 44,
                      color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '¡Crea tu Negocio!',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Para comenzar a registrar productos y ventas, asigna el nombre a tu primera empresa o tienda.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Nombre del negocio
                  TextFormField(
                    controller: _nameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de tu Negocio *',
                      hintText: 'Ej. Minimarket Don José, Tienda de Ropa...',
                      prefixIcon: Icon(Icons.store, color: Color(0xFF64748B)),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Ingresa el nombre de tu negocio';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 18),

                  // Moneda
                  DropdownButtonFormField<String>(
                    value: _selectedCurrency,
                    decoration: const InputDecoration(
                      labelText: 'Moneda Principal',
                      prefixIcon: Icon(Icons.monetization_on_outlined, color: Color(0xFF64748B)),
                    ),
                    items: kAvailableCurrencies.map((c) {
                      return DropdownMenuItem(
                        value: c.code,
                        child: Text(c.label),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedCurrency = val);
                    },
                  ),
                  const SizedBox(height: 32),

                  // Botón Comenzar
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _submit,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward),
                      label: Text(
                        _isLoading ? 'Creando...' : 'Crear y Comenzar',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
