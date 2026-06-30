/// 添加联系人 — 信令服务器 / 局域网 / 手动
library;

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
  @override
  State<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends State<AddContactScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  final IdentityManager _im = IdentityManager();

  @override
  void initState() { super.initState(); _tab = TabController(length: 3, vsync: this); }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(L10n.instance.get('add_contact')), bottom: TabBar(controller: _tab, tabs: [
      Tab(icon: const Icon(Icons.cloud), text: L10n.instance.get('signal_tab')),
      Tab(icon: const Icon(Icons.wifi), text: L10n.instance.get('lan_tab')),
      Tab(icon: const Icon(Icons.keyboard), text: L10n.instance.get('manual_tab')),
    ])),
    body: TabBarView(controller: _tab, children: [
      _SignalTab(identity: widget.identity, onDone: (p) => Navigator.pop(context, p)),
      _LanTab(identity: widget.identity, onDone: (p) => Navigator.pop(context, p)),
      _ManualTab(identity: widget.identity, onDone: (p) => Navigator.pop(context, p)),
    ]));
}

// ─── 信令 ────────────────────────────────

class _SignalTab extends StatefulWidget {
  final CryptoIdentity identity; final void Function(Peer) onDone;
  const _SignalTab({required this.identity, required this.onDone});
  @override
  State<_SignalTab> createState() => _SignalTabState();
}

class _SignalTabState extends State<_SignalTab> {
  final _sig = SignalingClient();
  final _ctrl = TextEditingController(text: SignalingClient.cachedUrl ?? 'ws://');
  final List<DiscoveredPeer> _peers = [];
  bool _on = false, _busy = false;
  String _rawFp = '';
  SecureSession? _pending;

  @override
  void initState() { super.initState(); _loadFp(); }
  @override
  void dispose() { _sig.disconnect(); _ctrl.dispose(); super.dispose();
  }

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
      if (mounted) _sig.sendAnswer(_rawFp, a); else s.dispose();
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

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(16), child: Column(children: [
    if (!_on) ...[
      TextField(controller: _ctrl, decoration: const InputDecoration(labelText: '信令服务器地址', hintText: 'ws://your-server:8765', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: _toggle, icon: const Icon(Icons.cloud), label: const Text('连接服务器')),
    ] else ...[
      Row(children: [
        Icon(Icons.cloud_done, color: Colors.green.shade400, size: 18),
        const SizedBox(width: 8),
        Text('已连接 · ${_peers.length} 在线', style: const TextStyle(fontSize: 13)),
        const Spacer(), TextButton(onPressed: () { _sig.disconnect(); setState(() { _on = false; _peers.clear(); }); }, child: const Text('断开'))]),
      const Divider(),
      Expanded(child: _peers.isEmpty ? const Center(child: Text('等待在线设备...', style: TextStyle(color: Colors.grey))) : ListView(
        children: _peers.map((dp) => ListTile(
          leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.person, color: Colors.white, size: 18)),
          title: Text(dp.fingerprint, style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
          trailing: _busy && _peers.first == dp ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : FilledButton.tonal(child: const Text('连接'), onPressed: () => _connect(dp)))).toList())),
    ],
  ]));
}

// ─── 局域网 ────────────────────────────────

class _LanTab extends StatefulWidget {
  final CryptoIdentity identity; final void Function(Peer) onDone;
  const _LanTab({required this.identity, required this.onDone});
  @override
  State<_LanTab> createState() => _LanTabState();
}

class _LanTabState extends State<_LanTab> {
  final _lan = LanDiscovery();
  final List<DiscoveredPeer> _peers = [];
  bool _on = false, _busy = false;
  String _rawFp = '';
  SecureSession? _pending;

  @override
  void initState() { super.initState(); _loadFp(); }
  @override
  void dispose() { _lan.stop(); super.dispose(); }

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
      if (mounted) _lan.sendSignaling(a); else s.dispose();
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

  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.all(16), child: Column(children: [
    Card(child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
      const Icon(Icons.info_outline, size: 16, color: Colors.grey), const SizedBox(width: 8),
      Expanded(child: Text('仅限同平台设备（电脑↔电脑、手机↔手机），无法跨端发现。', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
    ]))),
    const SizedBox(height: 12),
    if (!_on)
      FilledButton.icon(onPressed: _toggle, icon: const Icon(Icons.wifi), label: const Text('开启局域网扫描'))
    else ...[
      Row(children: [
        Icon(Icons.wifi, color: Colors.green.shade400, size: 18), const SizedBox(width: 8),
        Text('扫描中 · ${_peers.length} 设备', style: const TextStyle(fontSize: 13)),
        const Spacer(), TextButton(onPressed: () { _lan.stop(); setState(() { _on = false; _peers.clear(); }); }, child: const Text('停止'))]),
      const Divider(),
      Expanded(child: _peers.isEmpty ? const Center(child: Text('等待附近设备...', style: TextStyle(color: Colors.grey))) : ListView(
        children: _peers.map((dp) => ListTile(
          leading: const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.person, color: Colors.white, size: 18)),
          title: Text(dp.fingerprint, style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
          trailing: _busy ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : FilledButton.tonal(child: const Text('连接'), onPressed: () => _connect(dp)))).toList())),
    ],
  ]));
}

