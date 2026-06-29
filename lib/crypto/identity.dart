/// 身份密钥管理模块
///
/// 每个用户拥有两对密钥:
///   1. Ed25519 — 用于身份签名和验证
///   2. X25519 — 用于密钥交换 (ECDH)
///
/// 密钥持久化到本地存储，首次启动自动生成。
library;

import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// 用户的加密身份
class CryptoIdentity {
  final SimpleKeyPairData ed25519KeyPair;
  final SimpleKeyPairData x25519KeyPair;

  const CryptoIdentity({
    required this.ed25519KeyPair,
    required this.x25519KeyPair,
  });

  /// Ed25519 公钥 (32 bytes)
  Uint8List get ed25519PublicKey =>
      Uint8List.fromList(ed25519KeyPair.publicKey.bytes);

  /// X25519 公钥 (32 bytes)
  Uint8List get x25519PublicKey =>
      Uint8List.fromList(x25519KeyPair.publicKey.bytes);

  /// Ed25519 私钥 (32 bytes) — 需要通过 extract 获取
  Future<Uint8List> get ed25519PrivateKey async {
    final ex = await ed25519KeyPair.extract();
    return Uint8List.fromList(ex.bytes);
  }

  /// X25519 私钥 (32 bytes) — 需要通过 extract 获取
  Future<Uint8List> get x25519PrivateKey async {
    final ex = await x25519KeyPair.extract();
    return Uint8List.fromList(ex.bytes);
  }
}

/// 身份密钥生成器
class IdentityManager {
  final Ed25519 _ed25519 = Ed25519();
  final X25519 _x25519 = X25519();

  /// 生成全新的身份密钥对
  Future<CryptoIdentity> generateIdentity() async {
    final ed25519 = await _ed25519.newKeyPair();
    final x25519 = await _x25519.newKeyPair();

    return CryptoIdentity(
      ed25519KeyPair: ed25519 as SimpleKeyPairData,
      x25519KeyPair: x25519 as SimpleKeyPairData,
    );
  }

  /// 从已存储的字节恢复身份
  CryptoIdentity restoreIdentity({
    required Uint8List ed25519PublicKey,
    required Uint8List ed25519PrivateKey,
    required Uint8List x25519PublicKey,
    required Uint8List x25519PrivateKey,
  }) {
    return CryptoIdentity(
      ed25519KeyPair: SimpleKeyPairData(
        ed25519PrivateKey,
        publicKey: SimplePublicKey(
            ed25519PublicKey, type: KeyPairType.ed25519),
        type: KeyPairType.ed25519,
      ),
      x25519KeyPair: SimpleKeyPairData(
        x25519PrivateKey,
        publicKey:
            SimplePublicKey(x25519PublicKey, type: KeyPairType.x25519),
        type: KeyPairType.x25519,
      ),
    );
  }

  /// 生成身份指纹 (SHA-256 前 8 字节，用于显示)
  Future<Uint8List> fingerprint(CryptoIdentity identity) async {
    final sha256 = Sha256();
    final hash = await sha256.hash(identity.ed25519PublicKey);
    return Uint8List.fromList(hash.bytes.take(8).toList());
  }
}
