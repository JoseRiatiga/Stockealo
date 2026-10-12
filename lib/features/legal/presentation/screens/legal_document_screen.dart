import 'package:flutter/material.dart';

class LegalDocumentScreen extends StatelessWidget {
  final int initialTabIndex;

  const LegalDocumentScreen({
    super.key,
    this.initialTabIndex = 0,
  });

  static Future<void> show(BuildContext context, {int initialTabIndex = 0}) {
    return Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LegalDocumentScreen(initialTabIndex: initialTabIndex),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTabIndex,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Información Legal',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          bottom: const TabBar(
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Color(0xFFA7F3D0),
            indicatorWeight: 3,
            tabs: [
              Tab(icon: Icon(Icons.description_outlined), text: 'Términos de Uso'),
              Tab(icon: Icon(Icons.privacy_tip_outlined), text: 'Privacidad'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _TermsOfServiceView(),
            _PrivacyPolicyView(),
          ],
        ),
      ),
    );
  }
}

class _TermsOfServiceView extends StatelessWidget {
  const _TermsOfServiceView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildHeader(
          icon: Icons.gavel_rounded,
          title: 'Términos y Condiciones de Uso',
          subtitle: 'Última actualización: Octubre 2026',
        ),
        const SizedBox(height: 20),
        _buildSection(
          number: '1',
          title: 'Aceptación de los Términos',
          content:
              'Al crear una cuenta, acceder o utilizar la aplicación Stockealo, aceptas cumplir plenamente con estos Términos y Condiciones. Si no estás de acuerdo con alguna disposición, debes abstenerte de utilizar la plataforma.',
        ),
        _buildSection(
          number: '2',
          title: 'Naturaleza del Servicio',
          content:
              'Stockealo es una herramienta de productividad y gestión comercial diseñada para registrar inventarios, catalogar productos por códigos de barras o SKU, registrar ventas y administrar deudas de clientes ("fiado"). La app opera bajo una arquitectura Local-First, guardando tus datos en una base de datos segura en tu dispositivo de forma predeterminada.',
        ),
        _buildSection(
          number: '3',
          title: 'Exclusión de Facturación Tributaria Oficial',
          content:
              'Stockealo es una herramienta tecnológica de control interno, inventario y soporte operativo para comerciantes. No constituye ni reemplaza un sistema de facturación electrónica fiscal avalado por entidades tributarias oficiales (como DIAN, SAT u otros organismos gubernamentales). El usuario es el único responsable del cumplimiento de sus obligaciones contables, tributarias y fiscales.',
        ),
        _buildSection(
          number: '4',
          title: 'Cuentas y Múltiples Negocios',
          content:
              'Cada usuario es responsable de mantener la confidencialidad de sus credenciales. Stockealo permite la gestión de múltiples empresas o tiendas bajo una misma cuenta, garantizando que el inventario, ventas y clientes de cada empresa se encuentren 100% aislados e independientes.',
        ),
        _buildSection(
          number: '5',
          title: 'Control de Inventario y Ventas',
          content:
              'El usuario es el único responsable de la exactitud de los precios, costos y cantidades ingresadas. El sistema incluye validaciones para registrar existencias y generar órdenes de reabastecimiento, pero no reemplaza la auditoría física que el comerciante deba realizar periódicamente.',
        ),
        _buildSection(
          number: '6',
          title: 'Créditos Comerciales ("Fiados") y Datos de Clientes',
          content:
              'La función de venta a crédito o "fiado" es exclusivamente una herramienta contable de registro interno. Stockealo no actúa como entidad financiera, cobrador ni garante. El comerciante declara contar con la debida autorización de sus clientes para registrar sus números telefónicos con fines del envío voluntario de comprobantes y recibos por WhatsApp.',
        ),
        _buildSection(
          number: '7',
          title: 'Uso por Mayores de Edad',
          content:
              'La plataforma está dirigida a personas mayores de 18 años con plena capacidad legal para el ejercicio de actividades comerciales.',
        ),
        _buildSection(
          number: '8',
          title: 'Propiedad Intelectual',
          content:
              'Todos los derechos de software, diseño, logotipos y código fuente de Stockealo están protegidos por leyes de propiedad intelectual. Los datos de tus productos e imágenes registradas son y seguirán siendo de tu propiedad exclusiva.',
        ),
        _buildSection(
          number: '9',
          title: 'Modificaciones',
          content:
              'Nos reservamos el derecho de actualizar estos términos en cualquier momento. Te notificaremos dentro de la aplicación ante cualquier cambio sustancial.',
        ),
        const SizedBox(height: 30),
      ],
    );
  }
}

