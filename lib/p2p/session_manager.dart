/// 会话管理器
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

typedef OnSessionPhaseChanged = void Function(SessionPhase phase);
typedef OnSessionMessageReceived = void Function(ChatMessage message);
typedef OnSessionPeerConnected = void Function(Peer peer);
typedef OnSessionVoidCallback = void Function();

class SecureSession {
  final CryptoIdentity _identity;
  final KeyExchangeEngine _keyExchange = KeyExchangeEngine();
  final SymmetricCrypto _symmetric = SymmetricCrypto();
  final P2PConnectionManager _p2p;

  SessionPhase _phase = SessionPhase.idle;
  Uint8List? _myX25519Private;
  Uint8List? _myX25519Public;
  Uint8List? _sharedSecret;
  Peer? _peer;
  String? _encodedPayload;

  OnSessionPhaseChanged? onPhaseChanged;
  OnSessionMessageReceived? onMessageReceived;
  OnSessionPeerConnected? onPeerConnected;
  OnSessionMessageReceived? onDeleteRequest;
  OnSessionVoidCallback? onClearRequest;

  SessionPhase get phase => _phase;
  Peer? get peer => _peer;
  bool get isReady => _phase == SessionPhase.ready;
  String? get encodedPayload => _encodedPayload;

  SecureSession({required CryptoIdentity identity, List<String>? stunServers})
      : _identity = identity,
        _p2p = P2PConnectionManager(customStunServers: stunServers) {
    _p2p.onMessageReceived = _handleP2PMessage;
    _p2p.onStateChanged = _handleP2PStateChange;
  }

  // ─── Alice: 发起连接 ─────────────────────────────────

  Future<String> createOffer() async {
    final sdp = await _p2p.createOffer();
    final result = await _keyExchange.createInitHandshake(sdp: sdp, identity: _identity);
    _myX25519Private = result.x25519PrivateKey;
    _myX25519Public = result.x25519PublicKey;
    _encodedPayload = _base64UrlEncode(result.payload.encode());
    _setPhase(SessionPhase.offerCreated);
    return _encodedPayload!;
  }

  Future<void> acceptAnswer(String encodedAnswer) async {
    _setPhase(SessionPhase.handshaking);
    final answerHandshake = HandshakePayload.decode(_base64UrlDecode(encodedAnswer));
    if (!await _keyExchange.verifyHandshake(answerHandshake)) {
      _setPhase(SessionPhase.failed);
      throw StateError('签名验证失败');
    }
    // 先设 peer 和 secret，再 setRemote (防止 ICE 竞态)
    final r = await _keyExchange.deriveSharedSecret(
      myX25519PrivateKey: _myX25519Private!,
      myX25519PublicKey: _myX25519Public!,
      peerX25519PublicKey: answerHandshake.x25519PublicKey,
      peerEd25519PublicKey: answerHandshake.ed25519PublicKey,
    );
    _sharedSecret = r.sharedSecret;
    _peer = _makePeer(answerHandshake.ed25519PublicKey, r.peerFingerprint);
    await _p2p.setRemoteAnswer(String.fromCharCodes(answerHandshake.sdp));
  }

  // ─── Bob: 响应连接 ─────────────────────────────────

  Future<String> createAnswer(String encodedOffer) async {
    _setPhase(SessionPhase.handshaking);
    final offerHandshake = HandshakePayload.decode(_base64UrlDecode(encodedOffer));
    if (!await _keyExchange.verifyHandshake(offerHandshake)) {
      _setPhase(SessionPhase.failed);
      throw StateError('签名验证失败');
    }
    final answerSdp = await _p2p.createAnswer(String.fromCharCodes(offerHandshake.sdp));
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
    _encodedPayload = _base64UrlEncode(result.payload.encode());
    _setPhase(SessionPhase.answerCreated);
    return _encodedPayload!;
  }

  // ─── 消息 ──────────────────────────────────────────

  Future<void> sendTextMessage(String id, String text) async {
    if (_sharedSecret == null) throw StateError('会话未就绪');
    final ct = await _symmetric.encrypt(sharedSecret: _sharedSecret!, plaintext: Uint8List.fromList(utf8.encode('MSG|$id|$text')));
    await _p2p.sendMessage(ct);
  }

