import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/data_events.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/business_clock.dart';
import '../../products/models/product.dart';
import 'branch_repository.dart';

/// «1 unidad», «3 unidades» (0.18.6)
String unitsText(int n) => '$n ${n == 1 ? 'unidad' : 'unidades'}';

/// Estados de un traslado (0.18.5, docs/plan-0.18.5-traslados.md)
abstract final class TransferStatus {
  static const inTransit = 'IN_TRANSIT';
  static const received = 'RECEIVED';
  static const unverified = 'RECEIVED_UNVERIFIED';
  static const cancelled = 'CANCELLED';
}

class TransferLine {
  final String id;
  final String productId;
  final String variantKey;
  final String productName;
  final String? variantLabel;
  final int sent;
  final int? received;

  const TransferLine({
    required this.id,
    required this.productId,
    this.variantKey = '',
    required this.productName,
    this.variantLabel,
    required this.sent,
    this.received,
  });

  String get label => (variantLabel ?? '').trim().isEmpty ? productName : '$productName · $variantLabel';
  int get missing => received == null ? 0 : sent - received!;

  factory TransferLine.fromMap(Map<String, dynamic> m) => TransferLine(
        id: m['id'] as String,
        productId: m['product_id'] as String,
        variantKey: m['variant_key'] as String? ?? '',
        productName: m['product_name'] as String? ?? '',
        variantLabel: m['variant_label'] as String?,
        sent: (m['sent'] as num).toInt(),
        received: (m['received'] as num?)?.toInt(),
      );
}

class StockTransfer {
  final String id;
  final String businessId;

  /// null = la Principal
  final String? fromBranchId;
  final String? toBranchId;
  final String status;
  final String? note;
  final String? receiveNote;
  final String sentByEmail;
  final String? sentByName;
  final DateTime sentAt;
  final String? receivedByName;
  final bool receivedAsLead;
  final DateTime? receivedAt;
  final String? verifiedByName;
  final List<TransferLine> lines;

  const StockTransfer({
    required this.id,
    required this.businessId,
    this.fromBranchId,
    this.toBranchId,
    required this.status,
    this.note,
    this.receiveNote,
    required this.sentByEmail,
    this.sentByName,
    required this.sentAt,
    this.receivedByName,
    this.receivedAsLead = false,
    this.receivedAt,
    this.verifiedByName,
    this.lines = const [],
  });

  bool get inTransit => status == TransferStatus.inTransit;
  bool get unverified => status == TransferStatus.unverified;
  int get units => lines.fold(0, (s, l) => s + l.sent);
  int get receivedUnits => lines.fold(0, (s, l) => s + (l.received ?? 0));
  int get missing => lines.fold(0, (s, l) => s + l.missing);

  factory StockTransfer.fromMap(Map<String, dynamic> m) => StockTransfer(
        id: m['id'] as String,
        businessId: m['business_id'] as String,
        fromBranchId: m['from_branch_id'] as String?,
        toBranchId: m['to_branch_id'] as String?,
        status: m['status'] as String? ?? TransferStatus.inTransit,
        note: m['note'] as String?,
        receiveNote: m['receive_note'] as String?,
        sentByEmail: m['sent_by_email'] as String? ?? '',
        sentByName: m['sent_by_name'] as String?,
        sentAt: DateTime.tryParse('${m['sent_at']}')?.toLocal() ?? DateTime.now(),
        receivedByName: m['received_by_name'] as String?,
        receivedAsLead: m['received_as_lead'] == true,
        receivedAt: DateTime.tryParse('${m['received_at']}')?.toLocal(),
        verifiedByName: m['verified_by_name'] as String?,
        lines: [
          for (final l in (m['stock_transfer_lines'] as List? ?? const []))
            TransferLine.fromMap(Map<String, dynamic>.from(l as Map)),
        ],
      );
}

/// Lo que se va a enviar de un producto
class TransferDraftLine {
  final Product product;
  final String? variantId;
  final String? variantLabel;
  final int available;
  int quantity;

