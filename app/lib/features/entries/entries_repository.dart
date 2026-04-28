import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:uuid/uuid.dart';

import '../../core/crypto/cipher.dart';
import '../../core/db/database.dart';

class DiaryEntry {
  final String id;
  final DateTime entryAt;
  final String? categoryId;
  final String title;
  final String text;
  final String aiComment;
  final DateTime updatedAt;
  DiaryEntry({
    required this.id,
    required this.entryAt,
    required this.text,
    required this.updatedAt,
    this.title = '',
    this.aiComment = '',
    this.categoryId,
  });
}

class EntriesRepository {
  final AppDatabase _db;
  final DiaryCipher _cipher = DiaryCipher();
  final _uuid = const Uuid();

  EntriesRepository(this._db);

  static const _kDeviceIdKey = 'device_id';

  Future<String> _deviceId() async {
    var id = await _db.getMeta(_kDeviceIdKey);
    if (id == null) {
      id = _uuid.v4();
      await _db.setMeta(_kDeviceIdKey, id);
    }
    return id;
  }

  Future<DiaryEntry> _decrypt(LocalEntry row, SecretKey masterKey) async {
    final payload = await _cipher.decryptJson(
      ciphertext: row.ciphertext,
      nonce: row.nonce,
      masterKey: masterKey,
    );
    return DiaryEntry(
      id: row.id,
      entryAt: row.entryAt,
      categoryId: row.categoryId,
      title: payload['title'] as String? ?? '',
      text: payload['text'] as String? ?? '',
      aiComment: payload['ai_comment'] as String? ?? '',
      updatedAt: row.updatedAt,
    );
  }

  Future<List<DiaryEntry>> list({required SecretKey masterKey, String? categoryId}) async {
    final rows = await _db.listEntries(categoryId: categoryId);
    return [for (final r in rows) await _decrypt(r, masterKey)];
  }

  /// Постраничная загрузка (для бесконечного скролла).
  Future<List<DiaryEntry>> listPage({
    required SecretKey masterKey,
    required int offset,
    required int limit,
    String? categoryId,
  }) async {
    final rows = await _db.listEntries(
      categoryId: categoryId,
      limit: limit,
      offset: offset,
    );
    return [for (final r in rows) await _decrypt(r, masterKey)];
  }

  Future<int> count({String? categoryId}) => _db.countEntries(categoryId: categoryId);

  Future<DiaryEntry?> get(String id, {required SecretKey masterKey}) async {
    final r = await _db.getEntry(id);
    if (r == null) return null;
    return _decrypt(r, masterKey);
  }

  Future<List<DiaryEntry>> recentForContext({required SecretKey masterKey, int limit = 10}) async {
    final rows = await _db.recentEntries(limit: limit);
    return [for (final r in rows) await _decrypt(r, masterKey)];
  }

  /// Контекст вокруг записи: записи до и после, отсортированные хронологически.
  /// Используется для AI-анализа, чтобы модель видела что было до и после.
  Future<List<DiaryEntry>> contextAround({
    required SecretKey masterKey,
    required DiaryEntry focus,
    int beforeLimit = 5,
    int afterLimit = 5,
  }) async {
    final rows = await _db.entriesAround(
      focusAt: focus.entryAt,
      focusId: focus.id,
      beforeLimit: beforeLimit,
      afterLimit: afterLimit,
    );
    return [for (final r in rows) await _decrypt(r, masterKey)];
  }

  Future<DiaryEntry> save({
    required SecretKey masterKey,
    String? id,
    String title = '',
    required String text,
    required DateTime entryAt,
    String? categoryId,
    String aiComment = '',
  }) async {
    final entryId = id ?? _uuid.v4();
    // Сохраняем дату как wall-clock (компоненты, выбранные пользователем),
    // упаковано в UTC-DateTime для удобства хранения. На любом устройстве
    // отобразится теми же часами:минутами, без сдвига по часовым поясам.
    final wc = DateTime.utc(
      entryAt.year, entryAt.month, entryAt.day,
      entryAt.hour, entryAt.minute, entryAt.second,
    );
    final payload = {
      'title': title,
      'text': text,
      'category_id': categoryId,
      'entry_at': wc.toIso8601String(),
      'ai_comment': aiComment,
    };
    final box = await _cipher.encryptJson(payload: payload, masterKey: masterKey);
    final now = DateTime.now().toUtc();
    final deviceId = await _deviceId();
    await _db.upsertEntry(LocalEntry(
      id: entryId,
      ciphertext: box.ciphertext,
      nonce: box.nonce,
      updatedAt: now,
      deletedAt: null,
      deviceId: deviceId,
      dirty: true,
      categoryId: categoryId,
      entryAt: wc,
    ));
    return DiaryEntry(
      id: entryId,
      entryAt: wc,
      categoryId: categoryId,
      title: title,
      text: text,
      aiComment: aiComment,
      updatedAt: now,
    );
  }

  Future<void> delete(String id) async {
    final row = await _db.getEntry(id);
    if (row == null) return;
    await _db.upsertEntry(LocalEntry(
      id: row.id,
      ciphertext: row.ciphertext,
      nonce: row.nonce,
      updatedAt: DateTime.now().toUtc(),
      deletedAt: DateTime.now().toUtc(),
      deviceId: row.deviceId,
      dirty: true,
      categoryId: row.categoryId,
      entryAt: row.entryAt,
    ));
  }
}
