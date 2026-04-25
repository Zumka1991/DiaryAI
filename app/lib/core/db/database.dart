import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Локальная БД на sqflite. Содержимое записей УЖЕ зашифровано в столбце ciphertext —
/// сама БД в открытом виде, но без мастер-ключа из неё ничего не прочитать.
/// Метаданные (даты, category_id) лежат в открытом виде для скорости фильтрации/сортировки.

class LocalEntry {
  final String id;
  final Uint8List ciphertext;
  final Uint8List nonce;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String deviceId;
  final bool dirty;
  final String? categoryId;
  final DateTime entryAt;

  LocalEntry({
    required this.id,
    required this.ciphertext,
    required this.nonce,
    required this.updatedAt,
    required this.deviceId,
    required this.dirty,
    required this.entryAt,
    this.deletedAt,
    this.categoryId,
  });

  factory LocalEntry.fromMap(Map<String, Object?> m) => LocalEntry(
        id: m['id'] as String,
        ciphertext: m['ciphertext'] as Uint8List,
        nonce: m['nonce'] as Uint8List,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int, isUtc: true),
        deletedAt: m['deleted_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['deleted_at'] as int, isUtc: true),
        deviceId: m['device_id'] as String,
        dirty: (m['dirty'] as int) != 0,
        categoryId: m['category_id'] as String?,
        entryAt: DateTime.fromMillisecondsSinceEpoch(m['entry_at'] as int, isUtc: true),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'ciphertext': ciphertext,
        'nonce': nonce,
        'updated_at': updatedAt.toUtc().millisecondsSinceEpoch,
        'deleted_at': deletedAt?.toUtc().millisecondsSinceEpoch,
        'device_id': deviceId,
        'dirty': dirty ? 1 : 0,
        'category_id': categoryId,
        'entry_at': entryAt.toUtc().millisecondsSinceEpoch,
      };
}

class LocalCategory {
  final String id;
  final String name;
  final int color;
  final int sortOrder;
  // Поля для синхронизации (могут быть пусты у категорий из старой v1.0).
  final Uint8List? ciphertext;
  final Uint8List? nonce;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final String? deviceId;
  final bool dirty;

  LocalCategory({
    required this.id,
    required this.name,
    required this.color,
    required this.sortOrder,
    this.ciphertext,
    this.nonce,
    this.updatedAt,
    this.deletedAt,
    this.deviceId,
    this.dirty = false,
  });

  factory LocalCategory.fromMap(Map<String, Object?> m) => LocalCategory(
        id: m['id'] as String,
        name: m['name'] as String,
        color: m['color'] as int,
        sortOrder: m['sort_order'] as int,
        ciphertext: m['ciphertext'] as Uint8List?,
        nonce: m['nonce'] as Uint8List?,
        updatedAt: m['updated_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int, isUtc: true),
        deletedAt: m['deleted_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['deleted_at'] as int, isUtc: true),
        deviceId: m['device_id'] as String?,
        dirty: ((m['dirty'] as int?) ?? 0) != 0,
      );
}

class AppDatabase {
  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'diaryai.sqlite');
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE entries (
            id TEXT PRIMARY KEY,
            ciphertext BLOB NOT NULL,
            nonce BLOB NOT NULL,
            updated_at INTEGER NOT NULL,
            deleted_at INTEGER,
            device_id TEXT NOT NULL,
            dirty INTEGER NOT NULL DEFAULT 1,
            category_id TEXT,
            entry_at INTEGER NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX entries_entry_at_idx ON entries(entry_at DESC)');
        await db.execute('''
          CREATE TABLE categories (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            color INTEGER NOT NULL DEFAULT ${0xFF6B7280},
            sort_order INTEGER NOT NULL DEFAULT 0,
            ciphertext BLOB,
            nonce BLOB,
            updated_at INTEGER,
            deleted_at INTEGER,
            device_id TEXT,
            dirty INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await db.execute('''
          CREATE TABLE local_meta (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          // Добавляем поля для синхронизации категорий.
          await db.execute('ALTER TABLE categories ADD COLUMN ciphertext BLOB');
          await db.execute('ALTER TABLE categories ADD COLUMN nonce BLOB');
          await db.execute('ALTER TABLE categories ADD COLUMN updated_at INTEGER');
          await db.execute('ALTER TABLE categories ADD COLUMN deleted_at INTEGER');
          await db.execute('ALTER TABLE categories ADD COLUMN device_id TEXT');
          await db.execute('ALTER TABLE categories ADD COLUMN dirty INTEGER NOT NULL DEFAULT 1');
        }
      },
    );
    return _db!;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// Полностью удалить файл БД. После этого следующий _open() создаст пустую.
  Future<void> wipe() async {
    await close();
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'diaryai.sqlite');
    await deleteDatabase(path);
  }

  // --- entries ---

