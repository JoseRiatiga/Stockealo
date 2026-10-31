import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/features/stocky/data/stocky_assistant_service.dart';

void main() {
  final stocky = StockyAssistantService.instance;
  StockyIntent intentOf(String prompt) => stocky.classifyIntent(stocky.normalizeQuery(prompt));

  group('normalizeQuery', () {
    test('quita tildes, signos y espacios de más', () {
      expect(stocky.normalizeQuery('¿Qué es la regla 80/20  en mi negocio?'), 'que es la regla 8020 en mi negocio');
    });

    test('conserva la ñ como n en vez de borrarla', () {
      expect(stocky.normalizeQuery('¿Cuánto vendí mañana?'), 'cuanto vendi manana');
    });
  });

  group('classifyIntent', () {
    test('la regla 80/20 va a consejos, no a la respuesta por defecto', () {
      expect(intentOf('¿Qué es la regla 80/20 en mi negocio?'), StockyIntent.advice);
      expect(intentOf('Explícame la ley de Pareto'), StockyIntent.advice);
    });

    test('busca palabras, no pedazos de palabras', () {
      // "multiplicar" contiene "tip" y "laptop" contiene "top"
      expect(intentOf('cómo multiplicar mis ganancias'), isNot(StockyIntent.advice));
      expect(intentOf('tengo un laptop nuevo'), isNot(StockyIntent.topProducts));
    });

    test('"cómo van las ventas" da cifras y no un tutorial', () {
      expect(intentOf('¿Cómo van las ventas hoy?'), StockyIntent.sales);
      expect(intentOf('cómo van las ventas'), StockyIntent.sales);
    });

    test('"cómo registro una venta" sigue siendo un tutorial', () {
      expect(intentOf('¿Cómo registro una venta?'), StockyIntent.howTo);
    });

    test('"cómo vender más" es un consejo, no el tutorial de ventas', () {
      expect(intentOf('¿Cómo puedo vender más?'), StockyIntent.advice);
    });

    test('ventas de otros periodos', () {
      expect(intentOf('¿Cuánto vendí ayer?'), StockyIntent.sales);
      expect(intentOf('ventas de esta semana'), StockyIntent.sales);
      expect(intentOf('¿cuánto facturé el mes pasado?'), StockyIntent.sales);
    });

    test('el stock de un producto concreto se busca antes que el resumen de stock', () {
      expect(intentOf('¿Cuánto stock hay de arroz?'), StockyIntent.productStock);
      expect(intentOf('¿qué productos están agotados?'), StockyIntent.lowStock);
    });

    test('fiados, ganancias y más vendidos', () {
      expect(intentOf('¿Quién me debe?'), StockyIntent.debts);
      expect(intentOf('¿Cuánto gané?'), StockyIntent.profit);
      expect(intentOf('¿Cuáles son los más vendidos?'), StockyIntent.topProducts);
    });
  });

  group('salesPeriodFor', () {
    // Jueves 30 de octubre de 2026
    final now = DateTime(2026, 10, 30, 15, 20);
    SalesPeriod? periodOf(String prompt) => stocky.salesPeriodFor(stocky.normalizeQuery(prompt), now: now);

    test('sin periodo es hoy', () {
      expect(periodOf('¿cuánto vendí hoy?'), isNull);
    });

    test('ayer cubre el día completo anterior', () {
      final period = periodOf('¿cuánto vendí ayer?')!;
      expect(period.from, DateTime(2026, 10, 29));
      expect(period.to, DateTime(2026, 10, 30));
    });

    test('esta semana empieza el lunes e incluye hoy', () {
      final period = periodOf('ventas de esta semana')!;
      expect(period.from, DateTime(2026, 10, 26));
      expect(period.to, DateTime(2026, 10, 31));
    });

    test('la semana pasada va de lunes a lunes', () {
      final period = periodOf('ventas de la semana pasada')!;
      expect(period.from, DateTime(2026, 10, 19));
      expect(period.to, DateTime(2026, 10, 26));
    });

    test('el mes pasado es septiembre completo', () {
      final period = periodOf('¿cuánto facturé el mes pasado?')!;
      expect(period.from, DateTime(2026, 9));
      expect(period.to, DateTime(2026, 10));
    });

    test('este mes empieza el día 1', () {
      final period = periodOf('ventas de este mes')!;
      expect(period.from, DateTime(2026, 10));
      expect(period.to, DateTime(2026, 10, 31));
    });
  });
}
