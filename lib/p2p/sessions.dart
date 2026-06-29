library;
import 'session_manager.dart';
import '../models/peer.dart';
import '../models/message.dart';
import '../models/message_store.dart';

class Sessions {
  static final Map<String, _Entry> _map = {};
  static void Function(String id, bool online)? onStatusChanged;

  static void put(Peer peer, SecureSession session) {
    final id = peer.id;
    final old = _map[id];
    // dispose old session, keep messages
    old?.session.onMessageReceived = null;
    old?.session.onDeleteRequest = null;
    old?.session.onClearRequest = null;
    old?.session.dispose();
    final entry = _Entry(peer: peer, session: session);
    _map[id] = entry;
    // reuse messages from old entry, or load from store
    if (old != null && old.messages.isNotEmpty) {
      entry.messages = old.messages;
    } else {
      MessageStore.load(id).then((msgs) { if (_map[id] == entry) entry.messages = msgs; });
    }
    session.onMessageReceived = (m) { entry.messages.add(m); MessageStore.save(id, entry.messages); entry.onNewMessage?.call(m); };
    session.onDeleteRequest = (m) {
      final idx = entry.messages.indexWhere((x) => x.id == m.text);
      if (idx >= 0) { entry.messages[idx] = entry.messages[idx].copyRecalled(); MessageStore.save(id, entry.messages); entry.onRecall?.call(entry.messages[idx]); }
    };
    session.onClearRequest = () { entry.messages.clear(); MessageStore.clear(id); entry.onClear?.call(); };
    session.onPhaseChanged = (p) {
      if (p == SessionPhase.failed || p == SessionPhase.idle) onStatusChanged?.call(id, false);
      if (p == SessionPhase.ready) onStatusChanged?.call(id, true);
    };
  }

  static SecureSession? get(Peer peer) => _map[peer.id]?.session;
  static SecureSession? getById(String id) => _map[id]?.session;
  static bool isOnline(Peer peer) => _map[peer.id]?.session.isReady == true;

  static void setHandlers(Peer peer, {void Function(ChatMessage)? onNew, void Function(ChatMessage)? onRecall, void Function()? onClear}) {
    final e = _map[peer.id]; if (e == null) return;
    e.onNewMessage = onNew; e.onRecall = onRecall; e.onClear = onClear;
    if (onNew != null) for (final m in e.messages) onNew(m);
  }

  static Future<void> send(Peer peer, String text, {String? id}) async {
    final e = _map[peer.id]; if (e == null) return;
    final m = ChatMessage(id: id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36), text: text, timestamp: DateTime.now(), direction: MessageDirection.sent);
    await MessageStore.save(peer.id, e.messages); e.onNewMessage?.call(m);
  }

  static Future<void> recall(Peer peer, ChatMessage msg) async {
    final e = _map[peer.id]; if (e == null) return;
    final idx = e.messages.indexWhere((x) => x.id == msg.id);
    if (idx >= 0) { e.messages[idx] = msg.copyRecalled(); await MessageStore.save(peer.id, e.messages); e.onRecall?.call(e.messages[idx]); }
  }

  static void remove(Peer peer) { _map.remove(peer.id)?.session.dispose(); }
  static void removeAll() { for (final e in _map.values) e.session.dispose(); _map.clear(); }
}

class _Entry {
  final Peer peer; final SecureSession session;
  List<ChatMessage> messages = [];
  void Function(ChatMessage)? onNewMessage;
  void Function(ChatMessage)? onRecall;
  void Function()? onClear;
  _Entry({required this.peer, required this.session});
}