// ─── 手动 ────────────────────────────────

class _ManualTab extends StatefulWidget {
  final CryptoIdentity identity; final void Function(Peer) onDone;
  const _ManualTab({required this.identity, required this.onDone});
  @override
  State<_ManualTab> createState() => _ManualTabState();
}

class _ManualTabState extends State<_ManualTab> {
  SecureSession? _session;
  String? _shareData;
  SessionPhase _phase = SessionPhase.idle;
  final _pasteCtrl = TextEditingController();
  bool _loading = false, _showPaste = false;

  @override
  void initState() { super.initState(); _init(); }
  void _init() { _session?.dispose(); _session = SecureSession(identity: widget.identity); _session!.onPhaseChanged = (p) { if (mounted) setState(() => _phase = p); }; _session!.onPeerConnected = (peer) async { await PeerStorage.save(peer); Sessions.put(peer, _session!); if (mounted) widget.onDone(peer); }; }
  @override
  void dispose() { _pasteCtrl.dispose(); _session?.dispose(); super.dispose(); }

  Future<void> _createOffer() async { setState(() => _loading = true);
    try { _shareData = await _session!.createOffer(); setState(() => _loading = false); } catch (_) { _init(); setState(() => _loading = false); }}

  Future<void> _handleOffer(String data) async { if (data.trim().isEmpty) return; setState(() => _loading = true);
    try { _shareData = await _session!.createAnswer(data.trim()); setState(() => _loading = false); } catch (_) { _init(); setState(() => _loading = false); }}

  Future<void> _submitAnswer() async { final d = _pasteCtrl.text.trim(); if (d.isEmpty) return; setState(() => _loading = true);
    try { await _session!.acceptAnswer(d); } catch (_) { if (mounted) setState(() => _loading = false); }}

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Padding(padding: const EdgeInsets.all(16), child: _shareData == null
      ? Column(children: [
          const SizedBox(height: 40), const Icon(Icons.swap_horiz, size: 48, color: Color(0xFF6C4AB6)),
          const SizedBox(height: 16), const Text('手动连接', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8), const Text('两台设备通过复制粘贴交换连接数据', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 32),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _createOffer, icon: const Icon(Icons.upload), label: const Text('发起连接 (生成连接数据)'), style: FilledButton.styleFrom(padding: const EdgeInsets.all(15), backgroundColor: const Color(0xFF6C4AB6)))),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: () => showDialog(context: context, builder: (ctx) { final c = TextEditingController();
            return AlertDialog(title: const Text('粘贴对方数据'), content: TextField(controller: c, maxLines: 5, decoration: const InputDecoration(hintText: '粘贴...')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')), FilledButton(onPressed: () { Navigator.pop(ctx); _handleOffer(c.text); }, child: const Text('连接'))]); }), icon: const Icon(Icons.download), label: const Text('响应连接 (粘贴对方数据)'), style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(15))))])
      : Column(children: [
          Card(elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
            const Icon(Icons.link, size: 36, color: Color(0xFF6C4AB6)), const SizedBox(height: 12),
            Text(_phase == SessionPhase.answerCreated ? '应答数据已就绪' : '连接数据已就绪', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4), Text('${_shareData!.length} 字符', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              FilledButton.icon(onPressed: () { Clipboard.setData(ClipboardData(text: _shareData!)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'))); }, icon: const Icon(Icons.copy), label: const Text('复制'), style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6C4AB6))),
              if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) ...[const SizedBox(width: 12), OutlinedButton.icon(onPressed: () => Share.share(_shareData!), icon: const Icon(Icons.share), label: const Text('分享'))],
            ]),
            if (_phase == SessionPhase.answerCreated || _phase == SessionPhase.offerCreated) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: () => setState(() => _showPaste = true), icon: const Icon(Icons.paste, size: 16), label: const Text('粘贴对方应答')),
            ],
          ]))),
          if (_showPaste) Padding(padding: const EdgeInsets.only(top: 16), child: TextField(controller: _pasteCtrl, maxLines: 3, decoration: InputDecoration(hintText: '粘贴对方的应答数据...', border: const OutlineInputBorder(), suffixIcon: IconButton(icon: const Icon(Icons.send), onPressed: _submitAnswer)), onSubmitted: (_) => _submitAnswer())),
        ]));
  }
}
