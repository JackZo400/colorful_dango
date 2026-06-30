/// 添加联系人 — 信令 / 局域网 / 手动 (双语)
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../crypto/identity.dart';
import '../l10n.dart';
import '../models/peer.dart';
import '../models/peer_storage.dart';
import '../p2p/session_manager.dart';
import '../p2p/sessions.dart';
import '../p2p/lan_discovery.dart';
import '../p2p/signaling_client.dart';

class AddContactScreen extends StatefulWidget {
  final CryptoIdentity identity;
  const AddContactScreen({super.key, required this.identity});
  @override State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  @override void initState() { super.initState(); _tab = TabController(length: 3, vsync: this); }
  @override void dispose() { _tab.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final l = L10n.instance;
    return Scaffold(
      appBar: AppBar(title: Text(l.get('add_contact')), bottom: TabBar(controller: _tab, tabs: [
        Tab(icon: const Icon(Icons.cloud), text: l.get('signal_tab')),
        Tab(icon: const Icon(Icons.wifi), text: l.get('lan_tab')),
        Tab(icon: const Icon(Icons.keyboard), text: l.get('manual_tab')),
      ])),
      body: TabBarView(controller: _tab, children: [
        _SignalTab(identity: widget.identity, onDone: (p) => Navigator.pop(context, p)),
        _LanTab(identity: widget.identity, onDone: (p) => Navigator.pop(context, p)),
        _ManualTab(identity: widget.identity, onDone: (p) => Navigator.pop(context, p)),
      ]));
  }
}

class _SignalTab extends StatefulWidget {
  final CryptoIdentity identity; final void Function(Peer) onDone;
  const _SignalTab({required this.identity, required this.onDone});
  @override State<_SignalTab> createState() => _SignalTabState();
}

class _SignalTabState extends State<_SignalTab> {
  final _sig = SignalingClient();
  final _ctrl = TextEditingController(text: SignalingClient.cachedUrl ?? 'ws://');
  final List<DiscoveredPeer> _peers = [];
  bool _on = false, _busy = false;
  String _rawFp = '';
  SecureSession? _pending;

  @override void initState() { super.initState(); _loadFp(); }
  @override void dispose() { _sig.disconnect(); _ctrl.dispose(); super.dispose(); }

  Future<void> _loadFp() async {
    final fp = await IdentityManager().fingerprint(widget.identity);
    if (mounted) setState(() => _rawFp = fp.map((b) => b.toRadixString(16).padLeft(2, '0')).join(''));
  }

  void _toggle() {
    setState(() => _on = true);
    _sig.connect(_rawFp, url: _ctrl.text).then((ok) {
      if (!ok || !mounted) { setState(() => _on = false); return; }
      SignalingClient.cachedUrl = _ctrl.text;
      _sig.onPeerOnline.listen((fp) { if (mounted && !_peers.any((e) => e.fingerprint == fp)) setState(() => _peers.add(DiscoveredPeer(fingerprint: fp))); });
      _sig.onOffer.listen((o) => _accept(o.sdp));
      _sig.onAnswer.listen((a) async { if (_pending != null) { try { await _pending!.acceptAnswer(a.sdp); } catch (_) {} } });
    }).catchError((_) { if (mounted) setState(() => _on = false); });
  }

  void _accept(String sdp) async {
    try {
      final s = SecureSession(identity: widget.identity);
      s.onPeerConnected = (peer) async { await PeerStorage.save(peer); Sessions.put(peer, s); if (mounted) widget.onDone(peer); };
      final a = await s.createAnswer(sdp);
      if (mounted) _sig.sendAnswer(_rawFp, a); else s.close();
    } catch (_) {}
  }

  void _connect(DiscoveredPeer dp) async {
    setState(() => _busy = true);
    _pending = SecureSession(identity: widget.identity);
    _pending!.onPeerConnected = (peer) async { await PeerStorage.save(peer); Sessions.put(peer, _pending!); if (mounted) widget.onDone(peer); };
    try {
      final o = await _pending!.createOffer();
      if (mounted) _sig.sendOffer(dp.fingerprint, o); else { _pending = null; setState(() => _busy = false); }
    } catch (_) { _pending = null; if (mounted) setState(() => _busy = false); }
  }

