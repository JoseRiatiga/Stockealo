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
              'Stockealo es una herramienta de productividad y gestión comercial diseñada para registrar inventarios, catalogar productos por códigos de barras o SKU, registrar ventas y administrar deudas de clientes ("fiado"). La app opera bajo una arquitectura Local-First, guardando tus datos en una base de datos segura en tu dispositivo.',
        ),
        _buildSection(
          number: '3',
          title: 'Cuentas y Múltiples Negocios',
          content:
              'Cada usuario es responsable de mantener la confidencialidad de sus credenciales. Stockealo permite la gestión de múltiples empresas o tiendas bajo una misma cuenta, garantizando que el inventario, ventas y clientes de cada empresa se encuentren 100% aislados e independientes.',
        ),
        _buildSection(
          number: '4',
          title: 'Control de Inventario y Ventas',
          content:
              'El usuario es el único responsable de la exactitud de los precios, costos y cantidades ingresadas. El sistema incluye validaciones estrictas para impedir la venta de artículos sin existencias, pero no reemplaza la auditoría física que el comerciante deba realizar periódicamente.',
        ),
        _buildSection(
          number: '5',
          title: 'Créditos Comerciales ("Fiados")',
          content:
              'La función de venta a crédito o "fiado" es exclusivamente una herramienta contable y de registro. Stockealo no actúa como entidad financiera, cobrador ni garante entre el comerciante y sus clientes finales.',
        ),
        _buildSection(
          number: '6',
          title: 'Propiedad Intelectual',
          content:
              'Todos los derechos de software, diseño, logotipos y código fuente de Stockealo están protegidos por leyes de propiedad intelectual. Los datos de tus productos e imágenes registradas son y seguirán siendo de tu propiedad exclusiva.',
        ),
        _buildSection(
          number: '7',
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
          subtitle: 'Compromiso de protección de tus datos comerciales',
        ),
        const SizedBox(height: 20),
        _buildSection(
          number: '1',
          title: 'Principio Local-First y Privacidad Absoluta',
          content:
              'En Stockealo creemos que los datos de tu negocio te pertenecen exclusivamente a ti. Tus productos, costos, márgenes de ganancia, clientes y ventas se almacenan de manera local y encriptada en tu dispositivo. No vendemos ni compartimos tu información comercial con terceros.',
        ),
        _buildSection(
          number: '2',
          title: 'Información que Recopilamos',
          content:
              '• Cuenta: Dirección de correo electrónico y contraseña cifrada para autenticación y gestión de acceso.\n'
              '• Negocios y Catálogo: Nombres de tiendas, códigos SKU/barras, descripciones, precios y stock.\n'
              '• Clientes y Transacciones: Nombres de clientes y saldos de deuda registrados exclusivamente para tu control comercial.',
        ),
        _buildSection(
          number: '3',
          title: 'Permisos del Dispositivo y su Uso Estricto',
          content:
              'Para su correcto funcionamiento, Stockealo solicita los siguientes permisos en Android/iOS:\n\n'
              '📷 Cámara: Se utiliza con el único fin de escanear códigos de barras / QR y capturar fotografías de tus productos para el catálogo.\n\n'
              '🖼️ Galería y Almacenamiento: Se utiliza para permitirte seleccionar imágenes de tus productos y almacenar copias locales optimizadas en el almacenamiento privado de la app.\n\n'
              'No accedemos a tus fotos personales ni a tus contactos.',
        ),
        _buildSection(
          number: '4',
          title: 'Almacenamiento de Fotos',
          content:
              'Las fotos tomadas o seleccionadas para tus productos se comprimen a resolución óptima (800x800 px) y se guardan en el directorio privado de la aplicación para no consumir espacio innecesario en tu teléfono.',
        ),
        _buildSection(
          number: '5',
          title: 'Tus Derechos',
          content:
              'En cualquier momento puedes exportar tus registros, editar tu catálogo o eliminar tu cuenta junto con toda la base de datos asociada desde la configuración de la aplicación.',
        ),
        _buildSection(
          number: '6',
          title: 'Contacto y Soporte',
          content:
              'Si tienes dudas sobre el tratamiento de tus datos o los términos de la aplicación, puedes comunicarte con nuestro equipo de soporte a través de los canales oficiales de Stockealo.',
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
  return Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFFECFDF5),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFA7F3D0)),
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
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF065F46),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF047857),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildSection({
  required String number,
  required String title,
  required String content,
}) {
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
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFCBD5E1)),
          ),
          child: Text(
            number,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Color(0xFF334155),
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
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                content,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Color(0xFF475569),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
