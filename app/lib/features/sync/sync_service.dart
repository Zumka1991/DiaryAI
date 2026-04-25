import 'dart:convert';
import 'dart:typed_data';

import '../../core/api/sync_api.dart';
import '../../core/db/database.dart';

class SyncService {
  final SyncApi _api;
  final AppDatabase _db;

  SyncService(this._api, this._db);

  static const _kLastSyncKey = 'last_sync_at';

  Future<DateTime?> _getSince() async {
    final v = await _db.getMeta(_kLastSyncKey);
    return v == null ? null : DateTime.parse(v);
  }

  Future<void> _setSince(DateTime t) =>
      _db.setMeta(_kLastSyncKey, t.toUtc().toIso8601String());

  Future<({int pulled, int pushed})> syncOnce() async {
    final since = await _getSince();
    final pull = await _api.pull(since: since);
    var newest = since ?? DateTime.fromMillisecondsSinceEpoch(0).toUtc();

    for (final r in pull.entries) {
      final existing = await _db.getEntry(r.id);
      if (existing != null && !existing.updatedAt.isBefore(r.updatedAt)) continue;
      await _db.upsertEntry(LocalEntry(
        id: r.id,
        ciphertext: Uint8List.fromList(base64.decode(r.ciphertextB64)),
        nonce: Uint8List.fromList(base64.decode(r.nonceB64)),
        updatedAt: r.updatedAt,
        deletedAt: r.deletedAt,
        deviceId: r.deviceId,
        dirty: false,
        categoryId: existing?.categoryId,
        entryAt: existing?.entryAt ?? r.updatedAt,
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
      pushed = await _api.push(batch);
      for (final e in dirty) {
        await _db.markSynced(e.id);
        if (e.updatedAt.isAfter(newest)) newest = e.updatedAt;
      }
    }

    await _setSince(newest);
    return (pulled: pull.entries.length, pushed: pushed);
  }
}
