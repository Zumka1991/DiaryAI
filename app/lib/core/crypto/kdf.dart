import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography_plus/cryptography_plus.dart';

/// Параметры Argon2id, согласованные с сервером.
/// Сервер хранит их в users.kdf_params и отдаёт клиенту при логине.
class KdfParams {
  final String algo; // 'argon2id'
  final int memoryKib;
  final int iterations;
  final int parallelism;
  final int keyLen;

  const KdfParams({
    this.algo = 'argon2id',
    this.memoryKib = 65536, // 64 MiB
    this.iterations = 3,
    this.parallelism = 1,
    this.keyLen = 32,
  });

  factory KdfParams.fromJson(Map<String, dynamic> j) => KdfParams(
        algo: j['algo'] as String? ?? 'argon2id',
        memoryKib: (j['memory_kib'] as num?)?.toInt() ?? 65536,
        iterations: (j['iterations'] as num?)?.toInt() ?? 3,
        parallelism: (j['parallelism'] as num?)?.toInt() ?? 1,
        keyLen: (j['key_len'] as num?)?.toInt() ?? 32,
      );

  Map<String, dynamic> toJson() => {
        'algo': algo,
        'memory_kib': memoryKib,
        'iterations': iterations,
        'parallelism': parallelism,
        'key_len': keyLen,
      };
}

/// Результат деривации: master_key (локальный) + auth_key (на сервер).
class DerivedKeys {
  final SecretKey masterKey;
  final List<int> authKey;
  DerivedKeys(this.masterKey, this.authKey);
}

/// Деривация двух ключей из (login, password) через Argon2id.
/// Соль = HMAC-style separator + login (для детерминизма при первом логине,
/// сервер потом возвращает реальную сохранённую соль).
///
/// Контракт со сервером:
///   master_seed = Argon2id(password, salt + "|m", params)
///   auth_seed   = Argon2id(password, salt + "|a", params)
class CryptoKdf {
  Future<DerivedKeys> derive({
    required String password,
    required Uint8List salt,
    required KdfParams params,
  }) async {
    final algo = Argon2id(
      memory: params.memoryKib,
      iterations: params.iterations,
      parallelism: params.parallelism,
      hashLength: params.keyLen,
    );

    final masterSalt = Uint8List.fromList([...salt, ...utf8.encode('|m')]);
    final authSalt = Uint8List.fromList([...salt, ...utf8.encode('|a')]);

    final pwBytes = utf8.encode(password);

    final masterSecret = await algo.deriveKey(
      secretKey: SecretKey(pwBytes),
      nonce: masterSalt,
    );
    final authSecret = await algo.deriveKey(
      secretKey: SecretKey(pwBytes),
      nonce: authSalt,
    );

    return DerivedKeys(masterSecret, await authSecret.extractBytes());
  }
}
