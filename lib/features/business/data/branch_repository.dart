import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/app_database.dart';
import '../../../core/services/data_events.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/utils/business_clock.dart';
import '../models/ticket_info.dart';
import '../../products/models/product.dart';
import '../../products/models/product_variant.dart';

/// Una sede extra del negocio (0.18.0). La sede Principal no es una fila: es lo de
/// siempre (branch_id vacío) y su nombre va en businesses.main_branch_name.
class Branch {
  final String id;
  final String businessId;
  final String name;
  final String? address;
  final String? phone;
  final String status;

  /// Abierta y dentro del límite de cupos del plan: se puede vender en ella
  final bool usable;
  final DateTime createdAt;
  final DateTime? closedAt;

  const Branch({
    required this.id,
    required this.businessId,
    required this.name,
    this.address,
    this.phone,
    this.status = 'ACTIVE',
    this.usable = true,
    required this.createdAt,
    this.closedAt,
  });

  bool get isClosed => status == 'CLOSED';

  /// Abierta pero sin cupo (el plan bajó): se ve y se descarga, no se vende
  bool get isInactive => !isClosed && !usable;

  factory Branch.fromMap(Map<String, dynamic> m) => Branch(
        id: m['id'] as String,
        businessId: m['business_id'] as String,
        name: m['name'] as String? ?? '',
        address: m['address'] as String?,
        phone: m['phone'] as String?,
        status: m['status'] as String? ?? 'ACTIVE',
        usable: m['usable'] == 1 || m['usable'] == true,
        createdAt: DateTime.tryParse('${m['created_at']}')?.toLocal() ?? DateTime.now(),
        closedAt: DateTime.tryParse('${m['closed_at']}')?.toLocal(),
      );

  Map<String, Object?> toLocal() => {
        'id': id,
        'business_id': businessId,
        'name': name,
        'address': address,
        'phone': phone,
        'status': status,
        'usable': usable ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'closed_at': closedAt?.toIso8601String(),
      };
}

/// Sedes del negocio (0.18.0, docs/plan-sedes.md).
///
/// Diseño «la Principal se queda donde está»: el stock, las ventas y las cajas de
/// siempre son de la Principal. Una sede extra guarda su stock en branch_stock y sus
/// ventas y cajas con branch_id. [current] es la sede elegida (null = Principal).
class BranchRepository extends ChangeNotifier {
  BranchRepository._();
  static final BranchRepository instance = BranchRepository._();

  /// Nombre por defecto de la sede de siempre
  static const mainDefaultName = 'Principal';

  String? _businessId;
  List<Branch> _branches = const [];
  String? _mainName;
  int _allowance = 0;

  /// Sede elegida (null = Principal)
  final current = ValueNotifier<String?>(null);

  /// La persona trabaja en una sede fija (cajero de una sede): no puede cambiar
  String? _fixedBranch;
  bool _canSwitch = true;

  /// Sede elegida para leer y escribir (null = Principal)
  static String? get active => instance.current.value;

  /// «Todas las sedes» en Reportes e Inicio (dueño y administradores; solo para ver)
  final viewAll = ValueNotifier<bool>(false);

  /// Filtro SQL de la sede para consultas de ventas, cajas y entradas. Va al final del
  /// WHERE, con [scopeArgs] al final de los argumentos. En un negocio sin sedes
  /// («branch_id IS NULL» en todo) no cambia nada.
  static String scope([String column = 'branch_id']) =>
      instance.viewAll.value ? '' : (active == null ? ' AND $column IS NULL' : ' AND $column = ?');
  static List<Object?> scopeArgs() => instance.viewAll.value || active == null ? const [] : [active];

  void setViewAll(bool value) {
    if (viewAll.value == value || (value && !_canSwitch)) return;
    viewAll.value = value;
    _saveScope();
    notifyListeners();
    DataEvents.instance.salesChanged();
  }

  /// La sede elegida, para la vista «sales_here» de la base del celular
  Future<void> _saveScope() async {
    try {
      final db = await AppDatabase.instance.database;
      await db.update('app_scope', {'branch_id': current.value, 'all_branches': viewAll.value ? 1 : 0}, where: 'id = 1');
    } catch (e) {
      debugPrint('Sede elegida sin guardar: $e');
    }
  }

