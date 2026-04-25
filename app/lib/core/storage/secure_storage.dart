import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Обёртка над flutter_secure_storage с типизированными ключами.
///
/// Что хранится:
///   master_key  — XChaCha20-Poly1305 ключ, шифрует записи. Никогда не уходит с устройства.
///   auth_key    — деривируется из того же пароля, отправляется на сервер при синхронизации.
///                 Хранится локально, чтобы можно было включить синк без повторного ввода пароля.
///   login, kdf_salt, kdf_params — для повторной деривации (например при смене пароля).
///   jwt         — токен сервера; есть = синхронизация включена.
///   server_url, byok_*  — настройки.
class SecureStore {
  static const _opts = AndroidOptions(encryptedSharedPreferences: true);
  final FlutterSecureStorage _s = const FlutterSecureStorage(aOptions: _opts);

  static const _kMasterKey = 'master_key_b64';
  static const _kAuthKey = 'auth_key_b64';
  static const _kJwt = 'jwt';
  static const _kLogin = 'login';
  static const _kUserId = 'user_id';
  static const _kServerUrl = 'server_url';
  static const _kKdfSalt = 'kdf_salt_b64';
  static const _kKdfParams = 'kdf_params_json';
  static const _kByokOpenrouter = 'byok_openrouter';
  static const _kByokRouterai = 'byok_routerai';

  // ---------- профиль (обязательно при первом создании) ----------

  Future<void> saveProfile({
    required String login,
    required Uint8List masterKey,
    required Uint8List authKey,
    required Uint8List kdfSalt,
    required Map<String, dynamic> kdfParams,
  }) async {
    // Последовательные записи — на Windows flutter_secure_storage
    // плохо переносит конкурентные write через Future.wait.
    await _s.write(key: _kLogin, value: login);
    await _s.write(key: _kMasterKey, value: base64.encode(masterKey));
    await _s.write(key: _kAuthKey, value: base64.encode(authKey));
    await _s.write(key: _kKdfSalt, value: base64.encode(kdfSalt));
    await _s.write(key: _kKdfParams, value: jsonEncode(kdfParams));
  }

  /// Профиль есть, если в Keychain лежит auth_key (он сохраняется и при блокировке).
  /// master_key может отсутствовать — это значит "заблокирован, нужен пароль".
  Future<bool> hasProfile() async {
    final ak = await _s.read(key: _kAuthKey);
    return ak != null && ak.isNotEmpty;
  }

  Future<String?> getLogin() => _s.read(key: _kLogin);

  Future<Uint8List?> getMasterKey() async {
    final v = await _s.read(key: _kMasterKey);
    return v == null ? null : base64.decode(v);
  }

  /// Удаляет master_key из хранилища (для блокировки). Профиль остаётся —
  /// пароль можно ввести заново, и master_key восстановится через KDF.
  Future<void> deleteMasterKey() => _s.delete(key: _kMasterKey);

  /// Сохранить master_key обратно после успешной разблокировки.
  Future<void> saveMasterKey(Uint8List key) =>
      _s.write(key: _kMasterKey, value: base64.encode(key));

  Future<Uint8List?> getAuthKey() async {
    final v = await _s.read(key: _kAuthKey);
    return v == null ? null : base64.decode(v);
  }

  Future<Uint8List?> getKdfSalt() async {
    final v = await _s.read(key: _kKdfSalt);
    return v == null ? null : base64.decode(v);
  }

  Future<Map<String, dynamic>?> getKdfParams() async {
    final v = await _s.read(key: _kKdfParams);
    return v == null ? null : Map<String, dynamic>.from(jsonDecode(v) as Map);
  }

  // ---------- синхронизация (опционально) ----------

  Future<void> saveSyncSession({required String jwt, required String userId}) async {
    await _s.write(key: _kJwt, value: jwt);
    await _s.write(key: _kUserId, value: userId);
  }

  Future<void> clearSyncSession() async {
    await _s.delete(key: _kJwt);
    await _s.delete(key: _kUserId);
  }

  Future<String?> getJwt() => _s.read(key: _kJwt);
  Future<String?> getUserId() => _s.read(key: _kUserId);
  Future<bool> isSyncEnabled() async => (await getJwt())?.isNotEmpty ?? false;

  // ---------- настройки ----------

  Future<String> getServerUrl() async {
    return await _s.read(key: _kServerUrl) ?? 'http://localhost:8090';
  }

  Future<void> setServerUrl(String url) => _s.write(key: _kServerUrl, value: url);

  Future<String?> getByokOpenRouter() => _s.read(key: _kByokOpenrouter);
  Future<void> setByokOpenRouter(String? key) =>
      key == null ? _s.delete(key: _kByokOpenrouter) : _s.write(key: _kByokOpenrouter, value: key);

  Future<String?> getByokRouterAi() => _s.read(key: _kByokRouterai);
  Future<void> setByokRouterAi(String? key) =>
      key == null ? _s.delete(key: _kByokRouterai) : _s.write(key: _kByokRouterai, value: key);

  // ---------- полный logout ----------

  Future<void> wipeAll() => _s.deleteAll();
}
