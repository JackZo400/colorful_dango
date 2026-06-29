/// 密钥交换协议 — E2EE 握手 + Ed25519 身份签名
library;

import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'identity.dart';

// ─── 协议常量 ─────────────────────────────────────────────

const int protocolVersion = 1;
final Uint8List handshakeSalt = Uint8List(32);

// ─── 握手消息类型 ─────────────────────────────────────────

enum HandshakeType {
  init(0),
  response(1);

  final int code;
  const HandshakeType(this.code);

  static HandshakeType fromCode(int code) {
    switch (code) {
      case 0: return HandshakeType.init;
      case 1: return HandshakeType.response;
      default: throw ArgumentError('未知握手类型: $code');
    }
  }
}

// ─── 握手载荷 ─────────────────────────────────────────────

class HandshakePayload {
  final int version;
  final HandshakeType type;
  final Uint8List sdp;
  final Uint8List x25519PublicKey;
  final Uint8List ed25519PublicKey;
  final Uint8List signature;

  const HandshakePayload({
    required this.version,
    required this.type,
    required this.sdp,
    required this.x25519PublicKey,
    required this.ed25519PublicKey,
    required this.signature,
  });

  Uint8List encode() {
    final buf = BytesBuilder();
    buf.addByte(version);
    buf.addByte(type.code);
    buf.add(_u16be(sdp.length));
    buf.add(sdp);
    buf.add(x25519PublicKey);
    buf.add(ed25519PublicKey);
    buf.add(signature);
    return buf.toBytes();
  }

  factory HandshakePayload.decode(Uint8List data) {
    if (data.length < 132) throw ArgumentError('数据太短: ${data.length}');
    int o = 0;
    final ver = data[o++];
    final typ = HandshakeType.fromCode(data[o++]);
    final sl = _readU16be(data, o); o += 2;
    final sdp = Uint8List.sublistView(data, o, o + sl); o += sl;
    final xpk = Uint8List.sublistView(data, o, o + 32); o += 32;
    final epk = Uint8List.sublistView(data, o, o + 32); o += 32;
    final sig = Uint8List.sublistView(data, o, o + 64);
    return HandshakePayload(version: ver, type: typ, sdp: sdp,
        x25519PublicKey: xpk, ed25519PublicKey: epk, signature: sig);
  }

  static Uint8List _u16be(int v) =>
      Uint8List(2)..[0] = (v >> 8) & 0xFF..[1] = v & 0xFF;
  static int _readU16be(Uint8List d, int o) => (d[o] << 8) | d[o + 1];
}

// ─── 握手结果 ─────────────────────────────────────────────

class HandshakeResult {
  final HandshakePayload payload;
  final Uint8List x25519PrivateKey;
  final Uint8List x25519PublicKey;
  const HandshakeResult(
      {required this.payload,
      required this.x25519PrivateKey,
      required this.x25519PublicKey});
}

// ─── 密钥交换结果 ─────────────────────────────────────────

class KeyExchangeResult {
  final Uint8List sharedSecret;
  final Uint8List peerFingerprint;
  final Uint8List peerEd25519PublicKey;
  const KeyExchangeResult(
      {required this.sharedSecret,
      required this.peerFingerprint,
      required this.peerEd25519PublicKey});
}

// ─── 密钥交换引擎 ─────────────────────────────────────────

class KeyExchangeEngine {
  final X25519 _x25519 = X25519();
  final Ed25519 _ed25519 = Ed25519();

  /// Alice 创建 Offer 握手
  Future<HandshakeResult> createInitHandshake(
      {required String sdp, required CryptoIdentity identity}) async {
    final kp = await _x25519.newKeyPair();
    final spk = kp as SimpleKeyPairData;
    final ex = await spk.extract();
    final pub = Uint8List.fromList(spk.publicKey.bytes);
    final payload = await _makeHandshake(
        type: HandshakeType.init, sdp: sdp, xPub: pub, identity: identity);
    return HandshakeResult(
        payload: payload,
        x25519PrivateKey: Uint8List.fromList(ex.bytes),
        x25519PublicKey: pub);
  }