  TransferDraftLine({
    required this.product,
    this.variantId,
    this.variantLabel,
    required this.available,
    this.quantity = 1,
  });

  String get key => variantId == null ? product.id : '${product.id}|$variantId';
  String get label => variantLabel == null ? product.name : '${product.name} · $variantLabel';
  bool get tooMany => quantity > available;
}

/// Traslados entre sedes (0.18.5). El stock se mueve solo en la nube, de una vez
/// (send_transfer, receive_transfer, verify_transfer, cancel_transfer): por eso
/// enviar, recibir y cancelar necesitan conexión. Después la app baja el stock y los
/// lotes que cambiaron.
class TransferRepository {
  TransferRepository._();
  static final TransferRepository instance = TransferRepository._();

  /// Traslados que le llegan a la sede elegida y siguen en camino (para el aviso)
  final incoming = ValueNotifier<int>(0);

  static const needsConnection = 'Para enviar o recibir un traslado necesitas conexión.';

  /// Mensaje claro para lo que responde la nube
  static String friendlyError(Object e) {
    final t = e.toString();
    if (t.contains('not_enough_stock')) return 'No hay unidades suficientes en la sede que envía. Revisa el stock y vuelve a intentarlo.';
    if (t.contains('transfer_not_in_transit')) return 'Ese traslado ya no está en camino: alguien lo recibió o lo canceló.';
    if (t.contains('perm_denied:stockAdjust')) return 'Tu rol no permite enviar traslados. Pídeselo al dueño.';
    if (t.contains('perm_denied:cancel')) return 'Solo quien lo envió, el dueño o un administrador pueden cancelarlo.';
    if (t.contains('perm_denied:verify')) return 'Lo verifica un administrador o el encargado de turno.';
    if (t.contains('wrong_branch')) return 'Ese traslado es de otra sede.';
    if (t.contains('branch_inactive')) return 'Esa sede no está en uso: revisa los cupos de sede en Stockealo Pro.';
    if (t.contains('same_branch')) return 'Elige otra sede de destino.';
    if (t.contains('invalid_received')) return 'No puede llegar más de lo que se envió.';
    if (t.contains('SocketException') || t.contains('Failed host lookup') || t.contains('ClientException')) {
      return needsConnection;
    }
    return t.replaceFirst('Exception: ', '');
  }

  bool get _online => SupabaseService.instance.client?.auth.currentSession != null;

  /// Traslados del negocio, los más nuevos primero. La nube ya filtra: el cajero ve
  /// los de su sede; el dueño y los administradores, todos.
  Future<List<StockTransfer>> list(String businessId) async {
    if (!_online) throw Exception(needsConnection);
    final rows = await SupabaseService.instance.client!
        .from('stock_transfers')
        .select('*, stock_transfer_lines(*)')
        .eq('business_id', businessId)
        .order('sent_at', ascending: false)
        .limit(100);
    final out = [for (final r in rows as List) StockTransfer.fromMap(Map<String, dynamic>.from(r as Map))];
    _countIncoming(out);
    return out;
  }

  /// Actualiza el aviso «Te llegan» sin abrir la pantalla
  Future<void> refreshIncoming(String businessId) async {
    if (!_online || !BranchRepository.instance.hasBranches) {
      incoming.value = 0;
      return;
    }
    try {
      await list(businessId);
    } catch (e) {
      debugPrint('Traslados sin revisar: $e');
    }
  }

  /// Traslados ya avisados en la campana (para no repetir)
  final _notified = <String>{};

  void _countIncoming(List<StockTransfer> all) {
    final here = BranchRepository.active;
    final mine = all.where((t) => t.inTransit && t.toBranchId == here).toList();
    incoming.value = mine.length;
    for (final t in mine) {
      if (!_notified.add(t.id)) continue;
      NotificationService.instance.addNotification(
        title: 'Te llega un traslado',
        message: 'Desde ${BranchRepository.instance.nameOf(t.fromBranchId)}: ${t.units} ${t.units == 1 ? 'unidad' : 'unidades'}. '
            'Recíbelo en Stock › Traslados.',
        type: NotificationType.stockAlert,
        data: {'transfer_id': t.id},
      );
    }
  }

