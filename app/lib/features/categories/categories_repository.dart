import 'dart:typed_data';

import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:uuid/uuid.dart';

import '../../core/crypto/cipher.dart';
import '../../core/db/database.dart';

class CategoriesRepository {
  final AppDatabase _db;
  final DiaryCipher _cipher = DiaryCipher();
  final _uuid = const Uuid();
  CategoriesRepository(this._db);

  // Фиксированный namespace для UUIDv5, чтобы дефолтные категории на всех
  // устройствах имели одинаковые id и не плодили дубли при синхронизации.
  static const _namespace = '6f7b1e2c-9a4d-4f8e-b3a5-1c2d3e4f5a6b';

  String _deterministicId(String name) =>
      const Uuid().v5(_namespace, 'default-category:$name');

  static const _kDeviceIdKey = 'device_id';

  Future<String> _deviceId() async {
    var id = await _db.getMeta(_kDeviceIdKey);
    if (id == null) {
      id = _uuid.v4();
      await _db.setMeta(_kDeviceIdKey, id);
    }
    return id;
  }

  static const defaultCategories = <({String name, int color})>[
    (name: 'Личное', color: 0xFF8B7CB6),
    (name: 'Работа', color: 0xFF4F8FB8),
    (name: 'Здоровье', color: 0xFF5FA37A),
    (name: 'Идеи', color: 0xFFD4A75C),
    (name: 'Отношения', color: 0xFFC57A8E),
  ];

  Future<List<LocalCategory>> list() => _db.listCategories();

  Future<void> ensureDefaults({SecretKey? masterKey}) async {
    final existing = await _db.listCategories();
    final existingNames = existing.map((c) => c.name).toSet();
    for (var i = 0; i < defaultCategories.length; i++) {
      final c = defaultCategories[i];
      // Не пересоздавать, если категория с таким именем уже есть.
      if (existingNames.contains(c.name)) continue;
      await _save(
        id: _deterministicId(c.name),
        name: c.name,
        color: c.color,
        sortOrder: i,
        masterKey: masterKey,
      );
    }
  }

  /// Дедупликация: для каждого имени оставляем самую старую категорию,
  /// записи с удалённых дублей перенацеливаем на canonical.
  /// Вызывать на старте приложения после загрузки профиля.
  Future<void> cleanupDuplicates() async {
    final all = await _db.listCategories();
    final byName = <String, List<LocalCategory>>{};
    for (final c in all) {
      byName.putIfAbsent(c.name, () => []).add(c);
    }
    for (final group in byName.values) {
      if (group.length <= 1) continue;
      group.sort((a, b) {
        // Канон: тот, у кого id совпадает с детерминированным (если такой есть),
        // иначе самый старый по updated_at.
        final detId = _deterministicId(a.name);
        final aIsDet = a.id == detId;
        final bIsDet = b.id == detId;
        if (aIsDet != bIsDet) return aIsDet ? -1 : 1;
        final ua = a.updatedAt;
        final ub = b.updatedAt;
        if (ua == null && ub == null) return a.id.compareTo(b.id);
        if (ua == null) return 1;
        if (ub == null) return -1;
        return ua.compareTo(ub);
      });
      final canonical = group.first;
      for (final dup in group.skip(1)) {
        await _db.reassignEntriesCategory(dup.id, canonical.id);
        await _db.deleteCategory(dup.id);
      }
    }
  }

  Future<void> add(String name, {int color = 0xFF6B7280, required SecretKey masterKey}) async {
    final list = await _db.listCategories();
    await _save(
      id: _uuid.v4(),
      name: name,
      color: color,
      sortOrder: list.length,
      masterKey: masterKey,
    );
  }

  Future<void> rename(String id, String name, {required SecretKey masterKey}) async {
    final existing = await _db.getCategory(id);
    if (existing == null) return;
    await _save(
      id: id,
      name: name,
      color: existing.color,
      sortOrder: existing.sortOrder,
      masterKey: masterKey,
    );
  }

  Future<void> delete(String id) => _db.deleteCategory(id);

  /// Шифрует и сохраняет категорию. dirty=true — на следующем синке уйдёт.
  Future<void> _save({
    required String id,
    required String name,
    required int color,
    required int sortOrder,
    SecretKey? masterKey,
  }) async {
    final now = DateTime.now().toUtc();
    final deviceId = await _deviceId();
    if (masterKey == null) {
      // Профиля ещё нет (не залогинены) — сохраняем без шифрования, синк позже.
      await _db.upsertCategoryRow(LocalCategory(
        id: id, name: name, color: color, sortOrder: sortOrder,
        updatedAt: now, deviceId: deviceId, dirty: true,
      ));
      return;
    }
    final box = await _cipher.encryptJson(
      payload: {'name': name, 'color': color, 'sort_order': sortOrder},
      masterKey: masterKey,
    );
    await _db.upsertCategoryRow(LocalCategory(
      id: id,
      name: name,
      color: color,
      sortOrder: sortOrder,
      ciphertext: box.ciphertext,
      nonce: box.nonce,
      updatedAt: now,
      deviceId: deviceId,
      dirty: true,
    ));
  }

  /// Для старых категорий из v1.0 (без ciphertext) — зашифровать.
  /// Вызывается перед первым sync категорий.
  Future<void> ensureAllEncrypted(SecretKey masterKey) async {
    final all = await _db.listCategories();
    for (final c in all) {
      if (c.ciphertext != null) continue;
      await _save(
        id: c.id, name: c.name, color: c.color,
        sortOrder: c.sortOrder, masterKey: masterKey,
      );
    }
  }

  /// Расшифровать payload и обновить локальную категорию (для pull).
  Future<void> applyRemote({
    required String id,
    required List<int> ciphertext,
    required List<int> nonce,
    required DateTime updatedAt,
    DateTime? deletedAt,
    required String deviceId,
    required SecretKey masterKey,
  }) async {
    if (deletedAt != null) {
      // Запись удалена на другом устройстве — стираем локально
      await _db.upsertCategoryRow(LocalCategory(
        id: id, name: '', color: 0, sortOrder: 0,
        ciphertext: null, nonce: null,
        updatedAt: updatedAt, deletedAt: deletedAt, deviceId: deviceId,
        dirty: false,
      ));
      return;
    }
    final payload = await _cipher.decryptJson(
      ciphertext: Uint8List.fromList(ciphertext),
      nonce: Uint8List.fromList(nonce),
      masterKey: masterKey,
    );
    await _db.upsertCategoryRow(LocalCategory(
      id: id,
      name: payload['name'] as String? ?? '',
      color: (payload['color'] as num?)?.toInt() ?? 0xFF6B7280,
      sortOrder: (payload['sort_order'] as num?)?.toInt() ?? 0,
      ciphertext: null, // не дублируем — для следующего синка нам блоб не нужен
      nonce: null,
      updatedAt: updatedAt,
      deletedAt: null,
      deviceId: deviceId,
      dirty: false,
    ));
  }
}
