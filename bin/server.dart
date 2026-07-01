/// 三彩丸子信令中继服务器
/// 运行: dart run bin/server.dart
library;

import 'dart:io';
import 'dart:convert';

void main() async {
  final server = await HttpServer.bind(InternetAddress.anyIPv4, 8765);
  print('信号服务器已启动: ws://0.0.0.0:8765');

  await for (final req in server) {
    if (WebSocketTransformer.isUpgradeRequest(req)) {
      WebSocketTransformer.upgrade(req).then((ws) {
        print('新连接: ${req.connectionInfo?.remoteAddress}');
        String fp = '';
        ws.listen(
          (data) {
            try {
              final msg = utf8.decode(data is List<int> ? data : []);
              if (msg.startsWith('REG|')) {
                fp = msg.substring(4);
                clients[fp] = ws;
                broadcast('ON|$fp', except: ws);
                // 发送当前在线列表
                for (final f in clients.keys) {
                  if (f != fp) ws.add(utf8.encode('ON|$f'));
                }
              } else if (msg.startsWith('OFFER|')) {
                final parts = msg.split('|');
                final target = parts[1];
                final sdp = parts.sublist(2).join('|');
                clients[target]?.add(utf8.encode('OFFER|${fp}|$sdp'));
              } else if (msg.startsWith('ANSWER|')) {
                final parts = msg.split('|');
                final target = parts[1];
                final sdp = parts.sublist(2).join('|');
                clients[target]?.add(utf8.encode('ANSWER|${fp}|$sdp'));
              } else if (msg.startsWith('RELAY|')) {
                final parts = msg.split('|');
                final target = parts[1];
                final data = parts.sublist(2).join('|');
                clients[target]?.add(utf8.encode('RELAY|${fp}|$data'));
              }
            } catch (_) {}
          },
          onDone: () {
            if (fp.isNotEmpty) { clients.remove(fp); broadcast('OFF|$fp'); }
            print('断开: $fp');
          },
        );
      });
    } else {
      req.response.statusCode = 400;
      req.response.close();
    }
  }
}

final Map<String, WebSocket> clients = {};

void broadcast(String msg, {WebSocket? except}) {
  final data = utf8.encode(msg);
  final dead = <String>[];
  for (final e in clients.entries) {
    if (e.value == except) continue;
    try { e.value.add(data); } catch (_) { dead.add(e.key); }
  }
  for (final k in dead) { clients.remove(k); }
}
