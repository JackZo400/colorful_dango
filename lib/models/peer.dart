/// 对等端数据模型
library;

import 'dart:typed_data';

/// 通信对等端
class Peer {
  final String id;                 // 本地生成的对等端 ID
  String displayName;        // 显示名称
  final Uint8List fingerprint;     // Ed25519 公钥指纹 (8 bytes)
  final Uint8List ed25519PublicKey; // Ed25519 公钥

  /// 是否已连接
  bool isConnected;

  Peer({
    required this.id,
    required this.displayName,
    required this.fingerprint,
    required this.ed25519PublicKey,
    this.isConnected = false,
  });

  /// 十六进制指纹 (用于显示)
  String get fingerprintHex {
    return fingerprint
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':')
        .toUpperCase();
  }

  /// 短指纹 (前 4 字节)
  String get shortFingerprint {
    return fingerprint
        .sublist(0, 4)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(':')
        .toUpperCase();
  }
}
