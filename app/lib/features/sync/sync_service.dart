import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography_plus/cryptography_plus.dart';

import '../../core/api/sync_api.dart';
import '../../core/crypto/cipher.dart';
import '../../core/db/database.dart';
import '../categories/categories_repository.dart';

class SyncService {
  final SyncApi _entriesApi;
  final SyncApi _categoriesApi;
  final AppDatabase _db;
  final CategoriesRepository _categories;
  final Future<SecretKey?> Function() _masterKeyProvider;

  SyncService(
    this._entriesApi,
    this._categoriesApi,
    this._db,
    this._categories,
    this._masterKeyProvider,
  );

  static const _kEntriesSinceKey = 'last_sync_at';
  static const _kCategoriesSinceKey = 'last_sync_categories_at';

  Future<DateTime?> _getSince(String key) async {
    final v = await _db.getMeta(key);
    return v == null ? null : DateTime.parse(v);
  }

  Future<void> _setSince(String key, DateTime t) =>
      _db.setMeta(key, t.toUtc().toIso8601String());

  /// Полный цикл: записи + категории, pull → merge → push.
  Future<({int pulled, int pushed})> syncOnce() async {
    final entries = await _syncEntries();
    final cats = await _syncCategories();
    return (
      pulled: entries.pulled + cats.pulled,
      pushed: entries.pushed + cats.pushed,
    );
  }

  // ============== ENTRIES ==============

  Future<({int pulled, int pushed})> _syncEntries() async {
    final since = await _getSince(_kEntriesSinceKey);
    final pull = await _entriesApi.pull(since: since);
    var newest = since ?? DateTime.fromMillisecondsSinceEpoch(0).toUtc();

    final masterKey = await _masterKeyProvider();
    final cipher = DiaryCipher();

    for (final r in pull.entries) {
      final existing = await _db.getEntry(r.id);
      if (existing != null && !existing.updatedAt.isBefore(r.updatedAt)) continue;

      final ct = Uint8List.fromList(base64.decode(r.ciphertextB64));
      final nonce = Uint8List.fromList(base64.decode(r.nonceB64));

      // Расшифровываем payload, чтобы выставить актуальные denormalized
      // поля category_id и entry_at — иначе UI на этом устройстве будет
      // показывать стары значения из локальной строки.
      String? categoryId = existing?.categoryId;
      DateTime entryAt = existing?.entryAt ?? r.updatedAt;
      if (masterKey != null) {
        try {
          final payload = await cipher.decryptJson(
            ciphertext: ct, nonce: nonce, masterKey: masterKey,
          );
          categoryId = payload['category_id'] as String?;
          final eaStr = payload['entry_at'] as String?;
          if (eaStr != null) {
            entryAt = DateTime.parse(eaStr).toUtc();
          }
        } catch (_) {
          // Не смогли расшифровать (чужим ключом) — оставляем старые поля.
        }
      }

      await _db.upsertEntry(LocalEntry(
        id: r.id,
        ciphertext: ct,
        nonce: nonce,
        updatedAt: r.updatedAt,
        deletedAt: r.deletedAt,
        deviceId: r.deviceId,
        dirty: false,
        categoryId: categoryId,
        entryAt: entryAt,
      ));
      if (r.updatedAt.isAfter(newest)) newest = r.updatedAt;
    }

    final dirty = await _db.dirtyEntries();
    int pushed = 0;
    if (dirty.isNotEmpty) {
      final batch = dirty
          .map((e) => RemoteEntry(
                id: e.id,
                ciphertextB64: base64.encode(e.ciphertext),
                nonceB64: base64.encode(e.nonce),
                updatedAt: e.updatedAt,
                deletedAt: e.deletedAt,
                deviceId: e.deviceId,
              ))
          .toList();
      pushed = await _entriesApi.push(batch);
      for (final e in dirty) {
        await _db.markSynced(e.id);
        if (e.updatedAt.isAfter(newest)) newest = e.updatedAt;
      }
    }
    await _setSince(_kEntriesSinceKey, newest);
    return (pulled: pull.entries.length, pushed: pushed);
  }

  // ============== CATEGORIES ==============

  Future<({int pulled, int pushed})> _syncCategories() async {
    final masterKey = await _masterKeyProvider();
    if (masterKey == null) return (pulled: 0, pushed: 0);

    // Дошифровываем старые категории (из v1.0) перед первым sync.
    await _categories.ensureAllEncrypted(masterKey);

    final since = await _getSince(_kCategoriesSinceKey);
    final pull = await _categoriesApi.pull(since: since);
    var newest = since ?? DateTime.fromMillisecondsSinceEpoch(0).toUtc();

    for (final r in pull.entries) {
      final existing = await _db.getCategory(r.id);
      if (existing?.updatedAt != null && !existing!.updatedAt!.isBefore(r.updatedAt)) {
        continue;
      }
      try {
        await _categories.applyRemote(
          id: r.id,
          ciphertext: base64.decode(r.ciphertextB64),
          nonce: base64.decode(r.nonceB64),
          updatedAt: r.updatedAt,
          deletedAt: r.deletedAt,
          deviceId: r.deviceId,
          masterKey: masterKey,
        );
      } catch (_) {
        // Не смогли расшифровать чужой блоб — пропускаем.
      }
      if (r.updatedAt.isAfter(newest)) newest = r.updatedAt;
    }

    final dirty = await _db.dirtyCategories();
    int pushed = 0;
    if (dirty.isNotEmpty) {
      final batch = dirty.map((c) => RemoteEntry(
            id: c.id,
            ciphertextB64: base64.encode(c.ciphertext!),
            nonceB64: base64.encode(c.nonce!),
            updatedAt: c.updatedAt!,
            deletedAt: c.deletedAt,
            deviceId: c.deviceId ?? 'unknown',
          )).toList();
      pushed = await _categoriesApi.push(batch);
      for (final c in dirty) {
        await _db.markCategorySynced(c.id);
        if (c.updatedAt!.isAfter(newest)) newest = c.updatedAt!;
      }
    }
    await _setSince(_kCategoriesSinceKey, newest);
    return (pulled: pull.entries.length, pushed: pushed);
  }
}
