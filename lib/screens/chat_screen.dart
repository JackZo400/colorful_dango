/// 聊天页面 — 双语
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import '../l10n.dart';
import '../models/message.dart';
import '../models/peer.dart';
import '../p2p/session_manager.dart';
import '../p2p/sessions.dart';
import '../models/message_store.dart';

class ChatScreen extends StatefulWidget {
  final Peer peer;
  final SecureSession? session;
  const ChatScreen({super.key, required this.peer, this.session});
  @override State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  SecureSession? _session;
  final List<ChatMessage> _messages = [];
  final _ctrl = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollCtrl = ScrollController();
  bool _ready = false;
  bool _peerTyping = false;
  Timer? _typingTimer;

  @override void initState() {
    super.initState();
    _session = widget.session;
    if (_session != null) {
      _ready = _session!.isReady;
      _session!.onPhaseChanged = (p) { if (mounted) setState(() => _ready = p == SessionPhase.ready); };
      _session!.onTyping = (v) { if (mounted) setState(() => _peerTyping = v); };
      _ctrl.addListener(_onTyping);
      Sessions.setHandlers(widget.peer,
        onNew: (m) { if (mounted) { setState(() => _messages.add(m)); _scrollToBottom(); } },
        onRecall: (m) { if (mounted) setState(() { final idx = _messages.indexWhere((x) => x.id == m.id); if (idx >= 0) _messages[idx] = m; }); },
        onClear: () { if (mounted) setState(() => _messages.clear()); },
      );
    }
  }

