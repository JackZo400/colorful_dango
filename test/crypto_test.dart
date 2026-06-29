/// 加密模块测试
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:colorful_dango/crypto/identity.dart';
import 'package:colorful_dango/crypto/key_exchange.dart';
import 'package:colorful_dango/crypto/symmetric.dart';
import 'dart:typed_data';

void main() {
  // ─── 身份密钥生成 ───────────────────────────────────────

  group('IdentityManager', () {
    test('generateIdentity 生成 Ed25519 + X25519 密钥对', () async {
      final manager = IdentityManager();
      final identity = await manager.generateIdentity();

      expect(identity.ed25519PublicKey.length, 32);
      expect((await identity.ed25519PrivateKey).length, 32);
      expect(identity.x25519PublicKey.length, 32);
      expect((await identity.x25519PrivateKey).length, 32);
    });

    test('restoreIdentity 从字节恢复与 fingerprint 正确', () async {
      final manager = IdentityManager();
      final identity = await manager.generateIdentity();

      final restored = manager.restoreIdentity(
        ed25519PublicKey: identity.ed25519PublicKey,
        ed25519PrivateKey: await identity.ed25519PrivateKey,
        x25519PublicKey: identity.x25519PublicKey,
        x25519PrivateKey: await identity.x25519PrivateKey,
      );

      // 指纹应一致
      final fp1 = await manager.fingerprint(identity);
      final fp2 = await manager.fingerprint(restored);
      expect(fp1, fp2);
      expect(fp1.length, 8);
    });
  });

  // ─── 对称加密 ─────────────────────────────────────────

  group('SymmetricCrypto', () {
    test('encrypt + decrypt 往返正确', () async {
      final crypto = SymmetricCrypto();
      final key = Uint8List.fromList(List.generate(32, (i) => i));

      final plaintext = Uint8List.fromList('Hello, SecureChat!'.codeUnits);
      final encrypted = await crypto.encrypt(
        sharedSecret: key,
        plaintext: plaintext,
      );

      // 密文长度 = nonce(12) + plaintext + tag(16)
      expect(encrypted.length, 12 + plaintext.length + 16);

      final decrypted = await crypto.decrypt(
        sharedSecret: key,
        encrypted: encrypted,
      );

      expect(decrypted, plaintext);
    });

    test('错误密钥导致解密失败', () async {
      final crypto = SymmetricCrypto();
      final key1 = Uint8List.fromList(List.generate(32, (i) => i));
      final key2 = Uint8List.fromList(List.generate(32, (i) => i ^ 0xFF));

      final encrypted = await crypto.encrypt(
        sharedSecret: key1,
        plaintext: Uint8List.fromList('test'.codeUnits),
      );

      expect(
        () => crypto.decrypt(sharedSecret: key2, encrypted: encrypted),
        throwsA(isA<StateError>()),
      );
    });

    test('篡改密文导致认证失败', () async {
      final crypto = SymmetricCrypto();
      final key = Uint8List.fromList(List.generate(32, (i) => i));

      final encrypted = await crypto.encrypt(
        sharedSecret: key,
        plaintext: Uint8List.fromList('test'.codeUnits),
      );

      // 篡改密文最后一个字节
      final tampered = Uint8List.fromList(encrypted);
      tampered[tampered.length - 1] ^= 0xFF;

      expect(
        () => crypto.decrypt(sharedSecret: key, encrypted: tampered),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ─── 密钥交换 ─────────────────────────────────────────

  group('KeyExchangeEngine', () {
    test('完整握手流程: Alice ↔ Bob 派生相同共享密钥', () async {
      final manager = IdentityManager();
      final aliceId = await manager.generateIdentity();
      final bobId = await manager.generateIdentity();

      final engine = KeyExchangeEngine();

      // Alice 生成 Offer
      final aliceResult = await engine.createInitHandshake(
        sdp: 'mock_sdp_alice_offer',
        identity: aliceId,
      );

      // Bob 验证 Alice 的签名
      final aliceValid = await engine.verifyHandshake(aliceResult.payload);
      expect(aliceValid, true);

      // Bob 生成 Answer
      final bobResult = await engine.createResponseHandshake(
        sdp: 'mock_sdp_bob_answer',
        identity: bobId,
      );

      // Alice 验证 Bob 的签名
      final bobValid = await engine.verifyHandshake(bobResult.payload);
      expect(bobValid, true);

      // Alice 派生共享密钥
      final aliceSecret = await engine.deriveSharedSecret(
        myX25519PrivateKey: aliceResult.x25519PrivateKey,
        myX25519PublicKey: aliceResult.x25519PublicKey,
        peerX25519PublicKey: bobResult.payload.x25519PublicKey,
        peerEd25519PublicKey: bobResult.payload.ed25519PublicKey,
      );

      // Bob 派生共享密钥
      final bobSecret = await engine.deriveSharedSecret(
        myX25519PrivateKey: bobResult.x25519PrivateKey,
        myX25519PublicKey: bobResult.x25519PublicKey,
        peerX25519PublicKey: aliceResult.payload.x25519PublicKey,
        peerEd25519PublicKey: aliceResult.payload.ed25519PublicKey,
      );

      // 双方应得到相同的共享密钥
      expect(aliceSecret.sharedSecret, bobSecret.sharedSecret);
      expect(aliceSecret.sharedSecret.length, 32);
    });

    test('HandshakePayload encode/decode 往返正确', () async {
      final manager = IdentityManager();
      final identity = await manager.generateIdentity();
      final engine = KeyExchangeEngine();

      final result = await engine.createInitHandshake(
        sdp: 'test_sdp_string',
        identity: identity,
      );

      final encoded = result.payload.encode();
      final decoded = HandshakePayload.decode(encoded);

      expect(decoded.version, result.payload.version);
      expect(decoded.type, result.payload.type);
      expect(String.fromCharCodes(decoded.sdp), 'test_sdp_string');
      expect(decoded.x25519PublicKey, result.payload.x25519PublicKey);
      expect(decoded.ed25519PublicKey, result.payload.ed25519PublicKey);
      expect(decoded.signature, result.payload.signature);
    });

    test('签名验证拒绝篡改的握手消息', () async {
      final manager = IdentityManager();
      final identity = await manager.generateIdentity();
      final engine = KeyExchangeEngine();

      final result = await engine.createInitHandshake(
        sdp: 'test_sdp',
        identity: identity,
      );

      // 篡改 SDP
      final encoded = result.payload.encode();
      encoded[4] ^= 0xFF; // 翻转 sdp 的第一个字节
      final tampered = HandshakePayload.decode(encoded);

      final valid = await engine.verifyHandshake(tampered);
      expect(valid, false);
    });
  });
}
