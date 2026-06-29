/// WebRTC P2P 连接管理器
library;

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';

enum P2PConnectionState { disconnected, connecting, connected, failed }

typedef OnMessageReceived = void Function(Uint8List data);
typedef OnStateChanged = void Function(P2PConnectionState state);

class P2PConnectionManager {
  RTCPeerConnection? _pc;
  RTCDataChannel? _dataChannel;
  RTCDataChannel? _remoteDataChannel;
  final List<Map<String, dynamic>> _iceServers;

  P2PConnectionState _state = P2PConnectionState.disconnected;
  OnMessageReceived? onMessageReceived;
  OnStateChanged? onStateChanged;

  P2PConnectionState get state => _state;

  static const _defaultStun = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun.nextcloud.com:3478'},
    {'urls': 'stun:stun.voipbuster.com:3478'},
    {'urls': 'stun:stun.voipstunt.com:3478'},
  ];

  P2PConnectionManager({List<String>? customStunServers})
      : _iceServers = _buildIceServers(customStunServers);

  static List<Map<String, dynamic>> _buildIceServers(List<String>? custom) {
    if (custom != null && custom.isEmpty) return []; // LAN only
    final urls = custom ?? _defaultStun.map((e) => e['urls'] as String).toList();
    return urls.map((u) => {'urls': u}).toList();
  }

  // ─── 发起连接 ──────────────────────────────────────────

  Future<String> createOffer() async {
    await _init();
    _dataChannel = await _pc!.createDataChannel(
      'secure_chat',
      RTCDataChannelInit()..ordered = true..negotiated = false,
    );
    _setupDataChannel(_dataChannel!);
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    await _waitForIceGathering();
    _setState(P2PConnectionState.connecting);
    final desc = await _pc!.getLocalDescription();
    if (desc == null) throw StateError('无法获取本地 SDP');
    return desc.sdp!;
  }

  Future<void> setRemoteAnswer(String sdp) async {
    if (_pc == null) throw StateError('请先调用 createOffer()');
    await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
  }

  // ─── 响应连接 ──────────────────────────────────────────

  Future<String> createAnswer(String remoteOfferSdp) async {
    await _init();
    await _pc!.setRemoteDescription(RTCSessionDescription(remoteOfferSdp, 'offer'));
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    await _waitForIceGathering();
    _setState(P2PConnectionState.connecting);
    final desc = await _pc!.getLocalDescription();
    if (desc == null) throw StateError('无法获取本地 SDP');
    return desc.sdp!;
  }

  // ─── 消息 ──────────────────────────────────────────────

  void sendMessage(Uint8List encryptedMessage) {
    final ch = _dataChannel ?? _remoteDataChannel;
    if (ch == null || ch.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw StateError('DataChannel 未就绪');
    }
    ch.send(RTCDataChannelMessage.fromBinary(encryptedMessage));
  }

  // ─── 生命周期 ──────────────────────────────────────────

  Future<void> disconnect() async {
    try { await _dataChannel?.close(); } catch (_) {}
    try { await _remoteDataChannel?.close(); } catch (_) {}
    try { await _pc?.close(); } catch (_) {}
    _dataChannel = null;
    _remoteDataChannel = null;
    _pc = null;
    _setState(P2PConnectionState.disconnected);
  }

  Future<void> dispose() async => await disconnect();

  // ─── 内部 ──────────────────────────────────────────────

  Future<void> _init() async {
    await disconnect();
    await Future.delayed(const Duration(milliseconds: 300)); // let native cleanup finish
    final config = {
      'iceServers': _iceServers,
      'iceTransportPolicy': 'all',
    };
    _pc = await createPeerConnection(config);

    _pc!.onDataChannel = (channel) {
      _remoteDataChannel = channel;
      _setupDataChannel(channel);
    };

    _pc!.onIceConnectionState = (state) {
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _setState(P2PConnectionState.connected);
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _setState(P2PConnectionState.failed);
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _setState(P2PConnectionState.disconnected);
      }
    };

    _pc!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _setState(P2PConnectionState.failed);
      }
    };
  }

  void _setupDataChannel(RTCDataChannel channel) {
    channel.onMessage = (message) {
      if (message.isBinary && onMessageReceived != null) {
        onMessageReceived!(message.binary);
      }
    };
    // onStateChanged might not exist; use onDataChannelState instead
  }

  Future<void> _waitForIceGathering() async {
    if (_pc == null) return;
    if (_pc!.iceGatheringState == RTCIceGatheringState.RTCIceGatheringStateComplete) {
      return;
    }
    final completer = Completer<void>();
    void handler(state) {
      if (state == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !completer.isCompleted) {
        _pc?.onIceGatheringState = null;
        completer.complete();
      }
    }
    _pc!.onIceGatheringState = handler;
    Timer(const Duration(seconds: 10), () {
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
  }

  void _setState(P2PConnectionState s) {
    if (_state != s) {
      _state = s;
      onStateChanged?.call(s);
    }
  }
}