  @override Widget build(BuildContext context) {
    final l = L10n.instance;
    return Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      if (!_on) ...[
        TextField(controller: _ctrl, decoration: InputDecoration(hintText: 'ws://your-server:8765', border: const OutlineInputBorder())),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _toggle, icon: const Icon(Icons.cloud), label: Text(l.get('connect_server'))),
      ] else ...[
        Row(children: [
          Icon(Icons.cloud_done, color: Colors.green.shade400, size: 18), const SizedBox(width: 8),
          Text(l.get('online_count').replaceAll('{}', '${_peers.length}'), style: const TextStyle(fontSize: 13)),
          const Spacer(), TextButton(onPressed: () { _sig.disconnect(); setState(() { _on = false; _peers.clear(); }); }, child: Text(l.get('disconnect')))]),
        const Divider(),
        Expanded(child: _peers.isEmpty ? Center(child: Text(l.get('waiting_online'), style: const TextStyle(color: Colors.grey))) : ListView(
          children: _peers.map((dp) => ListTile(
            leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.person, color: Colors.white, size: 18)),
            title: Text(dp.fingerprint, style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
            trailing: _busy && _peers.first == dp ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : FilledButton.tonal(child: Text(l.get('connect_btn')), onPressed: () => _connect(dp)))).toList())),
      ],
    ]));
  }
}

class _LanTab extends StatefulWidget {
  final CryptoIdentity identity; final void Function(Peer) onDone;
  const _LanTab({required this.identity, required this.onDone});
  @override State<_LanTab> createState() => _LanTabState();
}

class _LanTabState extends State<_LanTab> {
  final _lan = LanDiscovery();
  final List<DiscoveredPeer> _peers = [];
  bool _on = false, _busy = false;
  String _rawFp = '';
  SecureSession? _pending;

  @override void initState() { super.initState(); _loadFp(); }
  @override void dispose() { _lan.stop(); super.dispose(); }

  Future<void> _loadFp() async {
    final fp = await IdentityManager().fingerprint(widget.identity);
    if (mounted) setState(() => _rawFp = fp.map((b) => b.toRadixString(16).padLeft(2, '0')).join(''));
  }

  void _toggle() {
    setState(() => _on = true);
    _lan.start(_rawFp).then((ok) {
      if (!ok || !mounted) { setState(() => _on = false); return; }
      _lan.onFound.listen((p) { if (mounted && !_peers.any((e) => e.fingerprint == p.fingerprint)) setState(() => _peers.add(p)); });
      _lan.onData.listen((data) async {
        if (_pending != null) { try { await _pending!.acceptAnswer(data); } catch (_) {} return; }
        _accept(data);
      });
    }).catchError((_) { if (mounted) setState(() => _on = false); });
  }

  void _accept(String sdp) async {
    try {
      final s = SecureSession(identity: widget.identity);
      s.onPeerConnected = (peer) async { await PeerStorage.save(peer); Sessions.put(peer, s); if (mounted) widget.onDone(peer); };
      final a = await s.createAnswer(sdp);
      if (mounted) _lan.sendSignaling(a); else s.close();
    } catch (_) {}
  }

  void _connect(DiscoveredPeer dp) async {
    setState(() => _busy = true);
    _pending = SecureSession(identity: widget.identity);
    _pending!.onPeerConnected = (peer) async { await PeerStorage.save(peer); Sessions.put(peer, _pending!); if (mounted) widget.onDone(peer); };
    try {
      final o = await _pending!.createOffer();
      if (mounted) _lan.sendSignaling(o); else { _pending = null; setState(() => _busy = false); }
    } catch (_) { _pending = null; if (mounted) setState(() => _busy = false); }
  }

  @override Widget build(BuildContext context) {
    final l = L10n.instance;
    return Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        const Icon(Icons.info_outline, size: 16, color: Colors.grey), const SizedBox(width: 8),
        Expanded(child: Text(l.get('lan_warning'), style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
      ]))),
      const SizedBox(height: 12),
      if (!_on)
        FilledButton.icon(onPressed: _toggle, icon: const Icon(Icons.wifi), label: Text(l.get('start_scan')))
      else ...[
        Row(children: [
          Icon(Icons.wifi, color: Colors.green.shade400, size: 18), const SizedBox(width: 8),
          Text(l.get('scanning').replaceAll('', ''), style: const TextStyle(fontSize: 13)),
          const Spacer(), TextButton(onPressed: () { _lan.stop(); setState(() { _on = false; _peers.clear(); }); }, child: Text(l.get('stop')))]),
        const Divider(),
        Expanded(child: _peers.isEmpty ? Center(child: Text(l.get('waiting_lan'), style: const TextStyle(color: Colors.grey))) : ListView(
          children: _peers.map((dp) => ListTile(
            leading: const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.person, color: Colors.white, size: 18)),
            title: Text(dp.fingerprint, style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
            trailing: _busy ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : FilledButton.tonal(child: Text(l.get('connect_btn')), onPressed: () => _connect(dp)))).toList())),
      ],
    ]));
  }
}

