/// 连接结果 — 同时返回 Peer 和 SecureSession
library;

import 'peer.dart';
import '../p2p/session_manager.dart';

class ConnectionResult {
  final Peer peer;
  final SecureSession session;

  const ConnectionResult({
    required this.peer,
    required this.session,
  });
}
