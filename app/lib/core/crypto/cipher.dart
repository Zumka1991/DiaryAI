import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography_plus/cryptography_plus.dart';

/// Шифрование/расшифровка содержимого записей дневника.
/// Алгоритм: XChaCha20-Poly1305 (AEAD, 24-байтный nonce).
class DiaryCipher {
  final _algo = Xchacha20.poly1305Aead();

  /// Шифрует JSON-объект записи. Возвращает (ciphertext+MAC, nonce).
  Future<({Uint8List ciphertext, Uint8List nonce})> encryptJson({
    required Map<String, dynamic> payload,
    required SecretKey masterKey,
  }) async {
    final plaintext = utf8.encode(jsonEncode(payload));
    final nonce = _algo.newNonce();
    final box = await _algo.encrypt(
      plaintext,
      secretKey: masterKey,
      nonce: nonce,
    );
    // Складываем cipher + mac в один blob
    final out = Uint8List(box.cipherText.length + box.mac.bytes.length);
    out.setRange(0, box.cipherText.length, box.cipherText);
    out.setRange(box.cipherText.length, out.length, box.mac.bytes);
    return (ciphertext: out, nonce: Uint8List.fromList(nonce));
  }

  Future<Map<String, dynamic>> decryptJson({
    required Uint8List ciphertext,
    required Uint8List nonce,
    required SecretKey masterKey,
  }) async {
    const macLen = 16; // Poly1305
    if (ciphertext.length < macLen) {
      throw StateError('ciphertext too short');
    }
    final ct = ciphertext.sublist(0, ciphertext.length - macLen);
    final mac = Mac(ciphertext.sublist(ciphertext.length - macLen));
    final box = SecretBox(ct, nonce: nonce, mac: mac);
    final plain = await _algo.decrypt(box, secretKey: masterKey);
    return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
  }
}
