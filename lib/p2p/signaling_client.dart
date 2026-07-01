/// WebSocket 信令客户端 — 支持消息中继 (RELAY)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class SignalingClient {
  WebSocket? _ws;
  String? _fp;
  final _onPeerOnline = StreamController<String>.broadcast();
  final _onPeerOffline = StreamController<String>.broadcast();
  final _onOffer = StreamController<({String from, String sdp})>.broadcast();
  final _onAnswer = StreamController<({String from, String sdp})>.broadcast();
  final _onRelay = StreamController<({String from, String data})>.broadcast();

  Stream<String> get onPeerOnline => _onPeerOnline.stream;
  Stream<String> get onPeerOffline => _onPeerOffline.stream;
  Stream<({String from, String sdp})> get onOffer => _onOffer.stream;
  Stream<({String from, String sdp})> get onAnswer => _onAnswer.stream;
  Stream<({String from, String data})> get onRelay => _onRelay.stream;
  bool get connected => _ws?.readyState == WebSocket.open;

  List<String> _onlinePeers = [];
  List<String> get onlinePeers => List.unmodifiable(_onlinePeers);

  String? serverUrl;
  static String? cachedUrl;

  Future<bool> connect(String fingerprint, {String? url}) async {
    _fp = fingerprint;
    serverUrl = url ?? 'ws://localhost:8765';
    cachedUrl = serverUrl;
    try {
      _ws = await WebSocket.connect(serverUrl!).timeout(const Duration(seconds: 8));
      _ws!.add(utf8.encode('REG|$fingerprint'));
      _ws!.listen((d) {
        final m = utf8.decode(d is List<int> ? d : []);
        if (m.startsWith('ON|')) {
          final fp = m.substring(3);
          if (!_onlinePeers.contains(fp)) { _onlinePeers.add(fp); _onPeerOnline.add(fp); }
        } else if (m.startsWith('OFF|')) {
          final fp = m.substring(4);
          _onlinePeers.remove(fp); _onPeerOffline.add(fp);
        } else if (m.startsWith('OFFER|')) {
          final parts = m.split('|');
          if (parts.length >= 2) _onOffer.add((from: parts[1], sdp: parts.sublist(2).join('|')));
        } else if (m.startsWith('ANSWER|')) {
          final parts = m.split('|');
          if (parts.length >= 2) _onAnswer.add((from: parts[1], sdp: parts.sublist(2).join('|')));
        } else if (m.startsWith('RELAY|')) {
          final parts = m.split('|');
          if (parts.length >= 2) _onRelay.add((from: parts[1], data: parts.sublist(2).join('|')));
        }
      }, onDone: () { _onlinePeers.clear(); _ws = null; });
      return true;
    } catch (e) {
      debugPrint('[Signal] connect failed: $e');
      return false;
    }
  }

  void sendOffer(String targetFp, String sdp) => _ws?.add(utf8.encode('OFFER|$targetFp|$sdp'));
  void sendAnswer(String targetFp, String sdp) => _ws?.add(utf8.encode('ANSWER|$targetFp|$sdp'));
  void sendRelay(String targetFp, String data) => _ws?.add(utf8.encode('RELAY|$targetFp|$data'));

  void disconnect() { _ws?.close(); _ws = null; _onlinePeers.clear(); }
  void dispose() { disconnect(); _onPeerOnline.close(); _onPeerOffline.close(); _onOffer.close(); _onAnswer.close(); _onRelay.close(); }
}