  Future<List<LocalEntry>> listEntries({
    String? categoryId,
    int? limit,
    int? offset,
  }) async {
    final db = await _open();
    final rows = await db.query(
      'entries',
      where: categoryId == null ? 'deleted_at IS NULL' : 'deleted_at IS NULL AND category_id = ?',
      whereArgs: categoryId == null ? null : [categoryId],
      orderBy: 'entry_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(LocalEntry.fromMap).toList();
  }

  Future<int> countEntries({String? categoryId}) async {
    final db = await _open();
    final rows = await db.rawQuery(
      categoryId == null
          ? 'SELECT COUNT(*) AS n FROM entries WHERE deleted_at IS NULL'
          : 'SELECT COUNT(*) AS n FROM entries WHERE deleted_at IS NULL AND category_id = ?',
      categoryId == null ? null : [categoryId],
    );
    return (rows.first['n'] as int?) ?? 0;
  }

  Future<LocalEntry?> getEntry(String id) async {
    final db = await _open();
    final rows = await db.query('entries', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return LocalEntry.fromMap(rows.first);
  }

  Future<void> upsertEntry(LocalEntry e) async {
    final db = await _open();
    await db.insert('entries', e.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> markSynced(String id) async {
    final db = await _open();
    await db.update('entries', {'dirty': 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<LocalEntry>> dirtyEntries() async {
    final db = await _open();
    final rows = await db.query('entries', where: 'dirty = 1');
    return rows.map(LocalEntry.fromMap).toList();
  }

  Future<List<LocalEntry>> recentEntries({int limit = 10, Duration window = const Duration(days: 30)}) async {
    final db = await _open();
    final cutoff = DateTime.now().toUtc().subtract(window).millisecondsSinceEpoch;
    final rows = await db.query(
      'entries',
      where: 'deleted_at IS NULL AND entry_at >= ?',
      whereArgs: [cutoff],
      orderBy: 'entry_at DESC',
      limit: limit,
    );
    return rows.map(LocalEntry.fromMap).toList();
  }

  /// Возвращает контекст вокруг указанной записи: [beforeLimit] до и [afterLimit] после
  /// (сама запись исключается). Результат отсортирован хронологически (старые → новые).
  Future<List<LocalEntry>> entriesAround({
    required DateTime focusAt,
    required String focusId,
    int beforeLimit = 5,
    int afterLimit = 5,
  }) async {
    final db = await _open();
    final ts = focusAt.toUtc().millisecondsSinceEpoch;
    final before = await db.query(
      'entries',
      where: 'deleted_at IS NULL AND id != ? AND entry_at < ?',
      whereArgs: [focusId, ts],
      orderBy: 'entry_at DESC',
      limit: beforeLimit,
    );
    final after = await db.query(
      'entries',
      where: 'deleted_at IS NULL AND id != ? AND entry_at > ?',
      whereArgs: [focusId, ts],
      orderBy: 'entry_at ASC',
      limit: afterLimit,
    );
    final all = [...before.map(LocalEntry.fromMap), ...after.map(LocalEntry.fromMap)];
    all.sort((a, b) => a.entryAt.compareTo(b.entryAt));
    return all;
  }

  // --- categories ---

  Future<List<LocalCategory>> listCategories() async {
    final db = await _open();
    final rows = await db.query(
      'categories',
      where: 'deleted_at IS NULL',
      orderBy: 'sort_order ASC',
    );
    return rows.map(LocalCategory.fromMap).toList();
  }

  Future<LocalCategory?> getCategory(String id) async {
    final db = await _open();
    final rows = await db.query('categories', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return LocalCategory.fromMap(rows.first);
  }

  Future<List<LocalCategory>> dirtyCategories() async {
    final db = await _open();
    final rows = await db.query('categories',
        where: 'dirty = 1 AND ciphertext IS NOT NULL');
    return rows.map(LocalCategory.fromMap).toList();
  }

  Future<void> markCategorySynced(String id) async {
    final db = await _open();
    await db.update('categories', {'dirty': 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> upsertCategoryRow(LocalCategory c) async {
    final db = await _open();
    await db.insert('categories', {
      'id': c.id,
      'name': c.name,
      'color': c.color,
      'sort_order': c.sortOrder,
      'ciphertext': c.ciphertext,
      'nonce': c.nonce,
      'updated_at': c.updatedAt?.toUtc().millisecondsSinceEpoch,
      'deleted_at': c.deletedAt?.toUtc().millisecondsSinceEpoch,
      'device_id': c.deviceId,
      'dirty': c.dirty ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteCategory(String id) async {
    // Soft-delete для синхронизации: помечаем deleted_at, dirty=1.
    final db = await _open();
    final row = await db.query('categories', where: 'id = ?', whereArgs: [id], limit: 1);
    if (row.isEmpty) return;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.update('categories', {
      'deleted_at': now,
      'updated_at': now,
      'dirty': 1,
    }, where: 'id = ?', whereArgs: [id]);
  }

  // --- meta ---

  Future<String?> getMeta(String key) async {
    final db = await _open();
    final rows = await db.query('local_meta', where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setMeta(String key, String value) async {
    final db = await _open();
    await db.insert(
      'local_meta',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
