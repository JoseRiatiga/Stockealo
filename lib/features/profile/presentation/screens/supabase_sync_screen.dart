import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/services/supabase_service.dart';

class SupabaseSyncScreen extends StatefulWidget {
  const SupabaseSyncScreen({super.key});

  @override
  State<SupabaseSyncScreen> createState() => _SupabaseSyncScreenState();
}

class _SupabaseSyncScreenState extends State<SupabaseSyncScreen> {
  final _supabase = SupabaseService.instance;
  bool _isTesting = false;
  bool _isSyncing = false;
  String? _statusMessage;
  bool _isSuccess = false;
  bool _needsTables = false;

  Future<void> _runConnectionTest() async {
    setState(() {
      _isTesting = true;
      _statusMessage = null;
      _needsTables = false;
    });

    final result = await _supabase.testConnection();

    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _isSuccess = result['success'] == true;
      _needsTables = result['needsTables'] == true;
      _statusMessage = result['message'] as String?;
    });
  }

  Future<void> _runSync() async {
    setState(() {
      _isSyncing = true;
      _statusMessage = null;
      _needsTables = false;
    });

    final result = await _supabase.syncToCloud();

    if (!mounted) return;
    setState(() {
      _isSyncing = false;
      _isSuccess = result.success;
      if (result.success) {
        _statusMessage =
            '✅ Sincronización exitosa:\n• ${result.businessesCount} empresas\n• ${result.membersCount} colaboradores/miembros\n• ${result.productsCount} productos\n• ${result.customersCount} clientes\n• ${result.salesCount} ventas respaldadas en la nube.';
      } else {
        _statusMessage = result.errorMessage ?? 'Error durante la sincronización.';
        if (_statusMessage!.contains('schema cache') ||
            _statusMessage!.contains('does not exist')) {
          _needsTables = true;
        }
      }
    });
  }

  void _copySqlScript() {
    Clipboard.setData(const ClipboardData(text: SupabaseService.sqlSetupScript));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('¡Script SQL copiado al portapapeles! Pégalo en Supabase SQL Editor.'),
        backgroundColor: Color(0xFF059669),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Conexión Supabase (Nube)',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        elevation: 0,
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        foregroundColor: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Tarjeta de Estado
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.2 : 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.cloud_done, color: Color(0xFF10B981), size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Supabase Cloud',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                              ),
                            ),
                            Text(
                              'Respaldo y sincronización en tiempo real',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF064E3B) : const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0),
                          ),
                        ),
                        child: Text(
                          'Activo',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Divider(
                    height: 28,
                    color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                  ),
                  _buildInfoRow('Proyecto ID', 'evdwwmkafwjyfawsufjb', isDark),
                  const SizedBox(height: 8),
                  _buildInfoRow('Servidor', 'evdwwmkafwjyfawsufjb.supabase.co', isDark),
                  const SizedBox(height: 8),
                  _buildInfoRow('Tipo de Clave', 'JWT Anon Key (Configurada)', isDark),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Acciones principales
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isTesting || _isSyncing ? null : _runConnectionTest,
                    icon: _isTesting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.network_ping, size: 20),
                    label: Text(_isTesting ? 'Probando...' : 'Probar conexión'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isTesting || _isSyncing ? null : _runSync,
                    icon: _isSyncing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.cloud_upload, size: 20),
                    label: Text(_isSyncing ? 'Subiendo...' : 'Sincronizar'),
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

            if (_statusMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _isSuccess
                      ? (isDark ? const Color(0xFF064E3B).withOpacity(0.4) : const Color(0xFFF0FDF4))
                      : (isDark ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isSuccess
                        ? (isDark ? const Color(0xFF059669) : const Color(0xFFBBF7D0))
                        : (isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA)),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _isSuccess ? Icons.check_circle : Icons.warning_amber_rounded,
                      color: _isSuccess
                          ? (isDark ? const Color(0xFF34D399) : const Color(0xFF16A34A))
                          : (isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626)),
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _statusMessage!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _isSuccess
                              ? (isDark ? const Color(0xFF6EE7B7) : const Color(0xFF166534))
                              : (isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Tarjeta de Guía para Crear las Tablas
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _needsTables
                    ? (isDark ? const Color(0xFF451A03) : const Color(0xFFFFFBEB))
                    : (isDark ? const Color(0xFF1E293B) : Colors.white),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _needsTables
                      ? const Color(0xFFF59E0B)
                      : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                  width: _needsTables ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.terminal, color: Color(0xFFD97706), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Paso importante: Crear tablas',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Para que Supabase pueda guardar los productos y ventas, debes ejecutar el script SQL en el panel de Supabase:',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildStep(1, 'Copia el script con el botón verde de abajo.', isDark),
                  _buildStep(2, 'Abre tu proyecto en supabase.com > pestaña "SQL Editor".', isDark),
                  _buildStep(3, 'Pega el código y haz clic en "Run" (Ejecutar).', isDark),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _copySqlScript,
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copiar Script SQL para Supabase'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
                        side: BorderSide(
                          color: isDark ? const Color(0xFF059669) : const Color(0xFF059669),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(int number, String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 9,
            backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            child: Text(
              '$number',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }
}
