/// 消息数据模型
library;

import 'dart:typed_data';

/// 消息方向
enum MessageDirection { sent, received }

/// 聊天消息
class ChatMessage {
  final String id;
  final String text;
  final DateTime timestamp;
  final MessageDirection direction;
  final Uint8List? rawEncrypted;
  final bool recalled;

  const ChatMessage({
    required this.id,
    required this.text,
    required this.timestamp,
    required this.direction,
    this.rawEncrypted,
    this.recalled = false,
  });

  ChatMessage copyRecalled() => ChatMessage(id: id, text: text, timestamp: timestamp, direction: direction, rawEncrypted: rawEncrypted, recalled: true);

  /// 从解密文本创建接收消息
  factory ChatMessage.received(String text, {Uint8List? raw}) {
    return ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      text: text,
      timestamp: DateTime.now(),
      direction: MessageDirection.received,
      rawEncrypted: raw,
    );
  }

  /// 创建已发送消息
  factory ChatMessage.sent(String text) {
    return ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      text: text,
      timestamp: DateTime.now(),
      direction: MessageDirection.sent,
    );
  }
}

/// 信令消息 — 用于二维码/粘贴交换的完整握手负载
class SignalingMessage {
  /// Base64 编码的握手数据
  final String encodedPayload;

  /// 人类可读的会话标识 (前 8 字符)
  final String sessionId;

  const SignalingMessage({
    required this.encodedPayload,
    required this.sessionId,
  });
}
