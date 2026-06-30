/// WebRTC P2P 连接管理器
library;

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
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
      'chat',
      RTCDataChannelInit()..negotiated = true..id = 0,
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
    // 协商模式：双方都创建 id=0 的通道
    _dataChannel = await _pc!.createDataChannel(
      'chat',
      RTCDataChannelInit()..negotiated = true..id = 0,
    );
    _setupDataChannel(_dataChannel!);
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    await _waitForIceGathering();
    _setState(P2PConnectionState.connecting);
    final desc = await _pc!.getLocalDescription();
    if (desc == null) throw StateError('无法获取本地 SDP');
    return desc.sdp!;
  }

  // ─── 消息 ──────────────────────────────────────────────

  Future<void> sendMessage(Uint8List encryptedMessage) async {
    final ch = _dataChannel ?? _remoteDataChannel;
    // Wait up to 5 seconds for channel to open
    for (int i = 0; i < 25; i++) {
      if (ch != null && ch.state == RTCDataChannelState.RTCDataChannelOpen) {
        ch.send(RTCDataChannelMessage.fromBinary(encryptedMessage));
        return;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }
    throw StateError('DataChannel 未就绪 (timeout)');
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
    debugPrint('[P2P] _init done, STUN: ${_iceServers.length} servers');

    _pc!.onDataChannel = (channel) {
      debugPrint('[P2P] remote DataChannel (ignored, using negotiated)');
    };

    _pc!.onIceConnectionState = (state) {
      debugPrint('[P2P] ICE: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        if (_state != P2PConnectionState.connected) _setState(P2PConnectionState.connected);
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        if (_state != P2PConnectionState.connected) _setState(P2PConnectionState.failed);
      }
    };

    _pc!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        if (_state != P2PConnectionState.connected) _setState(P2PConnectionState.failed);
      }
    };
  }

  void _setupDataChannel(RTCDataChannel channel) {
    channel.onMessage = (message) {
      if (message.isBinary && onMessageReceived != null) {
        onMessageReceived!(message.binary);
      }
    };
    channel.onDataChannelState = (state) {
      debugPrint('[P2P] DataChannel state: $state');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        _setState(P2PConnectionState.connected);
      }
    };
  }

  Future<void> _waitForIceGathering() async {
    final pc = _pc; if (pc == null) return;
    if (pc.iceGatheringState == RTCIceGatheringState.RTCIceGatheringStateComplete) return;
    final c = Completer<void>();
    pc.onIceGatheringState = (s) { if (s == RTCIceGatheringState.RTCIceGatheringStateComplete && !c.isCompleted) c.complete(); };
    Timer(const Duration(seconds: 3), () { if (!c.isCompleted) c.complete(); });
    await c.future;
  }

  void _setState(P2PConnectionState s) {
    if (_state != s) {
      _state = s;
      onStateChanged?.call(s);
    }
  }
}
