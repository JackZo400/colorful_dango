/// 局域网 UDP 发现 (224.0.0.200:5454)
library;

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class DiscoveredPeer {
  final String fingerprint;
  DiscoveredPeer({required this.fingerprint});
}

class LanDiscovery {
  static const _addr = '224.0.0.200';
  static const _port = 5454;
  static const _tag = 'DANGO';

  RawDatagramSocket? _socket;
  Timer? _timer;
  final _peers = <String, DiscoveredPeer>{};
  String? _myFp;
  int _retries = 0;

  final _onFound = StreamController<DiscoveredPeer>.broadcast();
  final _onData = StreamController<String>.broadcast();
  Stream<DiscoveredPeer> get onFound => _onFound.stream;
  Stream<String> get onData => _onData.stream;
  bool get active => _socket != null;

  Future<bool> start(String fp) async {
    _myFp = fp; _retries = 0;
    return _bind();
  }

  Future<bool> _bind() async {
    try {
      _socket?.close();
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, _port)
          .timeout(const Duration(seconds: 2));
      _socket!.multicastLoopback = true;
      _socket!.joinMulticast(InternetAddress(_addr));
      _socket!.listen((e) { try {
        if (e != RawSocketEvent.read) return;
        final d = _socket?.receive(); if (d == null) return;
        final m = utf8.decode(d.data);
        if (m.startsWith('$_tag|H|')) {
          final fp = m.substring(_tag.length + 3);
          if (fp != _myFp && !_peers.containsKey(fp)) {
            _peers[fp] = DiscoveredPeer(fingerprint: fp);
            _onFound.add(_peers[fp]!);
          }
        } else if (m.startsWith('$_tag|D|')) {
          _onData.add(m.substring(_tag.length + 3));
        }
      } catch (_) {} });
      _broadcast();
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 3), (_) => _broadcast());
      debugPrint('[LAN] OK');
      return true;
    } catch (e) {
      debugPrint('[LAN] fail: $e');
      if (_retries++ < 2) return _bind();
      return false;
    }
  }

  void _broadcast() {
    if (_myFp == null || _socket == null) return;
    _socket!.send(utf8.encode('$_tag|H|$_myFp'), InternetAddress(_addr), _port);
  }

  void sendSignaling(String data) {
    if (_socket == null) return;
    _socket!.send(utf8.encode('$_tag|D|$data'), InternetAddress(_addr), _port);
  }

  void stop() { _timer?.cancel(); _socket?.close(); _socket = null; _peers.clear(); }
}