  /// Unidades en camino de cada producto que sale de [fromBranchId]: «3 en camino a Norte»
  static Map<String, List<String>> inTransitFrom(List<StockTransfer> all, String? fromBranchId) {
    final out = <String, List<String>>{};
    final branches = BranchRepository.instance;
    for (final t in all.where((t) => t.inTransit && t.fromBranchId == fromBranchId)) {
      for (final l in t.lines) {
        (out[l.productId] ??= []).add('${l.sent} en camino a ${branches.nameOf(t.toBranchId)}');
      }
    }
    return out;
  }

  Future<void> _beforeWrite() async {
    if (!_online) throw Exception(needsConnection);
    // Que la nube tenga las ventas y ajustes de este celular antes de mover stock
    await SupabaseService.instance.flushPendingSync();
    await SupabaseService.instance.waitForPendingWrites();
  }

  /// Envía [lines] de [fromBranchId] a [toBranchId] (null = Principal). Devuelve el id.
  /// [id]: el mismo en cada reintento de la misma pantalla, para que la nube no lo
  /// envíe dos veces si la respuesta se perdió (Codex, 25 nov).
  Future<String> send({
    required String id,
    required String businessId,
    required String? fromBranchId,
    required String? toBranchId,
    required List<TransferDraftLine> lines,
    String? note,
  }) async {
    final real = lines.where((l) => l.quantity > 0).toList();
    if (real.isEmpty) throw Exception('Agrega al menos un producto.');
    if (fromBranchId == toBranchId) throw Exception('Elige otra sede de destino.');
    final over = real.where((l) => l.tooMany).firstOrNull;
    if (over != null) throw Exception('${over.label}: aquí hay ${over.available}, no se pueden enviar ${over.quantity}.');
    await _beforeWrite();
    final Object? result;
    try {
      result = await SupabaseService.instance.client!.rpc('send_transfer', params: {
        'p_id': id,
        'p_business_id': businessId,
        'p_from': fromBranchId,
        'p_to': toBranchId,
        'p_lines': [
          for (final l in real)
            {
              'product_id': l.product.id,
              'variant_key': l.variantId ?? '',
              'quantity': l.quantity,
              'product_name': l.product.name,
              if (l.variantLabel != null) 'variant_label': l.variantLabel,
            },
        ],
        'p_note': note,
      });
    } catch (e) {
      throw Exception(friendlyError(e));
    }
    var moves = [for (final l in real) (l.product.id, l.variantId ?? '', -l.quantity)];
    // Reintento de uno que ya había llegado: se refleja lo que de verdad salió
    if (result is Map && result['repeated'] == true) {
      final rows = await SupabaseService.instance.client!
          .from('stock_transfer_lines')
          .select('product_id, variant_key, sent')
          .eq('transfer_id', id);
      moves = [
        for (final r in rows as List)
          (r['product_id'] as String, r['variant_key'] as String? ?? '', -(r['sent'] as num).toInt()),
      ];
    }
    await _applyLocal(businessId, fromBranchId, moves);
    return id;
  }

  /// Recibe: [received] = unidades que llegaron por línea (las que falten = lo enviado).
  /// Devuelve true si quedó recibido del todo; false si quedó «por verificar».
  Future<bool> receive(StockTransfer t, {required Map<String, int> received, String? note}) async {
    await _beforeWrite();
    final Map<String, dynamic> result;
    try {
      result = Map<String, dynamic>.from(await SupabaseService.instance.client!.rpc('receive_transfer', params: {
        'p_id': t.id,
        'p_received': received,
        'p_note': note,
      }) as Map);
    } catch (e) {
      throw Exception(friendlyError(e));
    }
    await _applyLocal(t.businessId, t.toBranchId, [
      for (final l in t.lines) (l.productId, l.variantKey, received[l.id] ?? l.sent),
    ]);
    return result['final'] == true;
  }