  /// Bob 创建 Answer 握手
  Future<HandshakeResult> createResponseHandshake(
      {required String sdp, required CryptoIdentity identity}) async {
    final kp = await _x25519.newKeyPair();
    final spk = kp as SimpleKeyPairData;
    final ex = await spk.extract();
    final pub = Uint8List.fromList(spk.publicKey.bytes);
    final payload = await _makeHandshake(
        type: HandshakeType.response, sdp: sdp, xPub: pub, identity: identity);
    return HandshakeResult(
        payload: payload,
        x25519PrivateKey: Uint8List.fromList(ex.bytes),
        x25519PublicKey: pub);
  }

  Future<HandshakePayload> _makeHandshake(
      {required HandshakeType type,
      required String sdp,
      required Uint8List xPub,
      required CryptoIdentity identity}) async {
    final sdpB = Uint8List.fromList(sdp.codeUnits);
    final ePK = identity.ed25519PublicKey;
    final sp = Uint8List(2 + sdpB.length + 32 + 32);
    sp[0] = protocolVersion;
    sp[1] = type.code;
    sp.setAll(2, sdpB);
    sp.setAll(2 + sdpB.length, xPub);
    sp.setAll(2 + sdpB.length + 32, ePK);
    final sig = await _ed25519.sign(sp, keyPair: identity.ed25519KeyPair);
    return HandshakePayload(
        version: protocolVersion,
        type: type,
        sdp: sdpB,
        x25519PublicKey: xPub,
        ed25519PublicKey: ePK,
        signature: Uint8List.fromList(sig.bytes));
  }

  /// 验证对方签名
  Future<bool> verifyHandshake(HandshakePayload p) async {
    final sp = Uint8List(2 + p.sdp.length + 32 + 32);
    sp[0] = p.version;
    sp[1] = p.type.code;
    sp.setAll(2, p.sdp);
    sp.setAll(2 + p.sdp.length, p.x25519PublicKey);
    sp.setAll(2 + p.sdp.length + 32, p.ed25519PublicKey);
    return _ed25519.verify(sp,
        signature: Signature(p.signature,
            publicKey:
                SimplePublicKey(p.ed25519PublicKey, type: KeyPairType.ed25519)));
  }

  /// 派生共享密钥
  Future<KeyExchangeResult> deriveSharedSecret(
      {required Uint8List myX25519PrivateKey,
      required Uint8List myX25519PublicKey,
      required Uint8List peerX25519PublicKey,
      required Uint8List peerEd25519PublicKey}) async {
    final myKP = SimpleKeyPairData(myX25519PrivateKey,
        publicKey:
            SimplePublicKey(myX25519PublicKey, type: KeyPairType.x25519),
        type: KeyPairType.x25519);
    final peerPK =
        SimplePublicKey(peerX25519PublicKey, type: KeyPairType.x25519);
    final dh = await _x25519.sharedSecretKey(keyPair: myKP, remotePublicKey: peerPK);
    final info = _sortedInfo(myX25519PublicKey, peerX25519PublicKey);
    final hkdf = Hkdf(hmac: Hmac.sha512(), outputLength: 32);
    final dhEx = await dh.extract();
    final dk = await hkdf.deriveKey(
        secretKey: SecretKey(dhEx.bytes), nonce: handshakeSalt, info: info);
    final dkEx = await dk.extract();
    final sha = Sha256();
    final h = await sha.hash(peerEd25519PublicKey);
    final fp = Uint8List.fromList(h.bytes.take(8).toList());
    return KeyExchangeResult(
        sharedSecret: Uint8List.fromList(dkEx.bytes),
        peerFingerprint: fp,
        peerEd25519PublicKey: peerEd25519PublicKey);
  }

  static Uint8List _sortedInfo(Uint8List a, Uint8List b) {
    final s = _cmp(a, b) < 0 ? [a, b] : [b, a];
    return Uint8List.fromList([...s[0], ...s[1]]);
  }
  static int _cmp(Uint8List a, Uint8List b) {
    for (int i = 0; i < a.length && i < b.length; i++)
      if (a[i] != b[i]) return a[i] - b[i];
    return a.length - b.length;
  }
}
