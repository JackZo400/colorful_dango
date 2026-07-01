/// WebRTC P2P 连接 —— 参考 flutter_webrtc 官方示例重写
library;

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class P2PConnection {
  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  Completer<void> _ready = Completer<void>();
  void Function(Uint8List)? onMessage;
  void Function()? onClose;

  bool get isOpen => _dc?.state == RTCDataChannelState.RTCDataChannelOpen;
  Future<void> get ready => _ready.future;

  /// 发送消息 — 等通道就绪
  Future<void> send(Uint8List data) async {
    await _ready.future;
    if (_dc?.state != RTCDataChannelState.RTCDataChannelOpen) {
      await Future.delayed(const Duration(milliseconds: 500));
    }
    _dc!.send(RTCDataChannelMessage.fromBinary(data));
  }

  /// 创建 Offer（发起方）
  Future<String> createOffer() async {
    await _close();
    _pc = await createPeerConnection(_iceConfig);
    _dc = await _pc!.createDataChannel('chat', RTCDataChannelInit());
    _setupChannel(_dc!);

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    await _gatherCandidates();
    return (await _pc!.getLocalDescription())!.sdp!;
  }

  /// 接收 Offer 并创建 Answer（应答方）
  Future<String> createAnswer(String remoteSdp) async {
    await _close();
    _pc = await createPeerConnection(_iceConfig);
    _pc!.onDataChannel = (ch) { _dc = ch; _setupChannel(ch); };
    await _pc!.setRemoteDescription(RTCSessionDescription(remoteSdp, 'offer'));
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    await _gatherCandidates();
    return (await _pc!.getLocalDescription())!.sdp!;
  }

  /// 设置远端 Answer
  Future<void> setRemoteAnswer(String sdp) async {
    await _pc?.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
  }

  /// 关闭
  Future<void> close() => _close();
  Future<void> _close() async {
    try { await _dc?.close(); } catch (_) {}
    try { await _pc?.close(); } catch (_) {}
    _dc = null; _pc = null;
    _ready = Completer<void>(); // 新连接必须重置
  }

  // ─── 内部 ───

  static const _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
    'iceTransportPolicy': 'all',
  };

  void _setupChannel(RTCDataChannel ch) {
    ch.onDataChannelState = (s) {
      if (s == RTCDataChannelState.RTCDataChannelOpen && !_ready.isCompleted) {
        _ready.complete();
      } else if (s == RTCDataChannelState.RTCDataChannelClosed || s == RTCDataChannelState.RTCDataChannelClosing) {
        onClose?.call();
      }
    };
    ch.onMessage = (m) {
      if (m.isBinary && onMessage != null) onMessage!(m.binary);
    };
  }

  Future<void> _gatherCandidates() async {
    if (_pc!.iceGatheringState == RTCIceGatheringState.RTCIceGatheringStateComplete) return;
    final c = Completer<void>();
    _pc!.onIceGatheringState = (s) {
      if (s == RTCIceGatheringState.RTCIceGatheringStateComplete && !c.isCompleted) c.complete();
    };
    Timer(const Duration(seconds: 5), () { if (!c.isCompleted) c.complete(); });
    await c.future;
  }
}
