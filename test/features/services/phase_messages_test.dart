import 'package:flutter_test/flutter_test.dart';
import 'package:stockealo/features/business/models/business.dart';
import 'package:stockealo/features/services/data/order_whatsapp.dart';
import 'package:stockealo/features/services/data/service_board.dart';
import 'package:stockealo/features/services/models/phase_messages.dart';
import 'package:stockealo/features/services/models/service_models.dart';

/// Complementos de Servicios (0.12.0): mensajes por fase, espera estimada y demora
void main() {
  final now = DateTime(2026, 11, 10, 9);
  final lavadero = Business(
    id: 'b1',
    userId: 'u1',
    name: 'Lavadero Brillo',
    servicesEnabled: true,
    serviceType: ServiceTemplate.lavadero.code,
    createdAt: now,
  );

  WorkOrder order({String? kind = 'MOTO', String? phone = '3001112233', List<WorkOrderLine>? lines, DateTime? at}) => WorkOrder(
        id: 'o-${at?.minute ?? 0}',
        businessId: 'b1',
        number: '4',
        plate: 'ABC12D',
        vehicleKind: kind,
        customerName: 'Carlos Pérez',
        customerPhone: phone,
        lines: lines ?? const [WorkOrderLine(serviceId: 's1', name: 'Lavado completo', price: 15000, staffIds: ['juan'])],
        createdAt: at ?? now,
        updatedAt: at ?? now,
      );

  group('mensajes por fase', () {
    test('los de Stockealo se arman con las palabras del negocio', () {
      final m = PhaseMessages.defaults(ServiceTemplate.lavadero);
      final text = PhaseMessages.render(
        m.phases[MessagePhase.ready]!.text,
        order: order(),
        template: ServiceTemplate.lavadero,
        businessName: 'Lavadero Brillo',
      );
      expect(text, 'Hola Carlos, tu moto ABC12D ya está lista. Total: \$15.000. ¡Te esperamos en Lavadero Brillo!');
      final carro = PhaseMessages.render(m.phases[MessagePhase.ready]!.text,
          order: order(kind: 'CARRO'), template: ServiceTemplate.lavadero, businessName: 'Brillo');
      expect(carro, contains('tu carro ABC12D ya está listo'));
    });

    test('el de recibido lleva turno, espera y quién atiende', () {
      final m = PhaseMessages.defaults(ServiceTemplate.lavadero);
      final text = PhaseMessages.render(m.phases[MessagePhase.received]!.text,
          order: order(), template: ServiceTemplate.lavadero, businessName: 'Brillo', turn: 3, waitMinutes: 25);
      expect(text, contains('Tu turno es el 3, espera aproximada 25 min'));
      final inProgress = PhaseMessages.render(m.phases[MessagePhase.inProgress]!.text,
          order: order(), template: ServiceTemplate.lavadero, businessName: 'Brillo', staffNames: const {'juan': 'Juan Gómez'});
      expect(inProgress, startsWith('Hola Carlos, Juan ya está atendiendo tu moto ABC12D'));
    });

    test('una barbería no habla de placa ni de moto', () {
      final m = PhaseMessages.defaults(ServiceTemplate.barberia);
      for (final p in MessagePhase.values) {
        final text = PhaseMessages.render(m.phases[p]!.text,
            order: order(kind: null).copyWith(plate: ''), template: ServiceTemplate.barberia, businessName: 'Barbería Max');
        expect(text.toLowerCase(), isNot(contains('moto')), reason: p.label);
        expect(text, isNot(contains('{')), reason: 'variables sin reemplazar en ${p.label}');
      }
    });

    test('lo editado se guarda y una fase apagada no se ofrece', () {
      final edited = PhaseMessages.defaults(ServiceTemplate.lavadero)
          .copyWith(MessagePhase.ready, const PhaseMessage(enabled: true, text: '{cliente}: lista tu {unidad}'))
          .copyWith(MessagePhase.received, const PhaseMessage(enabled: false, text: 'x'));
      final business = lavadero.copyWith(serviceMessages: edited.encode());
      expect(OrderWhatsApp.phaseText(MessagePhase.ready, order(), business), 'Carlos: lista tu moto');
      expect(OrderWhatsApp.phaseText(MessagePhase.received, order(), business), isNull);
      // Un JSON dañado vuelve a los textos de Stockealo
      expect(PhaseMessages.of('{roto', ServiceTemplate.lavadero).phases[MessagePhase.ready]!.enabled, isTrue);
    });
  });

  group('espera estimada y demora', () {
    final juan = StaffMember(id: 'juan', businessId: 'b1', name: 'Juan', createdAt: now, updatedAt: now);
    final pedro = StaffMember(id: 'pedro', businessId: 'b1', name: 'Pedro', createdAt: now, updatedAt: now);
    final lavado = ShopService(id: 's1', businessId: 'b1', name: 'Lavado', price: 10000, durationMin: 30, createdAt: now, updatedAt: now);
    StaffAttendance came(String id) =>
        StaffAttendance(id: 'a-$id', businessId: 'b1', staffId: id, day: '2026-11-10', status: StaffAttendance.arrived, updatedAt: now);

    test('suma lo que falta y lo que hay antes en la cola, repartido entre quienes trabajan', () {
      // Juan lleva 10 min en un lavado de 30; esperan dos lavados más
      final working = order(lines: [
        WorkOrderLine(serviceId: 's1', name: 'Lavado', price: 10000, staffIds: const ['juan'],
            status: WorkOrderLine.inProgress, startedAt: now.subtract(const Duration(minutes: 10))),
      ], at: now.subtract(const Duration(minutes: 20)));
      final first = order(lines: const [WorkOrderLine(serviceId: 's1', name: 'Lavado', price: 10000)], at: now.subtract(const Duration(minutes: 5)));
      final second = order(lines: const [WorkOrderLine(serviceId: 's1', name: 'Lavado', price: 10000)], at: now);
      final oneWorker = ServiceBoard(orders: [working, first, second], staff: [juan], services: [lavado], attendance: [came('juan')]);
      expect(oneWorker.estimatedWait(first, now: now), 20);
      expect(oneWorker.estimatedWait(second, now: now), 50);
      final twoWorkers = ServiceBoard(orders: [working, first, second], staff: [juan, pedro], services: [lavado], attendance: [came('juan'), came('pedro')]);
      expect(twoWorkers.estimatedWait(second, now: now), 25);
      // Nadie vino: no se puede estimar
      expect(ServiceBoard(orders: [first], staff: [juan], services: [lavado], attendance: const []).estimatedWait(first), isNull);
    });

    test('un servicio que pasó su duración se marca como demorado', () {
      final board = ServiceBoard(orders: const [], staff: [juan], services: [lavado], attendance: [came('juan')]);
      final late = WorkOrderLine(serviceId: 's1', name: 'Lavado', price: 10000, status: WorkOrderLine.inProgress,
          startedAt: now.subtract(const Duration(minutes: 42)));
      final onTime = WorkOrderLine(serviceId: 's1', name: 'Lavado', price: 10000, status: WorkOrderLine.inProgress,
          startedAt: now.subtract(const Duration(minutes: 12)));
      expect(board.delayOf(late, now), 12);
      expect(board.delayOf(onTime, now), isNull);
    });
  });
}
