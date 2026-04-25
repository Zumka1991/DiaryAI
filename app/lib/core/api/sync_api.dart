import 'dart:convert';

import 'api_client.dart';

class RemoteEntry {
  final String id;
  final String ciphertextB64;
  final String nonceB64;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String deviceId;

  RemoteEntry({
    required this.id,
    required this.ciphertextB64,
    required this.nonceB64,
    required this.updatedAt,
    required this.deviceId,
    this.deletedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'ciphertext': ciphertextB64,
        'nonce': nonceB64,
        'updated_at': updatedAt.toUtc().toIso8601String(),
        if (deletedAt != null) 'deleted_at': deletedAt!.toUtc().toIso8601String(),
        'device_id': deviceId,
      };

  factory RemoteEntry.fromJson(Map<String, dynamic> j) => RemoteEntry(
        id: j['id'] as String,
        ciphertextB64: j['ciphertext'] as String,
        nonceB64: j['nonce'] as String,
        updatedAt: DateTime.parse(j['updated_at'] as String).toUtc(),
        deletedAt: j['deleted_at'] == null ? null : DateTime.parse(j['deleted_at'] as String).toUtc(),
        deviceId: j['device_id'] as String,
      );
}

class PullResult {
  final List<RemoteEntry> entries;
  final bool hasMore;
  final String? nextSince;
  PullResult(this.entries, this.hasMore, this.nextSince);
}

class SyncApi {
  final ApiClient _api;
  SyncApi(this._api);

  Future<int> push(List<RemoteEntry> entries) async {
    final r = await _api.dio.post('/sync/push', data: jsonEncode({
      'entries': entries.map((e) => e.toJson()).toList(),
    }));
    return (r.data['accepted'] as num).toInt();
  }

  Future<PullResult> pull({DateTime? since}) async {
    final qp = <String, dynamic>{};
    if (since != null) qp['since'] = since.toUtc().toIso8601String();
    final r = await _api.dio.get('/sync/pull', queryParameters: qp);
    final list = (r.data['entries'] as List).cast<Map<String, dynamic>>();
    return PullResult(
      list.map(RemoteEntry.fromJson).toList(),
      r.data['has_more'] as bool? ?? false,
      r.data['next_since'] as String?,
    );
  }
}