  @override void dispose() { _ctrl.dispose(); _focusNode.dispose(); _scrollCtrl.dispose(); super.dispose(); }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  void _onTyping() {
    if (!_ready) return;
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 500), () { /* auto-stops after 2s of no typing */ });
    _session!.sendTyping(_ctrl.text.isNotEmpty);
  }

  void _clearChat() {
    final l = L10n.instance;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text(l.get('clear_chat')), content: Text(l.get('clear_confirm')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.get('cancel'))),
        FilledButton(onPressed: () { Navigator.pop(ctx); _session?.sendClearRequest(); MessageStore.clear(widget.peer.id); Sessions.clearMessages(widget.peer.id); if (mounted) setState(() => _messages.clear()); }, child: Text(l.get('clear')))]));
  }

  void _showPopup(ChatMessage msg, Offset position) {
    if (msg.recalled) return;
    final l = L10n.instance;
    showMenu(context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem(child: _menuItem(Icons.copy, l.get('copy')), onTap: () => Clipboard.setData(ClipboardData(text: msg.text))),
        PopupMenuItem(child: _menuItem(Icons.format_quote, l.get('quote')), onTap: () { _ctrl.text = '\u300C ${l.get('quote')} \u300D${msg.text}\n${_ctrl.text}'; _ctrl.selection = TextSelection.collapsed(offset: 0); _focusNode.requestFocus(); }),
        if (msg.direction == MessageDirection.sent)
          PopupMenuItem(child: _menuItem(Icons.undo, l.get('recall'), color: Colors.orange), onTap: () { _session?.sendDeleteRequest(msg.id); Sessions.recall(widget.peer, msg); }),
      ]);
  }

  Widget _menuItem(IconData icon, String text, {Color? color}) =>
    ListTile(leading: Icon(icon, size: 20, color: color), title: Text(text, style: color != null ? TextStyle(color: color) : null), dense: true, contentPadding: EdgeInsets.zero);

  @override Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = L10n.instance;
    final isDesktop = Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    return Scaffold(
      appBar: AppBar(titleSpacing: 4, title: Row(children: [
        CircleAvatar(radius: 16, backgroundColor: cs.primary, child: Text(widget.peer.shortFingerprint.substring(0,2), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
        const SizedBox(width: 10), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.peer.displayName, style: const TextStyle(fontSize: 15)),
          Text(_peerTyping ? '对方正在输入...' : _ready ? l.get('encrypted') : l.get('connecting'), style: TextStyle(fontSize: 11, color: _peerTyping ? Colors.green : _ready ? Colors.green.shade400 : Colors.orange)),
        ])]),
        actions: [
          if (_ready) IconButton(icon: const Icon(Icons.delete_sweep), tooltip: l.get('clear_chat'), onPressed: _clearChat),
          if (_ready) const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.lock, color: Colors.green, size: 16)),
        ]),
      body: Column(children: [
        Expanded(child: _messages.isEmpty
          ? Center(child: Text(_ready ? l.get('first_msg') : l.get('waiting'), style: TextStyle(color: cs.outline)))
          : ListView.builder(controller: _scrollCtrl, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), itemCount: _messages.length,
              itemBuilder: (_, i) {
                final msg = _messages[i];
                final bubble = _Bubble(msg: msg);
                if (isDesktop) return Listener(onPointerDown: (e) { if (e.buttons == kSecondaryMouseButton) _showPopup(msg, e.position); }, child: bubble);
                return GestureDetector(onLongPressStart: (d) => _showPopup(msg, d.globalPosition), child: bubble);
              })),
        _InputBar(ctrl: _ctrl, focusNode: _focusNode, enabled: _ready, onSend: _send, onPickImage: _pickFile),
      ]));
  }

  Future<void> _pickFile() async {
    if (!_ready) return;
    final result = await FilePicker.platform.pickFiles();
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;
    await _session!.sendFile(file.bytes!, file.name);
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    await Sessions.send(widget.peer, '[文件: ${file.name}], id: id);
    _scrollToBottom();
  }

  Future<void> _send(String t) async {
    if (t.trim().isEmpty || !_ready) return;
    try {
      final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      await _session!.sendTextMessage(id, t.trim());
      await Sessions.send(widget.peer, t.trim(), id: id);
      _ctrl.clear(); _focusNode.requestFocus(); _scrollToBottom();
    } catch (e) {
      final l = L10n.instance;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${l.get('send_failed')}: $e'), backgroundColor: Colors.red));
    }
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage msg; const _Bubble({required this.msg});
  @override Widget build(BuildContext context) {
    final sent = msg.direction == MessageDirection.sent;
    final cs = Theme.of(context).colorScheme;
    final l = L10n.instance;
    if (msg.recalled) return Align(alignment: sent ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest.withAlpha(60), borderRadius: BorderRadius.circular(12)),
        child: Text(sent ? l.get('you_recalled') : l.get('peer_recalled'), style: TextStyle(fontSize: 12, color: cs.outline, ))));
    return Align(alignment: sent ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(color: sent ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(sent ? 16 : 4), bottomRight: Radius.circular(sent ? 4 : 16))),
        child: Column(crossAxisAlignment: sent ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
          SelectableText(msg.text, style: TextStyle(fontSize: 15, color: sent ? cs.onPrimaryContainer : cs.onSurface)),
          const SizedBox(height: 3),
          Text('${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}',
            style: TextStyle(fontSize: 10, color: (sent ? cs.onPrimaryContainer : cs.onSurface).withAlpha(100))),
        ])));
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController ctrl; final FocusNode focusNode; final bool enabled;
  final void Function(String) onSend; final VoidCallback? onPickImage;
  const _InputBar({required this.ctrl, required this.focusNode, required this.enabled, required this.onSend, this.onPickImage});
  @override Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = L10n.instance;
    return Container(padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      decoration: BoxDecoration(color: cs.surface, boxShadow: [BoxShadow(color: Colors.black.withAlpha(12), blurRadius: 4, offset: const Offset(0, -1))]),
      child: SafeArea(child: Row(children: [
        if (onPickImage != null) IconButton(icon: const Icon(Icons.attach_file), onPressed: enabled ? onPickImage : null, tooltip: '文件''),
        Expanded(child: TextField(controller: ctrl, focusNode: focusNode, enabled: enabled,
          decoration: InputDecoration(hintText: enabled ? l.get('input_msg') : l.get('waiting'), filled: true,
            fillColor: cs.surfaceContainerHighest.withAlpha(80), border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10)),
          textInputAction: TextInputAction.send, onSubmitted: onSend)),
        const SizedBox(width: 8),
        IconButton.filled(onPressed: enabled ? () => onSend(ctrl.text) : null, icon: const Icon(Icons.send_rounded, size: 18),
          style: IconButton.styleFrom(backgroundColor: cs.primary, foregroundColor: cs.onPrimary)),
      ])));
  }
}
