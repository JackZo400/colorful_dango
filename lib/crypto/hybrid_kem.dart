/// 混合后量子密钥封装机制 (Hybrid Post-Quantum KEM)
library;

import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class KemResult {
  final Uint8List sharedSecret;
  final Uint8List ciphertext;
  const KemResult({required this.sharedSecret, required this.ciphertext});
}

abstract class KeyEncapsulationMechanism {
  Future<(Uint8List, Uint8List)> keyGen();
  Future<KemResult> encapsulate(Uint8List remotePublicKey);
  Future<Uint8List> decapsulate(Uint8List ciphertext, Uint8List localPrivateKey);
}

/// Phase 1: X25519 KEM (密文=自己的公钥)
class X25519Kem implements KeyEncapsulationMechanism {
  final X25519 _x25519 = X25519();

  @override
  Future<(Uint8List, Uint8List)> keyGen() async {
    final kp = await _x25519.newKeyPair();
    final spk = kp as SimpleKeyPairData;
    final ex = await spk.extract();
    return (
      Uint8List.fromList(ex.bytes),
      Uint8List.fromList(spk.publicKey.bytes),
    );
  }

  @override
  Future<KemResult> encapsulate(Uint8List remotePublicKey) async {
    final (myPriv, myPub) = await keyGen();
    final myKP = SimpleKeyPairData(myPriv,
        publicKey: SimplePublicKey(myPub, type: KeyPairType.x25519),
        type: KeyPairType.x25519);
    final remotePK =
        SimplePublicKey(remotePublicKey, type: KeyPairType.x25519);
    final dh = await _x25519.sharedSecretKey(keyPair: myKP, remotePublicKey: remotePK);
    final hkdf = Hkdf(hmac: Hmac.sha512(), outputLength: 32);
    final dhEx = await dh.extract();
    final dk = await hkdf.deriveKey(
        secretKey: SecretKey(dhEx.bytes), nonce: Uint8List(0));
    final dkEx = await dk.extract();
    return KemResult(
        sharedSecret: Uint8List.fromList(dkEx.bytes), ciphertext: myPub);
  }

  @override
  Future<Uint8List> decapsulate(
      Uint8List ciphertext, Uint8List localPrivateKey) async {
    final myKP = SimpleKeyPairData(localPrivateKey,
        publicKey: SimplePublicKey(Uint8List(32), type: KeyPairType.x25519),
        type: KeyPairType.x25519);
    final remotePK =
        SimplePublicKey(ciphertext, type: KeyPairType.x25519);
    final dh = await _x25519.sharedSecretKey(keyPair: myKP, remotePublicKey: remotePK);
    final hkdf = Hkdf(hmac: Hmac.sha512(), outputLength: 32);
    final dhEx = await dh.extract();
    final dk = await hkdf.deriveKey(
        secretKey: SecretKey(dhEx.bytes), nonce: Uint8List(0));
    final dkEx = await dk.extract();
    return Uint8List.fromList(dkEx.bytes);
  }
}

/// 混合 KEM: X25519 + (可选) Kyber
class HybridKEM {
  final X25519Kem _classical = X25519Kem();
  final KeyEncapsulationMechanism? _pq;

  HybridKEM({KeyEncapsulationMechanism? postQuantumKem}) : _pq = postQuantumKem;

  int get protocolVersion => _pq != null ? 2 : 1;

  Future<(Uint8List, Uint8List)> generateAuthKey() async {
    final ed = Ed25519();
    final kp = await ed.newKeyPair();
    final spk = kp as SimpleKeyPairData;
    final ex = await spk.extract();
    return (
      Uint8List.fromList(ex.bytes),
      Uint8List.fromList(spk.publicKey.bytes),
    );
  }

  Future<KemResult> encapsulate(Uint8List remoteClassicalPubKey,
      [Uint8List? remotePqPubKey]) async {
    final cr = await _classical.encapsulate(remoteClassicalPubKey);
    if (_pq != null && remotePqPubKey != null) {
      final pr = await _pq!.encapsulate(remotePqPubKey);
      return await _combine(cr, pr);
    }
    return cr;
  }

  Future<Uint8List> decapsulate(
      Uint8List classicalCiphertext,
      Uint8List classicalPrivateKey,
      {Uint8List? pqCiphertext,
      Uint8List? pqPrivateKey}) async {
    final cs =
        await _classical.decapsulate(classicalCiphertext, classicalPrivateKey);
    if (_pq != null && pqCiphertext != null && pqPrivateKey != null) {
      final ps = await _pq!.decapsulate(pqCiphertext, pqPrivateKey);
      final combined = await _combine(
          KemResult(sharedSecret: cs, ciphertext: classicalCiphertext),
          KemResult(sharedSecret: ps, ciphertext: pqCiphertext));
      return combined.sharedSecret;
    }
    return cs;
  }

  Future<KemResult> _combine(KemResult a, KemResult b) async {
    final combined = Uint8List(a.sharedSecret.length + b.sharedSecret.length);
    combined.setAll(0, a.sharedSecret);
    combined.setAll(a.sharedSecret.length, b.sharedSecret);
    final sha = Sha512();
    final h = await sha.hash(combined);
    return KemResult(
        sharedSecret: Uint8List.fromList(h.bytes.take(32).toList()),
        ciphertext: Uint8List.fromList([...a.ciphertext, ...b.ciphertext]));
  }
}