class _PrivacyPolicyView extends StatelessWidget {
  const _PrivacyPolicyView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildHeader(
          icon: Icons.shield_rounded,
          title: 'Política de Privacidad y Tratamiento de Datos',
          subtitle: 'Compromiso de protección de tus datos comerciales y privacidad',
        ),
        const SizedBox(height: 20),
        _buildSection(
          number: '1',
          title: 'Principio Local-First y Privacidad por Defecto',
          content:
              'En Stockealo creemos que los datos de tu negocio te pertenecen exclusivamente a ti. De manera predeterminada:\n\n'
              '• Todos tus productos, costos, ventas, clientes y ganancias se guardan EXCLUSIVAMENTE en la memoria local de tu dispositivo.\n'
              '• La aplicación NO transmite tu actividad comercial a ningún servidor externo a menos que actives voluntariamente la sincronización en la nube.',
        ),
        _buildSection(
          number: '2',
          title: 'Sincronización en la Nube Opcional (Multidispositivo y Respaldo)',
          content:
              'Para los comerciantes que requieran gestionar su inventario desde varios dispositivos a la vez, invitar a miembros de su equipo o mantener una copia de seguridad en la nube, Stockealo ofrece una opción de sincronización.\n\n'
              'Esta opción está DESACTIVADA por defecto. Si decides activarla, tus datos se transmitirán mediante protocolos encriptados (TLS/HTTPS) hacia nuestra infraestructura en la nube. Puedes desactivar la sincronización en cualquier momento desde los Ajustes de la aplicación.',
        ),
        _buildSection(
          number: '3',
          title: 'Información que Recopilamos',
          content:
              '• Cuenta: Correo electrónico y contraseña cifrada con algoritmos criptográficos unidireccionales (SHA-256 + Salting).\n'
              '• Catálogo e Inventario: Nombres de tiendas, códigos SKU/barras, costos, precios de venta y existencias.\n'
              '• Clientes y Transacciones: Nombres y teléfonos registrados por el comerciante para control de ventas y abonos de fiados.',
        ),
        _buildSection(
          number: '4',
          title: 'Permisos del Dispositivo y su Uso Estricto',
          content:
              '📷 Cámara: Se utiliza únicamente para escanear códigos de barras/QR y tomar fotografías para tus productos.\n\n'
              '🖼️ Galería y Archivos: Se utiliza para seleccionar fotos de productos y para guardar o importar reportes de inventario en Excel (.xlsx).\n\n'
              '🌐 Conexión de Red: Utilizada para validar credenciales de cuenta, sincronizar con la nube (si el usuario la activa) y abrir WhatsApp para compartir tickets de venta o pedidos.',
        ),
        _buildSection(
          number: '5',
          title: 'Mecanismos de Supresión de Datos y Derecho al Olvido',
          content:
              'De acuerdo con las normativas de protección de datos personales y las políticas de Google Play y App Store, tienes derecho a eliminar tu información en cualquier momento a través de dos opciones en Ajustes:\n\n'
              '• Purgar solo la Nube: Elimina de forma inmediata e irreversible todos tus datos en los servidores remotos, regresando la app a modo 100% local sin perder tus datos en el teléfono.\n\n'
              '• Eliminación Total de Cuenta: Borra definitivamente toda tu información tanto en la nube como en la base de datos de tu teléfono móvil.',
        ),
        _buildSection(
          number: '6',
          title: 'Canal Oficial de Contacto y Soporte',
          content:
              'Para cualquier solicitud de privacidad, consulta sobre el tratamiento de tus datos o soporte técnico, puedes comunicarte directamente con nosotros a través del correo oficial:\n\n'
              '📧 byjosealbert@gmail.com',
        ),
        const SizedBox(height: 30),
      ],
    );
  }
}

Widget _buildHeader({
  required IconData icon,
  required String title,
  required String subtitle,
}) {
  return _LegalHeader(icon: icon, title: title, subtitle: subtitle);
}

class _LegalHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _LegalHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF064E3B).withOpacity(0.3) : const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: const Color(0xFF059669),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFFA7F3D0) : const Color(0xFF065F46),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _buildSection({
  required String number,
  required String title,
  required String content,
}) {
  return _LegalSection(number: number, title: title, content: content);
}

class _LegalSection extends StatelessWidget {
  final String number;
  final String title;
  final String content;

  const _LegalSection({
    required this.number,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
              ),
            ),
            child: Text(
              number,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF334155),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  content,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