  List<Branch> get branches => _branches;
  List<Branch> get openBranches => _branches.where((b) => !b.isClosed).toList();
  String get mainName => (_mainName ?? '').trim().isEmpty ? mainDefaultName : _mainName!.trim();
  int get allowance => _allowance;

  /// Cupos libres para abrir una sede
  int get freeSlots => (_allowance - openBranches.length).clamp(0, 1 << 20);

  /// El negocio tiene más de una sede (abierta o cerrada con historial)
  bool get hasBranches => _branches.isNotEmpty;
  /// Con sedes cerradas también: así «Todas las sedes» deja ver su historial (ventas y
  /// cierres de caja), que con solo la Principal no se veía (recorrido del 24 nov)
  bool get canSwitch => _canSwitch && _branches.isNotEmpty;

  Branch? byId(String? id) => id == null ? null : _branches.where((b) => b.id == id).firstOrNull;

  /// «Centro», «Norte»…
  String nameOf(String? branchId) => branchId == null ? mainName : (byId(branchId)?.name ?? 'Sede');

  /// La sede para el tiquete (0.18.1): null si el negocio no tiene sedes abiertas y el
  /// tiquete es de la Principal, para que el recibo de un solo local quede como siempre
  TicketBranch? ticketBranch(String? branchId) {
    if (branchId == null && openBranches.isEmpty) return null;
    final b = byId(branchId);
    return TicketBranch(nameOf(branchId), address: b?.address, phone: b?.phone);
  }

    /// Se puede vender y abrir caja en la sede elegida
  bool get activeUsable => active == null || (byId(active)?.usable ?? false) && !(byId(active)?.isClosed ?? true);

  static String _choiceKey(String businessId) => 'active_branch_$businessId';

  /// Prepara las sedes del negocio activo. [memberBranchId]: la sede de la persona;
  /// si no es dueño ni administrador, trabaja solo en esa.
  Future<void> use(String businessId, {required String role, String? memberBranchId}) async {
    _businessId = businessId;
    final db = await AppDatabase.instance.database;
    final rows = await db.query('branches', where: 'business_id = ?', whereArgs: [businessId], orderBy: 'created_at');
    _branches = rows.map(Branch.fromMap).toList();
    final biz = await db.query('businesses', columns: ['main_branch_name'], where: 'id = ?', whereArgs: [businessId], limit: 1);
    _mainName = biz.isEmpty ? null : biz.first['main_branch_name'] as String?;
    final manager = role == 'OWNER' || role == 'ADMIN';
    _canSwitch = manager;
    _fixedBranch = manager ? null : memberBranchId;
    String? choice;
    if (manager) {
      choice = await AppDatabase.instance.getSetting(_choiceKey(businessId));
      if (choice != null && (byId(choice)?.isClosed ?? true)) choice = null;
    } else {
      choice = _fixedBranch;
    }
    if (current.value != choice) current.value = choice;
    if (!manager) viewAll.value = false;
    await _saveScope();
    notifyListeners();
  }

  /// Cambia de sede (dueño y administradores). El carrito y lo de la sede anterior no se mezclan.
  Future<void> choose(String? branchId) async {
    if (!_canSwitch || _businessId == null) return;
    if (branchId != null && (byId(branchId)?.isClosed ?? true)) return;
    await AppDatabase.instance.setSetting(_choiceKey(_businessId!), branchId);
    current.value = branchId;
    await _saveScope();
    notifyListeners();
    DataEvents.instance.productsChanged();
    DataEvents.instance.salesChanged();
    DataEvents.instance.cashChanged();
  }

