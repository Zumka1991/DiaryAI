import 'package:uuid/uuid.dart';

import '../../core/db/database.dart';

class CategoriesRepository {
  final AppDatabase _db;
  final _uuid = const Uuid();
  CategoriesRepository(this._db);

  static const defaultCategories = <({String name, int color})>[
    (name: 'Личное', color: 0xFF8B7CB6),
    (name: 'Работа', color: 0xFF4F8FB8),
    (name: 'Здоровье', color: 0xFF5FA37A),
    (name: 'Идеи', color: 0xFFD4A75C),
    (name: 'Отношения', color: 0xFFC57A8E),
  ];

  Future<List<LocalCategory>> list() => _db.listCategories();

  Future<void> ensureDefaults() async {
    final existing = await _db.listCategories();
    if (existing.isNotEmpty) return;
    for (var i = 0; i < defaultCategories.length; i++) {
      final c = defaultCategories[i];
      await _db.upsertCategory(
        id: _uuid.v4(),
        name: c.name,
        color: c.color,
        sortOrder: i,
      );
    }
  }

  Future<void> add(String name, {int color = 0xFF6B7280}) async {
    final list = await _db.listCategories();
    await _db.upsertCategory(
      id: _uuid.v4(),
      name: name,
      color: color,
      sortOrder: list.length,
    );
  }

  Future<void> rename(String id, String name) =>
      _db.upsertCategory(id: id, name: name);

  Future<void> delete(String id) => _db.deleteCategory(id);
}
