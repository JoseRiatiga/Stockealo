import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';

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
    final c = context.colors;
    return DefaultTabController(
      length: 2,
      initialIndex: initialTabIndex,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'Información Legal',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          bottom: TabBar(
            indicatorColor: c.accent,
            labelColor: c.ink,
            unselectedLabelColor: c.inkMuted,
            dividerColor: c.line,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700),
            tabs: const [
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final double hPadding = math.max(20.0, (constraints.maxWidth - 780) / 2);
        return ListView(
          padding: EdgeInsets.fromLTRB(hPadding, 20, hPadding, 30),
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
              'Stockealo es una herramienta de productividad y gestión comercial diseñada para registrar inventarios, catalogar productos por códigos de barras o SKU, registrar ventas, administrar deudas de clientes ("fiado"), crear catálogos y consultar a Stocky, el asistente del negocio. La app opera bajo una arquitectura Local-First: tus datos se guardan primero en tu dispositivo.',
        ),
        _buildSection(
          number: '3',
          title: 'Exclusión de Facturación Tributaria Oficial',
          content:
              'Stockealo es una herramienta tecnológica de control interno, inventario y soporte operativo para comerciantes. No constituye ni reemplaza un sistema de facturación electrónica fiscal avalado por entidades tributarias oficiales (como DIAN, SAT u otros organismos gubernamentales). El usuario es el único responsable del cumplimiento de sus obligaciones contables, tributarias y fiscales.',
        ),
        _buildSection(
          number: '4',
          title: 'Cuentas, Negocios y Equipo',
          content:
              'Cada usuario es responsable de mantener la confidencialidad de sus credenciales. Stockealo permite gestionar varios negocios bajo una misma cuenta, con el inventario, las ventas y los clientes de cada negocio separados. El dueño de un negocio decide a quién invita a su equipo y qué puede hacer cada miembro; la app guarda un historial de actividad del equipo para que el dueño sepa quién hizo cada movimiento.',
        ),
        _buildSection(
          number: '5',
          title: 'Control de Inventario y Ventas',
          content:
              'El usuario es el único responsable de la exactitud de los precios, costos y cantidades ingresadas. El sistema incluye validaciones para registrar existencias y generar órdenes de reabastecimiento, pero no reemplaza la auditoría física que el comerciante deba realizar periódicamente.',
        ),
        _buildSection(
          number: '6',
          title: 'Créditos Comerciales ("Fiados"), Cobros y Datos de Clientes',
          content:
              'La función de venta a crédito o "fiado" es exclusivamente una herramienta de registro interno. Stockealo no actúa como entidad financiera, cobrador ni garante, y nunca envía mensajes a tus clientes por su cuenta: los recordatorios programados solo te avisan a ti, y cada mensaje de WhatsApp o estado de cuenta lo envías tú.\n'
              'El comerciante declara contar con la autorización de sus clientes para registrar sus datos y enviarles recordatorios, y se compromete a cobrar de forma respetuosa, en horarios razonables y conforme a la ley, sin acoso ni presiones indebidas.',
        ),
        _buildSection(
          number: '7',
          title: 'Stockealo Pro',
          content:
              'Stockealo Pro es una suscripción opcional que suma funciones extra (por ejemplo, catálogos personalizados, cobro de fiados con recordatorios y estado de cuenta, más preguntas a Stocky y, más adelante, tienda en línea). Todo lo que hoy es gratis sigue siendo gratis.\n'
              '\n'
              '• Pago y activación: el pago se hace por los medios que se indican en la app y Pro se activa con un código. Los planes semanales y mensuales no se renuevan solos: cada código suma días.\n'
              '• Alcance: Pro Negocio aplica a un negocio y a su equipo; Pro Global, a los negocios del titular. El plan permanente dura mientras Stockealo preste el servicio.\n'
              '• Precios: pueden cambiar para compras futuras; lo que ya pagaste se respeta.\n'
              '• Reembolsos y retracto: si tienes un problema con tu pago o quieres ejercer el derecho de retracto que te reconozca la ley, escríbenos al correo de soporte y revisaremos tu caso.',
        ),
        _buildSection(
          number: '8',
          title: 'Stocky y las Respuestas Automáticas',
          content:
              'Las respuestas de Stocky, incluidas las generadas con inteligencia artificial, son orientativas y pueden contener errores. No constituyen asesoría contable, legal, tributaria ni financiera. Las preguntas a la IA tienen un límite diario que depende de tu plan.',
        ),
        _buildSection(
          number: '9',
          title: 'Uso por Mayores de Edad',
          content:
              'La plataforma está dirigida a personas mayores de 18 años con plena capacidad legal para el ejercicio de actividades comerciales.',
        ),
        _buildSection(
          number: '10',
          title: 'Propiedad Intelectual',
          content:
              'Todos los derechos de software, diseño, logotipos y código fuente de Stockealo están protegidos por leyes de propiedad intelectual. Los datos de tus productos, clientes e imágenes registradas son y seguirán siendo de tu propiedad exclusiva.',
        ),
        _buildSection(
          number: '11',
          title: 'Disponibilidad y Responsabilidad',
          content:
              'Stockealo se ofrece "tal como está". Hacemos lo posible para que funcione sin interrupciones y para proteger tus datos, pero no garantizamos que el servicio esté libre de fallas. Te recomendamos mantener activo el respaldo. Stockealo no responde por pérdidas comerciales derivadas del uso de la app, de datos mal ingresados o de fallas del dispositivo o de la conexión, salvo en los casos en que la ley no permita esta limitación.',
        ),
        _buildSection(
          number: '12',
          title: 'Modificaciones',
          content:
              'Nos reservamos el derecho de actualizar estos términos en cualquier momento. Te notificaremos dentro de la aplicación ante cualquier cambio sustancial.',
        ),
        _buildSection(
          number: '13',
          title: 'Ley Aplicable',
          content:
              'Estos términos se rigen por las leyes de la República de Colombia, sin perjuicio de los derechos que te reconozcan las leyes de protección al consumidor de tu país.',
        ),
          const SizedBox(height: 30),
        ],
      );
    },
  );
}
}