class _ManualTab extends StatefulWidget {
  final CryptoIdentity identity; final void Function(Peer) onDone;
  const _ManualTab({required this.identity, required this.onDone});
  @override State<_ManualTab> createState() => _ManualTabState();
}

class _ManualTabState extends State<_ManualTab> {
  SecureSession? _session;
  String? _shareData;
  SessionPhase _phase = SessionPhase.idle;
  final _pasteCtrl = TextEditingController();
  bool _loading = false, _showPaste = false;

  @override void initState() { super.initState(); _init(); }
  void _init() { _session?.close(); _session = SecureSession(identity: widget.identity); _session!.onPhaseChanged = (p) { if (mounted) setState(() => _phase = p); }; _session!.onPeerConnected = (peer) async { await PeerStorage.save(peer); Sessions.put(peer, _session!); if (mounted) widget.onDone(peer); }; }
  @override void dispose() { _pasteCtrl.dispose(); super.dispose(); }

  Future<void> _createOffer() async { setState(() => _loading = true);
    try { _shareData = await _session!.createOffer(); Clipboard.setData(ClipboardData(text: _shareData!)); setState(() => _loading = false); } catch (_) { _init(); setState(() => _loading = false); }}

  Future<void> _handleOffer(String data) async { if (data.trim().isEmpty) return; setState(() => _loading = true);
    try { _shareData = await _session!.createAnswer(data.trim()); Clipboard.setData(ClipboardData(text: _shareData!)); setState(() => _loading = false); } catch (_) { _init(); setState(() => _loading = false); }}

  Future<void> _submitAnswer() async { final d = _pasteCtrl.text.trim(); if (d.isEmpty) return; setState(() => _loading = true);
    // 30s timeout
    Timer? t; t = Timer(const Duration(seconds: 30), () { if (mounted) { setState(() => _loading = false); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L10n.instance.get('connect_failed')), backgroundColor: Colors.red)); }});
    try { await _session!.acceptAnswer(d); t.cancel(); } catch (_) { t.cancel(); if (mounted) setState(() => _loading = false); }}

  @override Widget build(BuildContext context) {
    final l = L10n.instance;
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Padding(padding: const EdgeInsets.all(16), child: _shareData == null
      ? Column(children: [
          const SizedBox(height: 40), const Icon(Icons.swap_horiz, size: 48, color: Color(0xFF6C4AB6)),
          const SizedBox(height: 16), Text(l.get('manual_title'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8), Text(l.get('manual_desc'), style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 32),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _createOffer, icon: const Icon(Icons.upload), label: Text(l.get('create_offer')), style: FilledButton.styleFrom(padding: const EdgeInsets.all(15), backgroundColor: const Color(0xFF6C4AB6)))),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => showDialog(context: context, builder: (ctx) { final c = TextEditingController();
            return AlertDialog(title: Text(l.get('paste_dialog')), content: TextField(controller: c, maxLines: 5, decoration: const InputDecoration(hintText: 'Paste...')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.get('cancel'))), FilledButton(onPressed: () { Navigator.pop(ctx); _handleOffer(c.text); }, child: Text(l.get('connect_btn')))]); }), icon: const Icon(Icons.download), label: Text(l.get('paste_offer')), style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(15))))])
      : Column(children: [
          Card(elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
            const Icon(Icons.link, size: 36, color: Color(0xFF6C4AB6)), const SizedBox(height: 12),
            Text(_phase == SessionPhase.answerCreated ? l.get('answer_ready') : l.get('data_ready'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4), Text('${_shareData!.length} ${l.get('chars')}', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              FilledButton.icon(onPressed: () { Clipboard.setData(ClipboardData(text: _shareData!)); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.get('copied')))); }, icon: const Icon(Icons.copy), label: Text(l.get('copy')), style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6C4AB6))),
              if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) ...[const SizedBox(width: 12), OutlinedButton.icon(onPressed: () => Share.share(_shareData!), icon: const Icon(Icons.share), label: Text(l.get('share')))],
            ]),
            if (_phase == SessionPhase.answerCreated || _phase == SessionPhase.offerCreated) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: () => setState(() => _showPaste = true), icon: const Icon(Icons.paste, size: 16), label: Text(l.get('paste_answer'))),
            ],
          ]))),
          if (_showPaste) Padding(padding: const EdgeInsets.only(top: 16), child: TextField(controller: _pasteCtrl, maxLines: 3, decoration: InputDecoration(hintText: l.get('paste_answer_hint'), border: const OutlineInputBorder(), suffixIcon: IconButton(icon: const Icon(Icons.send), onPressed: _submitAnswer)), onSubmitted: (_) => _submitAnswer())),
        ]));
  }
}
