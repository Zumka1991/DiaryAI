import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:dio/dio.dart';

import '../../core/api/auth_api.dart';
import '../../core/crypto/kdf.dart';
import '../../core/db/database.dart';
import '../../core/storage/secure_storage.dart';

/// Результаты включения синхронизации.
enum EnableSyncResult {
  registered,    // создали аккаунт на сервере
  loggedIn,      // аккаунт уже есть и наш auth_key подошёл
  conflict,      // логин занят, и наш auth_key не подходит — нужно восстанавливать
}

class AuthRepository {
  final AuthApi _api;
  final SecureStore _store;
  final AppDatabase _db;
  final CryptoKdf _kdf = CryptoKdf();

  AuthRepository(this._api, this._store, this._db);

  // ---------- состояние ----------

  Future<bool> hasProfile() => _store.hasProfile();
  Future<bool> isSyncEnabled() => _store.isSyncEnabled();

  /// Профиль создан, но master_key стёрт — нужно ввести пароль.
  Future<bool> isLocked() async {
    if (!await _store.hasProfile()) return false;
    final mk = await _store.getMasterKey();
    return mk == null;
  }

  /// Заблокировать: стираем master_key из Keychain. Записи на диске остаются
  /// (зашифрованные), но без master_key их не расшифровать.
  Future<void> lock() => _store.deleteMasterKey();

  /// Разблокировать: проверяем пароль через сравнение auth_key с сохранённым.
  /// При успехе — кладём master_key обратно в Keychain.
  Future<bool> unlock(String password) async {
    final salt = await _store.getKdfSalt();
    final params = await _store.getKdfParams();
    final storedAuthKey = await _store.getAuthKey();
    if (salt == null || params == null || storedAuthKey == null) {
      throw StateError('Профиль повреждён: нет соли/параметров/auth_key');
    }
    final keys = await _kdf.derive(
      password: password,
      salt: salt,
      params: KdfParams.fromJson(params),
    );
    // Сравнение в постоянном времени.
    if (!_constantTimeEq(keys.authKey, storedAuthKey)) return false;
    await _store.saveMasterKey(Uint8List.fromList(await keys.masterKey.extractBytes()));
    return true;
  }

  bool _constantTimeEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  Future<SecretKey?> currentMasterKey() async {
    final raw = await _store.getMasterKey();
    if (raw == null) return null;
    return SecretKey(raw);
  }

  Future<String?> currentLogin() => _store.getLogin();

  // ---------- 1. локальное создание профиля (без сервера) ----------

  /// Создаёт профиль полностью локально. Сервер не вызывается.
  /// Соль генерится случайно, ключи деривируются Argon2id, всё кладётся в Keychain.
  /// Дневник сразу готов к работе.
  Future<void> createLocalProfile({
    required String login,
    required String password,
  }) async {
    final params = const KdfParams();
    final salt = _randomBytes(16);
    final keys = await _kdf.derive(password: password, salt: salt, params: params);

    await _store.saveProfile(
      login: login.toLowerCase().trim(),
      masterKey: Uint8List.fromList(await keys.masterKey.extractBytes()),
      authKey: Uint8List.fromList(keys.authKey),
      kdfSalt: salt,
      kdfParams: params.toJson(),
    );

    // Sanity-check: убедимся что профиль реально сохранился.
    // На Windows flutter_secure_storage иногда тихо не пишет, лучше падать сразу.
    if (!await _store.hasProfile()) {
      throw StateError(
        'Не удалось сохранить профиль в защищённое хранилище. '
        'Если ты на Windows — проверь, что Credential Manager включён.',
      );
    }
  }

  // ---------- 2. включение синхронизации ----------

  /// Регистрирует существующий локальный профиль на сервере.
  /// Если логин уже занят — пробует залогиниться с нашим auth_key.
  /// Если не подошёл — возвращает conflict (нужен restoreFromServer с паролем).
  Future<EnableSyncResult> enableSync() async {
    final login = await _store.getLogin();
    final authKey = await _store.getAuthKey();
    final salt = await _store.getKdfSalt();
    final params = await _store.getKdfParams();
    if (login == null || authKey == null || salt == null || params == null) {
      throw StateError('Локальный профиль не создан');
    }
    final authKeyB64 = base64.encode(authKey);
    final saltB64 = base64.encode(salt);

    try {
      final session = await _api.register(
        login: login,
        authKeyB64: authKeyB64,
        kdfSaltB64: saltB64,
        kdfParams: params,
      );
      await _store.saveSyncSession(jwt: session.token, userId: session.userId);
      return EnableSyncResult.registered;
    } on DioException catch (e) {
      // 409 login_taken — пробуем залогиниться существующим auth_key
      if (e.response?.statusCode == 409) {
        try {
          final session = await _api.loginVerify(login: login, authKeyB64: authKeyB64);
          await _store.saveSyncSession(jwt: session.token, userId: session.userId);
          return EnableSyncResult.loggedIn;
        } on DioException catch (e2) {
          if (e2.response?.statusCode == 401) return EnableSyncResult.conflict;
          rethrow;
        }
      }
      rethrow;
    }
  }

  /// Выключить синк: убираем JWT, локальный профиль остаётся.
  Future<void> disableSync() => _store.clearSyncSession();

  // ---------- 3. восстановление с другого устройства ----------

  /// Логинимся в существующий аккаунт по логину+паролю.
  /// Деривируем ключи с серверной солью, проверяем auth_key, сохраняем профиль.
  /// ВНИМАНИЕ: затирает текущий локальный профиль (если был).
  Future<void> restoreFromServer({
    required String login,
    required String password,
  }) async {
    final loginNorm = login.toLowerCase().trim();
    final info = await _api.loginInfo(loginNorm);
    final salt = Uint8List.fromList(base64.decode(info.kdfSaltB64));
    final params = KdfParams.fromJson(info.kdfParams);

    final keys = await _kdf.derive(password: password, salt: salt, params: params);
    final session = await _api.loginVerify(
      login: loginNorm,
      authKeyB64: base64.encode(keys.authKey),
    );

    await _store.saveProfile(
      login: loginNorm,
      masterKey: Uint8List.fromList(await keys.masterKey.extractBytes()),
      authKey: Uint8List.fromList(keys.authKey),
      kdfSalt: salt,
      kdfParams: params.toJson(),
    );
    await _store.saveSyncSession(jwt: session.token, userId: session.userId);

    // Sanity check, чтобы потом не было null'ов в editor.
    if (!await _store.hasProfile()) {
      throw StateError('Не удалось сохранить профиль в защищённое хранилище.');
    }
  }

  // ---------- 4. полный выход ----------

  /// Удаляет ВСЁ с устройства: ключи, JWT, настройки И локальную БД с записями.
  /// Записи на сервере (если синк был включён) останутся, но без пароля их не открыть.
  Future<void> wipeDevice() async {
    await _store.wipeAll();
    await _db.wipe();
  }

  Uint8List _randomBytes(int n) {
    final r = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => r.nextInt(256)));
  }
}