class _PrivacyPolicyView extends StatelessWidget {
  const _PrivacyPolicyView();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double hPadding = math.max(20.0, (constraints.maxWidth - 780) / 2);
        return ListView(
          padding: EdgeInsets.fromLTRB(hPadding, 20, hPadding, 30),
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
              'En Stockealo creemos que los datos de tu negocio te pertenecen exclusivamente a ti. De manera predeterminada:\n'
              '\n'
              '• Tus productos, costos, ventas, clientes y ganancias se guardan en la memoria local de tu dispositivo.\n'
              '• Tu actividad comercial solo se envía a la nube si activas la sincronización o trabajas con un equipo, y cuando usas funciones que necesitan internet (como preguntarle a Stocky con IA).',
        ),
        _buildSection(
          number: '2',
          title: 'Sincronización en la Nube (Multidispositivo, Equipo y Respaldo)',
          content:
              'Para gestionar tu inventario desde varios dispositivos, trabajar con tu equipo o tener una copia en la nube, Stockealo ofrece sincronización.\n'
              '\n'
              'Está desactivada por defecto y se activa sola cuando tu negocio tiene más de un miembro, porque el equipo necesita compartir los datos. Los datos viajan cifrados (TLS/HTTPS) hacia nuestra infraestructura en la nube. Puedes desactivarla en cualquier momento desde los Ajustes.',
        ),
        _buildSection(
          number: '3',
          title: 'Información que Recopilamos',
          content:
              '• Cuenta: correo electrónico, nombre y, si lo agregas, teléfono. Tu contraseña la gestiona nuestro proveedor de autenticación y se guarda cifrada con un algoritmo de un solo sentido (hash); nosotros nunca la vemos.\n'
              '• Negocio: nombre, país, moneda, logo y color.\n'
              '• Catálogo e inventario: productos, códigos SKU o de barras, costos, precios, existencias y fotos.\n'
              '• Clientes y transacciones: nombres y teléfonos que registra el comerciante, ventas, fiados y abonos.\n'
              '• Equipo: miembros del negocio y el historial de actividad (quién hizo cada movimiento).\n'
              '• Stockealo Pro: el plan activo, sus fechas y los códigos canjeados.\n'
              '• Stocky con IA: las preguntas que haces y cuántas llevas en el día.',
        ),
        _buildSection(
          number: '4',
          title: 'Stocky con Inteligencia Artificial',
          content:
              'Cuando le preguntas a Stocky con IA, tu pregunta y un resumen de los datos de tu negocio necesarios para responderla (por ejemplo, ventas, productos y saldos) se envían a nuestro servidor y a un proveedor de inteligencia artificial (como Groq o Google Gemini) solo para generar la respuesta. No enviamos tu contraseña.',
        ),
        _buildSection(
          number: '5',
          title: 'Datos de tus Clientes',
          content:
              'Los datos de tus clientes los registras tú: frente a ellos, tú eres el responsable de su tratamiento y Stockealo actúa como encargado que los guarda por ti. Úsalos solo para tu negocio, por ejemplo para registrar fiados y enviar recordatorios o estados de cuenta.',
        ),
        _buildSection(
          number: '6',
          title: 'Permisos del Dispositivo y su Uso Estricto',
          content:
              '📷 Cámara: para escanear códigos de barras/QR y tomar fotos de tus productos.\n'
              '\n'
              '🖼️ Galería y archivos: para elegir fotos de productos y para guardar o importar reportes, catálogos y respaldos.\n'
              '\n'
              '🔔 Notificaciones: para avisarte del stock bajo, el resumen del día y los recordatorios de cobro que tú programes. Los avisos programados se mantienen aunque reinicies el celular.\n'
              '\n'
              '⬇️ Instalar actualizaciones: para instalar las nuevas versiones de Stockealo cuando tú lo confirmes.\n'
              '\n'
              '🌐 Conexión de red: para validar tu cuenta, sincronizar con la nube, consultar Stockealo Pro y Stocky con IA, buscar actualizaciones y abrir WhatsApp para compartir tickets, catálogos o recordatorios.',
        ),
        _buildSection(
          number: '7',
          title: 'Proveedores y Transferencia de Datos',
          content:
              'Para prestar el servicio usamos proveedores que tratan datos por nuestra cuenta: Supabase (base de datos en la nube y autenticación), proveedores de inteligencia artificial (para Stocky) y GitHub (descarga de actualizaciones y página web). Sus servidores pueden estar fuera de tu país; al usar estas funciones autorizas esa transferencia, que se hace con medidas de seguridad adecuadas. No vendemos tus datos ni los usamos para publicidad.',
        ),
        _buildSection(
          number: '8',
          title: 'Web, Cookies y Almacenamiento',
          content:
              'La versión web de Stockealo no usa cookies de publicidad ni de analítica. Solo guarda en tu navegador lo necesario para funcionar: tu sesión iniciada y los datos locales de la app. Si lo borras desde tu navegador, tendrás que volver a iniciar sesión y perderás los datos que no estén sincronizados.',
        ),
        _buildSection(
          number: '9',
          title: 'Tus Derechos',
          content:
              'De acuerdo con la Ley 1581 de 2012 de Colombia y las normas de protección de datos de tu país, puedes conocer, actualizar, rectificar y suprimir tus datos, pedir prueba de tu autorización y revocarla. Responderemos las consultas en un máximo de 10 días hábiles y los reclamos en un máximo de 15 días hábiles.',
        ),
        _buildSection(
          number: '10',
          title: 'Mecanismos de Supresión de Datos y Derecho al Olvido',
          content:
              'De acuerdo con las normativas de protección de datos personales y las políticas de Google Play y App Store, puedes eliminar tu información en cualquier momento con dos opciones en Ajustes:\n'
              '\n'
              '• Purgar solo la nube: elimina de forma inmediata e irreversible tus datos en los servidores remotos y deja la app en modo 100 % local, sin perder los datos de tu teléfono.\n'
              '\n'
              '• Eliminación total de cuenta: borra definitivamente tu información en la nube y en tu teléfono.',
        ),
        _buildSection(
          number: '11',
          title: 'Canal Oficial de Contacto y Soporte',
          content:
              'Para cualquier solicitud de privacidad, consulta sobre el tratamiento de tus datos o soporte técnico, escríbenos al correo oficial:\n'
              '\n'
              '📧 byjosealbert@gmail.com',
        ),
        const SizedBox(height: 30),
      ],
    );
  },
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
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: c.accent, borderRadius: BorderRadius.circular(AppRadius.control)),
            child: Icon(icon, color: c.onAccent, size: 26),
          ),
          const SizedBox(width: AppSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.ink)),
                const SizedBox(height: AppSpace.xs),
                Text(subtitle, style: TextStyle(fontSize: 12, color: c.inkMuted)),
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
    final c = context.colors;
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
              color: c.surfaceMuted,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.line),
            ),
            child: Text(number, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: c.inkMuted)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink)),
                const SizedBox(height: 6),
                Text(content, style: TextStyle(fontSize: 13, height: 1.5, color: c.inkMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
