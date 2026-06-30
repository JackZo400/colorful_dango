/// 会话管理
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../crypto/key_exchange.dart';
import '../crypto/symmetric.dart';
import '../crypto/identity.dart';
import '../models/message.dart';
import '../models/peer.dart';
import 'connection_manager.dart';

enum SessionPhase { idle, offerCreated, answerCreated, handshaking, ready, failed }

class SecureSession {
  final CryptoIdentity _identity;
  final KeyExchangeEngine _keyExchange = KeyExchangeEngine();
  final SymmetricCrypto _symmetric = SymmetricCrypto();
  final P2PConnection _p2p = P2PConnection();

  Uint8List? _myX25519Private;
  Uint8List? _myX25519Public;
  Uint8List? _sharedSecret;
  Peer? _peer;
  String? _encodedPayload;

  void Function(ChatMessage)? onMessageReceived;
  void Function(Peer)? onPeerConnected;
  void Function(ChatMessage)? onDeleteRequest;
  void Function()? onClearRequest;
  void Function(dynamic)? onPhaseChanged; // 兼容旧代码
  SessionPhase _phase = SessionPhase.idle; // 兼容旧代码
  SessionPhase get phase => _phase;

  bool get isReady => _p2p.isOpen;
  Peer? get peer => _peer;

  SecureSession({required CryptoIdentity identity}) : _identity = identity {
    _p2p.onMessage = _onP2PMessage;
  }

  // ─── 发起方 ───

  Future<String> createOffer() async {
    final sdp = await _p2p.createOffer();
    final result = await _keyExchange.createInitHandshake(sdp: sdp, identity: _identity);
    _myX25519Private = result.x25519PrivateKey;
    _myX25519Public = result.x25519PublicKey;
    _encodedPayload = _encode(result.payload.encode());
    return _encodedPayload!;
  }

  Future<void> acceptAnswer(String encodedAnswer) async {
    final answerHandshake = HandshakePayload.decode(_decode(encodedAnswer));
    if (!await _keyExchange.verifyHandshake(answerHandshake)) throw StateError('签名验证失败');
    final r = await _keyExchange.deriveSharedSecret(
      myX25519PrivateKey: _myX25519Private!,
      myX25519PublicKey: _myX25519Public!,
      peerX25519PublicKey: answerHandshake.x25519PublicKey,
      peerEd25519PublicKey: answerHandshake.ed25519PublicKey,
    );
    _sharedSecret = r.sharedSecret;
    _peer = _makePeer(answerHandshake.ed25519PublicKey, r.peerFingerprint);
    await _p2p.setRemoteAnswer(utf8.decode(answerHandshake.sdp));
    // 等 DataChannel 打开后回调
    _waitReady();
  }

  // ─── 应答方 ───

  Future<String> createAnswer(String encodedOffer) async {
    final offerHandshake = HandshakePayload.decode(_decode(encodedOffer));
    if (!await _keyExchange.verifyHandshake(offerHandshake)) throw StateError('签名验证失败');
    final answerSdp = await _p2p.createAnswer(utf8.decode(offerHandshake.sdp));
    final result = await _keyExchange.createResponseHandshake(sdp: answerSdp, identity: _identity);
    _myX25519Private = result.x25519PrivateKey;
    _myX25519Public = result.x25519PublicKey;
    final r = await _keyExchange.deriveSharedSecret(
      myX25519PrivateKey: _myX25519Private!,
      myX25519PublicKey: _myX25519Public!,
      peerX25519PublicKey: offerHandshake.x25519PublicKey,
      peerEd25519PublicKey: offerHandshake.ed25519PublicKey,
    );
    _sharedSecret = r.sharedSecret;
    _peer = _makePeer(offerHandshake.ed25519PublicKey, r.peerFingerprint);
    _encodedPayload = _encode(result.payload.encode());
    _waitReady();
    return _encodedPayload!;
  }

  void _waitReady() {
    _p2p.ready.then((_) {
      if (_peer != null) { _peer!.isConnected = true; onPeerConnected?.call(_peer!); }
    });
  }

  // ─── 消息 ───

  Future<void> sendTextMessage(String id, String text) async {
    final ct = await _symmetric.encrypt(sharedSecret: _sharedSecret!, plaintext: Uint8List.fromList(utf8.encode('MSG|$id|$text')));
    await _p2p.send(ct);
  }

  Future<void> sendDeleteRequest(String messageId) async {
    if (_sharedSecret == null) return;
    final ct = await _symmetric.encrypt(sharedSecret: _sharedSecret!, plaintext: Uint8List.fromList(utf8.encode('__DEL__|$messageId')));
    await _p2p.send(ct);
  }

  Future<void> sendClearRequest() async {
    if (_sharedSecret == null) return;
    final ct = await _symmetric.encrypt(sharedSecret: _sharedSecret!, plaintext: Uint8List.fromList(utf8.encode('__CLR__')));
    await _p2p.send(ct);
  }

  void _onP2PMessage(Uint8List encrypted) {
    if (_sharedSecret == null) return;
    _symmetric.decrypt(sharedSecret: _sharedSecret!, encrypted: encrypted).then((pt) {
      final text = utf8.decode(pt);
      if (text.startsWith('MSG|')) {
        final p = text.split('|');
        final id = p.length > 1 ? p[1] : '';
        final body = p.length > 2 ? p.sublist(2).join('|') : '';
        onMessageReceived?.call(ChatMessage(id: id, text: body, timestamp: DateTime.now(), direction: MessageDirection.received));
      } else if (text.startsWith('__DEL__|')) {
        onDeleteRequest?.call(ChatMessage.received(text.substring(8)));
      } else if (text == '__CLR__') {
        onClearRequest?.call();
      }
    }).catchError((_) {});
  }

  void close() => _p2p.close();
  void dispose() => _p2p.close(); // 兼容

  Peer _makePeer(Uint8List pk, Uint8List fp) {
    final h = fp.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
    return Peer(id: h.replaceAll(':', ''), displayName: h, fingerprint: fp, ed25519PublicKey: pk, isConnected: true);
  }

  static String _encode(Uint8List data) {
    final c = Uint8List.fromList(gzip.encode(data));
    final s = base64.encode(c).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
    return s;
  }

  static Uint8List _decode(String s) {
    var b = s.replaceAll('-', '+').replaceAll('_', '/');
    while (b.length % 4 != 0) b += '=';
    return Uint8List.fromList(gzip.decode(base64.decode(b)));
  }
}