  Future<void> verify(StockTransfer t) async {
    if (!_online) throw Exception(needsConnection);
    try {
      await SupabaseService.instance.client!.rpc('verify_transfer', params: {'p_id': t.id});
    } catch (e) {
      throw Exception(friendlyError(e));
    }
  }

  Future<void> cancel(StockTransfer t) async {
    await _beforeWrite();
    try {
      await SupabaseService.instance.client!.rpc('cancel_transfer', params: {'p_id': t.id});
    } catch (e) {
      throw Exception(friendlyError(e));
    }
    // Si la sede de origen se cerró, la nube lo devolvió a la Principal
    final origin = BranchRepository.instance.byId(t.fromBranchId);
    final back = t.fromBranchId != null && (origin == null || origin.isClosed) ? null : t.fromBranchId;
    await _applyLocal(t.businessId, back, [for (final l in t.lines) (l.productId, l.variantKey, l.sent)]);
  }

  /// Refleja en el celular lo que la nube ya movió: la Principal por diferencia; las
  /// sedes extra y los lotes se vuelven a bajar.
  Future<void> _applyLocal(String businessId, String? branchId, List<(String, String, int)> moves) async {
    try {
      if (branchId == null) {
        final db = await AppDatabase.instance.database;
        final now = appNow().toIso8601String();
        await db.transaction((txn) async {
          for (final (product, variant, delta) in moves) {
            await txn.rawUpdate('UPDATE products SET stock = stock + ?, updated_at = ? WHERE id = ?', [delta, now, product]);
            if (variant.isNotEmpty) {
              await txn.rawUpdate('UPDATE product_variants SET stock = stock + ?, updated_at = ? WHERE id = ?', [delta, now, variant]);
            }
          }
        });
      }
      await BranchRepository.instance.refresh();
      await _refreshLots(businessId);
    } catch (e) {
      debugPrint('Stock del traslado sin reflejar: $e');
    }
    DataEvents.instance.productsChanged();
  }

  static const _lotColumns = [
    'id', 'business_id', 'product_id', 'code', 'expires_on', 'quantity', 'initial_quantity', 'cost', 'source',
    'purchase_id', 'status', 'created_at', 'updated_at', 'branch_id',
  ];

  Future<void> _refreshLots(String businessId) async {
    final rows = await SupabaseService.instance.client!.from('product_lots').select().eq('business_id', businessId);
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      for (final r in rows as List) {
        final row = Map<String, dynamic>.from(r as Map);
        await txn.insert('product_lots', {for (final k in _lotColumns) k: row[k]}, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  /// Sugerencia de traslado (plan, «Traer de Norte»): productos que en la sede [hereId]
  /// están en su mínimo o por debajo y que otra sede tiene por encima del suyo.
  /// Devuelve, por sede de origen, lo que se podría traer.
  static List<({String? fromBranchId, List<({Product product, int quantity})> items})> suggestions({
    required List<Product> here,
    required Map<String?, List<Product>> others,
  }) {
    final out = <({String? fromBranchId, List<({Product product, int quantity})> items})>[];
    for (final entry in others.entries) {
      final byId = {for (final p in entry.value) p.id: p};
      final items = <({Product product, int quantity})>[];
      for (final p in here) {
        if (p.hasVariants && p.variants.isNotEmpty) continue;
        if (p.stock > p.minStock) continue;
        final there = byId[p.id];
        if (there == null) continue;
        final spare = there.stock - there.minStock;
        if (spare <= 0) continue;
        final need = (p.minStock - p.stock + 1).clamp(1, 1 << 20);
        items.add((product: p, quantity: need < spare ? need : spare));
      }
      if (items.isNotEmpty) out.add((fromBranchId: entry.key, items: items));
    }
    out.sort((a, b) => b.items.length.compareTo(a.items.length));
    return out;
  }
}