  /// Baja las sedes y el stock de las sedes extra desde la nube
  Future<void> refresh() async {
    final businessId = _businessId;
    final client = SupabaseService.instance.client;
    if (businessId == null || client?.auth.currentSession == null) return;
    try {
      final data = Map<String, dynamic>.from(await client!.rpc('my_branches', params: {'p_business_id': businessId}) as Map);
      _allowance = (data['allowance'] as num?)?.toInt() ?? 0;
      final list = [
        for (final b in (data['branches'] as List? ?? const []))
          Branch.fromMap({...Map<String, dynamic>.from(b as Map), 'business_id': businessId}),
      ];
      final stock = list.isEmpty ? const <dynamic>[] : await client.from('branch_stock').select().eq('business_id', businessId);
      final db = await AppDatabase.instance.database;
      await db.transaction((txn) async {
        await txn.delete('branches', where: 'business_id = ?', whereArgs: [businessId]);
        for (final b in list) {
          await txn.insert('branches', b.toLocal(), conflictAlgorithm: ConflictAlgorithm.replace);
        }
        // El stock de las sedes extra lo manda la nube (se mueve por diferencia)
        await txn.delete('branch_stock', where: 'business_id = ?', whereArgs: [businessId]);
        for (final r in stock) {
          final m = Map<String, dynamic>.from(r as Map);
          await txn.insert('branch_stock', {
            'branch_id': m['branch_id'],
            'business_id': businessId,
            'product_id': m['product_id'],
            'variant_key': m['variant_key'] ?? '',
            'stock': (m['stock'] as num?)?.toInt() ?? 0,
            'min_stock': (m['min_stock'] as num?)?.toInt(),
            'updated_at': m['updated_at'],
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        await txn.update('businesses', {'main_branch_name': data['main_name']}, where: 'id = ?', whereArgs: [businessId]);
      });
      _branches = list;
      _mainName = data['main_name'] as String?;
      if (current.value != null && (byId(current.value)?.isClosed ?? true)) current.value = _fixedBranch;
      notifyListeners();
    } catch (e) {
      debugPrint('Sedes sin bajar: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Abrir, renombrar, cerrar y reabrir (solo el dueño, con conexión: usa un cupo)

  Future<void> create({required String name, String? address, String? phone}) async {
    final client = SupabaseService.instance.client;
    if (client?.auth.currentSession == null || _businessId == null) throw Exception('Para abrir una sede necesitas conexión.');
    try {
      await client!.from('branches').insert({
        'business_id': _businessId,
        'name': name.trim(),
        if ((address ?? '').trim().isNotEmpty) 'address': address!.trim(),
        if ((phone ?? '').trim().isNotEmpty) 'phone': phone!.trim(),
      });
    } catch (e) {
      throw Exception(friendlyError(e));
    }
    await refresh();
  }

  Future<void> update(Branch b, {required String name, String? address, String? phone}) async {
    final client = SupabaseService.instance.client;
    if (client?.auth.currentSession == null) throw Exception('Para cambiar la sede necesitas conexión.');
    try {
      await client!.from('branches').update({'name': name.trim(), 'address': address?.trim(), 'phone': phone?.trim()}).eq('id', b.id);
    } catch (e) {
      throw Exception(friendlyError(e));
    }
    await refresh();
  }

  Future<void> renameMain(String name) async {
    final businessId = _businessId;
    final client = SupabaseService.instance.client;
    if (businessId == null || client?.auth.currentSession == null) throw Exception('Para cambiar el nombre necesitas conexión.');
    await client!.from('businesses').update({'main_branch_name': name.trim()}).eq('id', businessId);
    await refresh();
  }

  /// Cierra una sede: su mercancía, sus lotes y sus personas pasan a [target]
  /// (null = Principal). Nada se borra.
  Future<void> close(Branch b, {String? target}) async {
    final client = SupabaseService.instance.client;
    if (client?.auth.currentSession == null) throw Exception('Para cerrar una sede necesitas conexión.');
    if (await openCashSession(b.id)) throw Exception('Primero cierra la caja de ${b.name}.');
    await SupabaseService.instance.waitForPendingWrites();
    try {
      await client!.rpc('close_branch', params: {'p_branch_id': b.id, 'p_target_branch_id': target});
    } catch (e) {
      throw Exception(friendlyError(e));
    }
    // Lo que pasó a otra sede llega con la próxima descarga; aquí se refleja de una vez
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      final rows = await txn.query('branch_stock', where: 'branch_id = ? AND stock <> 0', whereArgs: [b.id]);
      for (final r in rows) {
        await _addLocal(txn, businessId: b.businessId, branchId: target, productId: r['product_id'] as String,
            variantKey: r['variant_key'] as String, delta: (r['stock'] as num).toInt());
      }
      await txn.update('branch_stock', {'stock': 0}, where: 'branch_id = ?', whereArgs: [b.id]);
      await txn.update('product_lots', {'branch_id': target}, where: "branch_id = ? AND status = 'ACTIVE'", whereArgs: [b.id]);
      await txn.update('business_members', {'branch_id': target}, where: 'branch_id = ?', whereArgs: [b.id]);
    });
    if (current.value == b.id) await choose(target);
    await refresh();
    DataEvents.instance.productsChanged();
  }

  Future<void> reopen(Branch b) async {
    final client = SupabaseService.instance.client;
    if (client?.auth.currentSession == null) throw Exception('Para reabrir una sede necesitas conexión.');
    try {
      await client!.from('branches').update({'status': 'ACTIVE'}).eq('id', b.id);
    } catch (e) {
      throw Exception(friendlyError(e));
    }
    await refresh();
  }

  /// La sede tiene una caja abierta en este equipo
  static Future<bool> openCashSession(String? branchId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS n FROM cash_sessions WHERE closed_at IS NULL AND ${branchId == null ? 'branch_id IS NULL' : 'branch_id = ?'}',
      [if (branchId != null) branchId],
    );
    return ((rows.first['n'] as num?) ?? 0) > 0;
  }

  /// Mensaje claro para lo que responde la nube
  static String friendlyError(Object e) {
    final t = e.toString();
    if (t.contains('branch_limit')) return 'No tienes cupos libres para otra sede. Pide uno más en Stockealo Pro.';
    if (t.contains('owner_only')) return 'Solo el dueño del negocio puede abrir o cerrar sedes.';
    if (t.contains('cash_open')) return 'Esa sede tiene la caja abierta: ciérrala primero.';
    if (t.contains('branch_closed')) return 'Esa sede ya está cerrada.';
    return t.replaceFirst('Exception: ', '');
  }

  // ---------------------------------------------------------------------------
  // Stock de las sedes extra (la Principal sigue con products.stock y product_variants.stock)

  /// Sede de escritura: la elegida, salvo que se indique otra (anular o devolver va
  /// a la sede de la venta)
  static Future<void> addStock(
    DatabaseExecutor db, {
    required String businessId,
    required String branchId,
    required String productId,
    String? variantId,
    required int delta,
  }) async {
    await _addLocal(db, businessId: businessId, branchId: branchId, productId: productId, variantKey: variantId ?? '', delta: delta);
  }

  static Future<void> _addLocal(
    DatabaseExecutor db, {
    required String businessId,
    required String? branchId,
    required String productId,
    required String variantKey,
    required int delta,
  }) async {
    final now = appNow().toIso8601String();
    if (branchId == null) {
      // A la Principal (solo al cerrar una sede): como siempre
      await db.rawUpdate('UPDATE products SET stock = stock + ?, updated_at = ? WHERE id = ?', [delta, now, productId]);
      if (variantKey.isNotEmpty) {
        await db.rawUpdate('UPDATE product_variants SET stock = stock + ?, updated_at = ? WHERE id = ?', [delta, now, variantKey]);
      }
      return;
    }
    await db.rawInsert(
      'INSERT INTO branch_stock (branch_id, business_id, product_id, variant_key, stock, updated_at) VALUES (?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(branch_id, product_id, variant_key) DO UPDATE SET stock = stock + excluded.stock, updated_at = excluded.updated_at',
      [branchId, businessId, productId, variantKey, delta, now],
    );
  }

  /// Fija el stock de un producto o variante en una sede extra
  static Future<void> setStock(
    DatabaseExecutor db, {
    required String businessId,
    required String branchId,
    required String productId,
    String? variantId,
    required int stock,
    int? minStock,
  }) async {
    final now = appNow().toIso8601String();
    await db.rawInsert(
      'INSERT INTO branch_stock (branch_id, business_id, product_id, variant_key, stock, min_stock, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(branch_id, product_id, variant_key) DO UPDATE SET stock = excluded.stock, '
      'min_stock = COALESCE(excluded.min_stock, min_stock), updated_at = excluded.updated_at',
      [branchId, businessId, productId, variantId ?? '', stock < 0 ? 0 : stock, minStock, now],
    );
  }

  /// Cambia solo el stock mínimo de un producto en una sede extra (Editar producto)
  static Future<void> setStockMin(
    DatabaseExecutor db, {
    required String businessId,
    required String branchId,
    required String productId,
    required int minStock,
  }) async {
    await db.rawInsert(
      'INSERT INTO branch_stock (branch_id, business_id, product_id, variant_key, stock, min_stock, updated_at) VALUES (?, ?, ?, \'\', 0, ?, ?) '
      'ON CONFLICT(branch_id, product_id, variant_key) DO UPDATE SET min_stock = excluded.min_stock, updated_at = excluded.updated_at',
      [branchId, businessId, productId, minStock, appNow().toIso8601String()],
    );
    final row = await db.query('branch_stock',
        columns: ['stock'], where: "branch_id = ? AND product_id = ? AND variant_key = ''", whereArgs: [branchId, productId], limit: 1);
    SupabaseService.instance.setBranchStockInCloud(branchId, productId, null, (row.firstOrNull?['stock'] as num?)?.toInt() ?? 0,
        minStock: minStock);
  }

  /// Stock de cada producto (y variante) en una sede extra: productId -> (total, mínimo, variantes)
  static Future<Map<String, ({int stock, int? minStock, Map<String, int> variants})>> stockIn(String branchId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('branch_stock', where: 'branch_id = ?', whereArgs: [branchId]);
    final out = <String, ({int stock, int? minStock, Map<String, int> variants})>{};
    for (final r in rows) {
      final product = r['product_id'] as String;
      final key = r['variant_key'] as String? ?? '';
      final qty = (r['stock'] as num?)?.toInt() ?? 0;
      final prev = out[product] ?? (stock: 0, minStock: null, variants: <String, int>{});
      if (key.isEmpty) {
        out[product] = (stock: prev.variants.isEmpty ? qty : prev.stock, minStock: (r['min_stock'] as num?)?.toInt(), variants: prev.variants);
      } else {
        final variants = {...prev.variants, key: qty};
        // Con tallas o colores, el total de la sede es la suma de sus variantes
        out[product] = (stock: variants.values.fold(0, (s, v) => s + v), minStock: prev.minStock, variants: variants);
      }
    }
    return out;
  }

  /// «Principal 4 · Norte 14» (0.18.1): las unidades de cada producto en las otras sedes
  /// abiertas, para la lista de Stock del dueño y los administradores. Solo los
  /// productos con unidades en otra sede; vacío si el negocio no tiene sedes abiertas.
  Future<Map<String, String>> stockElsewhere(String businessId) async {
    if (!_canSwitch || openBranches.isEmpty) return const {};
    final db = await AppDatabase.instance.database;
    final parts = <String, List<String>>{};
    void add(String product, String where, int qty) {
      if (qty != 0) (parts[product] ??= []).add('$where $qty');
    }

    if (active != null) {
      final rows = await db.query('products', columns: ['id', 'stock'], where: 'business_id = ?', whereArgs: [businessId]);
      for (final r in rows) {
        add(r['id'] as String, mainName, (r['stock'] as num?)?.toInt() ?? 0);
      }
    }
    for (final b in openBranches) {
      if (b.id == active) continue;
      for (final e in (await stockIn(b.id)).entries) {
        add(e.key, b.name, e.value.stock);
      }
    }
    return {for (final e in parts.entries) e.key: e.value.join(' · ')};
  }

    /// Los productos con el stock de la sede [branchId] en vez del de la Principal.
  /// Sin sede (Principal) devuelve la lista tal cual.
  static Future<List<Product>> withBranchStock(List<Product> products, String? branchId) async {
    if (branchId == null || products.isEmpty) return products;
    final stock = await stockIn(branchId);
    return [
      for (final p in products)
        () {
          final s = stock[p.id];
          final variants = [
            for (final ProductVariant v in p.variants) v.copyWith(stock: s?.variants[v.id] ?? 0),
          ];
          return p.copyWith(
            stock: p.hasVariants && p.variants.isNotEmpty ? variants.fold<int>(0, (t, v) => t + v.stock) : (s?.stock ?? 0),
            minStock: s?.minStock ?? p.minStock,
            variants: variants,
          );
        }(),
    ];
  }

  /// Copia para «Descargar todos mis datos»
  static Future<String> exportJson(String businessId) async {
    final db = await AppDatabase.instance.database;
    return jsonEncode({
      'branches': await db.query('branches', where: 'business_id = ?', whereArgs: [businessId]),
      'branch_stock': await db.query('branch_stock', where: 'business_id = ?', whereArgs: [businessId]),
    });
  }
}
