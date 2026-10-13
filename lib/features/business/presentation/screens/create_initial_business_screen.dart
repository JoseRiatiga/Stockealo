import 'package:flutter/material.dart';
import '../../../../core/utils/currency_options.dart';
import '../../../auth/data/auth_repository.dart';
import '../../../products/presentation/screens/barcode_scanner_screen.dart';
import '../../../team/data/team_repository.dart';
import '../../data/business_repository.dart';

class CreateInitialBusinessScreen extends StatefulWidget {
  final String userId;
  final String? userEmail;
  final String? userName;
  final VoidCallback onBusinessCreated;

  const CreateInitialBusinessScreen({
    super.key,
    required this.userId,
    this.userEmail,
    this.userName,
    required this.onBusinessCreated,
  });

  @override
  State<CreateInitialBusinessScreen> createState() => _CreateInitialBusinessScreenState();
}

class _CreateInitialBusinessScreenState extends State<CreateInitialBusinessScreen> {
  final _formKey = GlobalKey<FormState>();
  final _businessRepo = BusinessRepository.instance;
  final _teamRepo = TeamRepository.instance;

  // Modo: false = Soy Dueño (Crear), true = Soy Colaborador (Unirse)
  bool _isJoiningTeam = false;

  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  String _selectedCurrency = 'COP';
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// Crea un nuevo negocio desde cero (Rol Dueño)
  Future<void> _submitCreateBusiness() async {
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

  /// Abre la cámara para escanear el Código QR del negocio (Opción B)
  Future<void> _scanQrCode() async {
    final scanned = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
    );
    if (scanned != null && scanned.trim().isNotEmpty) {
      _joinWithCode(scanned.trim());
    }
  }

  /// Procesa la vinculación usando un código o QR escaneado (Opción A y B)
  Future<void> _joinWithCode(String rawCode) async {
    final code = rawCode.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa o escanea un código de invitación válido.')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final email = widget.userEmail ?? AuthRepository.instance.currentUser?.email ?? '';
      final name = widget.userName ?? AuthRepository.instance.currentUser?.name;
      final business = await _teamRepo.joinBusinessByCode(
        codeOrId: code,
        userId: widget.userId,
        userEmail: email,
        userName: name,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('¡Te has unido exitosamente a ${business.name}!'),
            backgroundColor: const Color(0xFF059669),
          ),
        );
        widget.onBusinessCreated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
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
    final primaryTextColor = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B);
    final secondaryTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Selector / Switcher de Rol (Soy Dueño vs Soy Colaborador)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      // Pestaña Dueño
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isJoiningTeam = false),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: !_isJoiningTeam
                                  ? (isDark ? const Color(0xFF334155) : Colors.white)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: !_isJoiningTeam
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.06),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : [],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.storefront,
                                  size: 18,
                                  color: !_isJoiningTeam
                                      ? const Color(0xFF059669)
                                      : secondaryTextColor,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Soy Dueño',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: !_isJoiningTeam ? primaryTextColor : secondaryTextColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Pestaña Colaborador
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _isJoiningTeam = true),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _isJoiningTeam
                                  ? (isDark ? const Color(0xFF334155) : Colors.white)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: _isJoiningTeam
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.06),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : [],
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.group_add_rounded,
                                  size: 18,
                                  color: _isJoiningTeam
                                      ? const Color(0xFF059669)
                                      : secondaryTextColor,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Soy Colaborador',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: _isJoiningTeam ? primaryTextColor : secondaryTextColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Ícono de cabecera
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    !_isJoiningTeam ? Icons.storefront : Icons.qr_code_scanner,
                    size: 40,
                    color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                  ),
                ),
                const SizedBox(height: 18),

                // Título y Descripción dinámicos según pestaña
                Text(
                  !_isJoiningTeam ? '¡Crea tu Negocio!' : 'Únete a tu Tienda',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: primaryTextColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  !_isJoiningTeam
                      ? 'Asigna un nombre a tu empresa o comercio para comenzar a gestionar inventario y ventas.'
                      : 'Pídele al dueño el Código de Invitación o escanea su Código QR para ingresar de inmediato.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: secondaryTextColor, height: 1.3),
                ),
                const SizedBox(height: 28),

                // CONTENIDO SEGÚN PESTAÑA
                if (!_isJoiningTeam) ...[
                  // ================= Formulario Crear Empresa =================
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _nameController,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'Nombre de tu Negocio *',
                            hintText: 'Ej. Minimarket Don José, Tienda...',
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
                        const SizedBox(height: 28),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _submitCreateBusiness,
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
                ] else ...[
                  // ================= Opciones Unirse a Equipo (A y B) =================
                  Column(
                    children: [
                      // 1. Opción B: Botón Principal Escanear QR
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _scanQrCode,
                          icon: const Icon(Icons.qr_code_scanner, size: 22),
                          label: const Text(
                            'Escanear Código QR',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                      const SizedBox(height: 22),

                      // Separador con texto
                      Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Text(
                              'O escribe el código',
                              style: TextStyle(fontSize: 12, color: secondaryTextColor),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),

                      // 2. Opción A: Campo para ingresar el Código de Invitación
                      TextFormField(
                        controller: _codeController,
                        textCapitalization: TextCapitalization.characters,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2.5,
                          color: Color(0xFF059669),
                        ),
                        decoration: InputDecoration(
                          labelText: 'Código de Invitación',
                          hintText: 'Ej. 6CC1-4831',
                          prefixIcon: const Icon(Icons.pin, color: Color(0xFF64748B)),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () => _codeController.clear(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : () => _joinWithCode(_codeController.text),
                          icon: _isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF059669)),
                                )
                              : const Icon(Icons.check_circle_outline, size: 18),
                          label: Text(
                            _isLoading ? 'Verificando...' : 'Unirme con Código',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF059669),
                            side: const BorderSide(color: Color(0xFF059669), width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),

                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
