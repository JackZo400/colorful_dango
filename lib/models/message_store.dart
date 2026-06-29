/// 消息持久化存储 — 退出聊天也能收消息
library;

import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';

class MessageStore {
  static Future<void> save(String peerId, List<ChatMessage> msgs) async {
    final prefs = await SharedPreferences.getInstance();
    final json = msgs.map((m) => jsonEncode({
      'id': m.id, 'text': m.text, 'dir': m.direction.name,
      'ts': m.timestamp.toIso8601String(),
    })).toList();
    await prefs.setStringList('msgs_$peerId', json);
  }

  static Future<List<ChatMessage>> load(String peerId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getStringList('msgs_$peerId') ?? [];
    return json.map((s) {
      final m = jsonDecode(s) as Map<String, dynamic>;
      return ChatMessage(
        id: m['id'] as String,
        text: m['text'] as String,
        direction: m['dir'] == 'sent' ? MessageDirection.sent : MessageDirection.received,
        timestamp: DateTime.parse(m['ts'] as String),
      );
    }).toList();
  }

  static Future<void> clear(String peerId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('msgs_$peerId');
  }
}
