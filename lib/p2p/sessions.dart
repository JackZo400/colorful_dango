library;
import 'session_manager.dart';
import '../models/peer.dart';
import '../models/message.dart';
import '../models/message_store.dart';

class Sessions {
  static final Map<String, _Entry> _map = {};
  static void Function(String id, bool online)? onStatusChanged;

  static Future<void> put(Peer peer, SecureSession session) async {
    final id = peer.id;
    final old = _map[id];
    old?.session.close();
    final msgs = old != null ? old.messages : await MessageStore.load(id);
    final entry = _Entry(peer: peer, session: session);
    entry.messages = msgs.toList();
    _map[id] = entry;

    session.onMessageReceived = (m) { entry.messages.add(m); entry.lastText = m.text; _save(id, entry); entry.onNewMessage?.call(m); };
    session.onDeleteRequest = (m) {
      final idx = entry.messages.indexWhere((x) => x.id == m.text);
      if (idx >= 0) { entry.messages[idx] = entry.messages[idx].copyRecalled(); _save(id, entry); entry.onRecall?.call(entry.messages[idx]); }
    };
    session.onClearRequest = () async { entry.messages.clear(); entry.lastText = null; await MessageStore.clear(id); entry.onClear?.call(); };
    session.onPhaseChanged = (p) {
      if (p == SessionPhase.failed || p == SessionPhase.idle) onStatusChanged?.call(id, false);
      if (p == SessionPhase.ready) onStatusChanged?.call(id, true);
    };
    if (session.isReady) onStatusChanged?.call(id, true);
  }

  static SecureSession? get(Peer peer) => _map[peer.id]?.session;
  static SecureSession? getById(String id) => _map[id]?.session;
  static bool isOnline(Peer peer) => _map[peer.id]?.session.isReady == true;
  static String? lastText(String id) => _map[id]?.lastText;

  static void setHandlers(Peer peer, {void Function(ChatMessage)? onNew, void Function(ChatMessage)? onRecall, void Function()? onClear}) {
    final e = _map[peer.id]; if (e == null) return;
    e.onNewMessage = onNew; e.onRecall = onRecall; e.onClear = onClear;
    if (onNew != null) for (final m in e.messages) onNew(m);
  }

  static Future<void> send(Peer peer, String text, {String? id}) async {
    final e = _map[peer.id]; if (e == null) return;
    final m = ChatMessage(id: id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36), text: text, timestamp: DateTime.now(), direction: MessageDirection.sent);
    e.messages.add(m);
    e.lastText = text;
    await _save(peer.id, e);
    e.onNewMessage?.call(m);
  }

  static Future<void> recall(Peer peer, ChatMessage msg) async {
    final e = _map[peer.id]; if (e == null) return;
    final idx = e.messages.indexWhere((x) => x.id == msg.id);
    if (idx >= 0) { e.messages[idx] = msg.copyRecalled(); await _save(peer.id, e); e.onRecall?.call(e.messages[idx]); }
  }

  static void remove(Peer peer) { _map.remove(peer.id)?.session.close(); }
  static void removeAll() { for (final e in _map.values) e.session.close(); _map.clear(); }
  static void clearMessages(String id) { _map[id]?.messages.clear(); }

  static Future<void> _save(String id, _Entry e) => MessageStore.save(id, e.messages);
}

class _Entry {
  final Peer peer; final SecureSession session;
  List<ChatMessage> messages = [];
  String? lastText;
  void Function(ChatMessage)? onNewMessage;
  void Function(ChatMessage)? onRecall;
  void Function()? onClear;
  _Entry({required this.peer, required this.session});
}