  void _handleP2PMessage(Uint8List encrypted) {
    if (_sharedSecret == null) return;
    _symmetric.decrypt(sharedSecret: _sharedSecret!, encrypted: encrypted).then((pt) {
      final text = utf8.decode(pt);
      if (text.startsWith('MSG|')) {
        final parts = text.split('|');
        final id = parts.length > 1 ? parts[1] : DateTime.now().microsecondsSinceEpoch.toRadixString(36);
        final body = parts.length > 2 ? parts.sublist(2).join('|') : '';
        onMessageReceived?.call(ChatMessage(id: id, text: body, timestamp: DateTime.now(), direction: MessageDirection.received));
      } else if (text.startsWith('__DEL__|')) {
        onDeleteRequest?.call(ChatMessage.received(text.substring(8), raw: encrypted));
      } else if (text == '__CLR__') {
        onClearRequest?.call();
      } else {
        onMessageReceived?.call(ChatMessage.received(text, raw: encrypted));
      }
    }).catchError((_) {});
  }

  Future<void> sendDeleteRequest(String messageId) async {
    if (_sharedSecret == null) return;
    final ct = await _symmetric.encrypt(sharedSecret: _sharedSecret!, plaintext: Uint8List.fromList(utf8.encode('__DEL__|$messageId')));
    await _p2p.sendMessage(ct);
  }

  Future<void> sendClearRequest() async {
    if (_sharedSecret == null) return;
    final ct = await _symmetric.encrypt(sharedSecret: _sharedSecret!, plaintext: Uint8List.fromList(utf8.encode('__CLR__')));
    await _p2p.sendMessage(ct);
  }

  void _handleP2PStateChange(P2PConnectionState state) {
    if (state == P2PConnectionState.connected) {
      if (_peer != null && _sharedSecret != null) { _peer!.isConnected = true; onPeerConnected?.call(_peer!); }
      _setPhase(SessionPhase.ready);
    } else if (state == P2PConnectionState.failed || state == P2PConnectionState.disconnected) {
      if (_phase == SessionPhase.ready || _phase == SessionPhase.handshaking) _setPhase(SessionPhase.failed);
    }
  }

  void _setPhase(SessionPhase p) { _phase = p; onPhaseChanged?.call(p); }

  Peer _makePeer(Uint8List pk, Uint8List fp) {
    final h = fp.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
    return Peer(id: h.replaceAll(':', ''), displayName: h, fingerprint: fp, ed25519PublicKey: pk, isConnected: true);
  }

  Future<void> dispose() async => await _p2p.dispose();

  // ─── Base64 + Gzip ────────────────────────────────

  static String _base64UrlEncode(Uint8List data) {
    return _toBase64(Uint8List.fromList(gzip.encode(data))).replaceAll('+', '-').replaceAll('/', '_').replaceAll('=', '');
  }

  static Uint8List _base64UrlDecode(String s) {
    var b = s.replaceAll('-', '+').replaceAll('_', '/');
    while (b.length % 4 != 0) b += '=';
    return Uint8List.fromList(gzip.decode(_fromBase64(b)));
  }

  static String _toBase64(Uint8List d) {
    const c = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final o = StringBuffer();
    for (int i = 0; i < d.length; i += 3) {
      final b0 = d[i], b1 = i + 1 < d.length ? d[i + 1] : 0, b2 = i + 2 < d.length ? d[i + 2] : 0;
      o.write(c[(b0 >> 2) & 0x3F]); o.write(c[((b0 << 4) | (b1 >> 4)) & 0x3F]);
      o.write(c[((b1 << 2) | (b2 >> 6)) & 0x3F]); o.write(c[b2 & 0x3F]);
    }
    final m = d.length % 3, r = o.toString();
    if (m == 1) return '${r.substring(0, r.length - 2)}==';
    if (m == 2) return '${r.substring(0, r.length - 1)}=';
    return r;
  }

  static Uint8List _fromBase64(String b) {
    const c = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final l = <int, int>{}; for (int i = 0; i < c.length; i++) l[c.codeUnitAt(i)] = i;
    final s = b.replaceAll(RegExp(r'[^A-Za-z0-9+/]'), '');
    int p = 0; if (s.isNotEmpty && s[s.length - 1] == '=') p++; if (s.length > 1 && s[s.length - 2] == '=') p++;
    final o = Uint8List(s.length * 6 ~/ 8 - p); int j = 0;
    for (int i = 0; i < s.length; i += 4) {
      final t = (l[s.codeUnitAt(i)]! << 18) | (l[s.codeUnitAt(i + 1)]! << 12) |
          ((i + 2 < s.length ? l[s.codeUnitAt(i + 2)]! : 0) << 6) | (i + 3 < s.length ? l[s.codeUnitAt(i + 3)]! : 0);
      if (j < o.length) o[j++] = (t >> 16) & 0xFF;
      if (j < o.length) o[j++] = (t >> 8) & 0xFF;
      if (j < o.length) o[j++] = t & 0xFF;
    }
    return o;
  }
}
