/// 对等端持久化存储
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/peer.dart';

class PeerStorage {
  static const _key = 'saved_peers';

  static Future<List<Peer>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getStringList(_key) ?? [];
    return json.map((s) => _fromJson(jsonDecode(s) as Map<String, dynamic>)).toList();
  }

  static Future<void> save(Peer peer) async {
    final list = await loadAll();
    list.removeWhere((p) => p.id == peer.id);
    list.add(peer);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, list.map((p) => jsonEncode(_toJson(p))).toList());
  }

  static Future<void> remove(String peerId) async {
    final list = await loadAll();
    list.removeWhere((p) => p.id == peerId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, list.map((p) => jsonEncode(_toJson(p))).toList());
  }

  static Map<String, dynamic> _toJson(Peer p) => {
    'id': p.id,
    'displayName': p.displayName,
    'fingerprint': base64Encode(p.fingerprint),
    'ed25519PublicKey': base64Encode(p.ed25519PublicKey),
  };

  static Peer _fromJson(Map<String, dynamic> j) => Peer(
    id: j['id'] as String,
    displayName: j['displayName'] as String,
    fingerprint: base64Decode(j['fingerprint'] as String),
    ed25519PublicKey: base64Decode(j['ed25519PublicKey'] as String),
    isConnected: false,
  );
}
