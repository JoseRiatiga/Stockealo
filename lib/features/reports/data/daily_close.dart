import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../business/models/business.dart';
import '../../dashboard/data/dashboard_repository.dart';
import '../../sales/models/payment_method.dart';
import '../../../core/utils/business_clock.dart';

/// Cierre del día por WhatsApp (0.15.0, punto 19): a mano para todos; con Pro, el aviso
/// del resumen de la noche lo deja listo para enviar con un toque.
abstract final class DailyClose {
  /// El texto del cierre: ventas, ganancia, cuánto entró por cada medio y qué reponer
  static Future<String> text(Business business, {DateTime? day}) async {
    final d = day ?? appNow();
    String money(num v) => CurrencyFormatter.formatIn(v, business.currency);
    final summary = await DashboardRepository.instance.getDashboardSummary(business.id, period: 'today');
    final count = (summary['periodCount'] as num?)?.toInt() ?? 0;
    final total = (summary['periodTotal'] as num?)?.toDouble() ?? 0;
    final profit = (summary['periodProfit'] as num?)?.toDouble() ?? 0;
    final restock = ((summary['outOfStock'] as num?)?.toInt() ?? 0) + ((summary['lowStock'] as num?)?.toInt() ?? 0);

    // Por medio de pago (sin las anuladas)
    final db = await AppDatabase.instance.database;
    final prefix = DateFormat('yyyy-MM-dd').format(d);
    final rows = await db.rawQuery(
      'SELECT payment_method AS m, SUM(total) AS t FROM sales_here '
      'WHERE business_id = ? AND date LIKE ? GROUP BY payment_method ORDER BY t DESC',
      [business.id, '$prefix%'],
    );

    final lines = <String>[
      '*Cierre del día · ${business.name}*',
      toBeginningOfSentenceCase(DateFormat("EEEE d 'de' MMMM", 'es_CO').format(d)),
      '',
      if (count == 0)
        'Hoy no hubo ventas.'
      else ...[
        'Ventas: $count por ${money(total)}',
        'Ganancia: ${money(profit)}',
        for (final r in rows)
          if (((r['t'] as num?) ?? 0) > 0) '• ${PaymentMethod.label(r['m'] as String?)}: ${money((r['t'] as num).toDouble())}',
      ],
      if (restock > 0) '',
      if (restock > 0) 'Por reponer: $restock ${restock == 1 ? 'producto' : 'productos'}',
      '',
      '_Enviado desde Stockealo_',
    ];
    return lines.join('\n');
  }

  /// Abre WhatsApp con el cierre escrito; la persona elige a quién mandarlo
  static Future<bool> send(Business business) async {
    final message = await text(business);
    return launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(message)}'), mode: LaunchMode.externalApplication);
  }
}
