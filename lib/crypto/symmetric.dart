/// 对称加密层
///
/// 使用 AES-256-GCM (认证加密) 保护消息内容。
/// AES-256 具有 256 位密钥，对 Grover 算法提供 128 位量子安全性。
library;

import 'dart:typed_data';
import 'dart:math';
import 'package:cryptography/cryptography.dart';

/// 对称加密引擎 — 使用 AES-256-GCM
class SymmetricCrypto {
  final AesGcm _aes = AesGcm.with256bits();
  final _random = Random.secure();

  // AES-256-GCM 参数常量
  static const int keySize = 32;
  static const int nonceSize = 12;
  static const int tagSize = 16;

  /// 加密明文消息
  ///
  /// [sharedSecret] — 32 字节共享密钥 (来自密钥交换)
  /// [plaintext] — 要加密的消息
  /// 返回 nonce || ciphertext || tag 的连接
  Future<Uint8List> encrypt({
    required Uint8List sharedSecret,
    required Uint8List plaintext,
  }) async {
    final nonce = _generateNonce();
    final secretKey = SecretKey(sharedSecret);
    final secretBox = await _aes.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: nonce,
      aad: Uint8List(0),
    );

    // nonce(12) || ciphertext || tag(16)
    final result =
        Uint8List(nonceSize + secretBox.cipherText.length + tagSize);
    result.setAll(0, nonce);
    result.setAll(nonceSize, secretBox.cipherText);
    result.setAll(
        nonceSize + secretBox.cipherText.length, secretBox.mac.bytes);
    return result;
  }

  /// 解密密文
  ///
  /// [sharedSecret] — 32 字节共享密钥
  /// [encrypted] — nonce || ciphertext || tag 的连接
  /// 认证失败时抛出 StateError
  Future<Uint8List> decrypt({
    required Uint8List sharedSecret,
    required Uint8List encrypted,
  }) async {
    if (encrypted.length < nonceSize + tagSize) {
      throw ArgumentError('密文太短，可能已损坏');
    }

    final nonce = Uint8List.sublistView(encrypted, 0, nonceSize);
    final ciphertext = Uint8List.sublistView(
        encrypted, nonceSize, encrypted.length - tagSize);
    final mac = Mac(
      Uint8List.sublistView(encrypted, encrypted.length - tagSize),
    );

    final secretKey = SecretKey(sharedSecret);
    final secretBox = SecretBox(ciphertext, nonce: nonce, mac: mac);

    try {
      final decrypted = await _aes.decrypt(
        secretBox,
        secretKey: secretKey,
        aad: Uint8List(0),
      );
      return Uint8List.fromList(decrypted);
    } catch (e) {
      throw StateError('消息认证失败 — 密钥不匹配或消息被篡改 ($e)');
    }
  }

  /// 生成随机 12 字节 nonce
  Uint8List _generateNonce() {
    return Uint8List.fromList(
      List<int>.generate(nonceSize, (_) => _random.nextInt(256)),
    );
  }
}
