/// 连接页面
library;

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../crypto/identity.dart';
import '../p2p/session_manager.dart';
import '../models/peer.dart';
import '../models/connection_result.dart';

class ConnectScreen extends StatefulWidget {
  final CryptoIdentity identity;
  const ConnectScreen({super.key, required this.identity});
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  SecureSession? _session;
  SessionPhase _phase = SessionPhase.idle;
  String? _shareData;
  Peer? _connectedPeer;
  String? _error;
  bool _loading = false;
  final _pasteCtrl = TextEditingController();
  bool _showPasteForAnswer = false;

  @override
  void initState() { super.initState(); _initSession(); }

  void _initSession() {
    _session?.dispose();
    _session = SecureSession(identity: widget.identity);
    _session!.onPhaseChanged = (p) { if (mounted) setState(() => _phase = p); };
    _session!.onPeerConnected = (peer) {
      if (!mounted) return;
      setState(() => _connectedPeer = peer);
      final s = _session; _session = null;
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) Navigator.pop(context, ConnectionResult(peer: peer, session: s!));
      });
    };
  }

  @override
  void dispose() { _pasteCtrl.dispose(); _session?.dispose(); super.dispose(); }

  Widget _build() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_connectedPeer != null) return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.check_circle, size: 64, color: Colors.green),
      const SizedBox(height: 12), const Text('连接成功', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4), Text(_connectedPeer!.displayName, style: const TextStyle(fontFamily: 'monospace')),
    ]));
    return Column(children: [
      if (_error != null) _errBanner(),
      if (_phase == SessionPhase.idle) ..._roleBtns(),
      if (_shareData != null) _shareView(),
      if (_showPasteForAnswer) _pasteField(),
      const Spacer(),
      _statusChip(),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('建立连接'), centerTitle: true),
    body: SafeArea(child: Padding(padding: const EdgeInsets.all(20), child: _build())));

  Widget _errBanner() => Container(padding: const EdgeInsets.all(12), margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
    child: Row(children: [
      const Icon(Icons.error_outline, color: Colors.red, size: 20), const SizedBox(width: 8),
      Expanded(child: Text(_error!, style: TextStyle(color: Colors.red.shade800, fontSize: 13))),
      IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () { setState(() => _error = null); _initSession(); }),
    ]));

  List<Widget> _roleBtns() => [
    const Icon(Icons.link, size: 48, color: Color(0xFF6C4AB6)),
    const SizedBox(height: 16), const Text('选择角色', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
    const SizedBox(height: 32),
    SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _createOffer,
      icon: const Icon(Icons.upload), label: const Text('我是发起方'),
      style: FilledButton.styleFrom(padding: const EdgeInsets.all(15), backgroundColor: const Color(0xFF6C4AB6)))),
    const SizedBox(height: 16),
    SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _showPasteDialog,
      icon: const Icon(Icons.download), label: const Text('我是接收方 (粘贴数据)'),
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(15)))),
  ];

  Widget _shareView() => Card(elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
      const Icon(Icons.share, size: 36, color: Color(0xFF6C4AB6)),
      const SizedBox(height: 12), const Text('连接数据已就绪', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4), Text('${_shareData!.length} 字符', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        FilledButton.icon(onPressed: _doCopy, icon: const Icon(Icons.copy), label: const Text('复制'),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6C4AB6))),
        if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) ...[
          const SizedBox(width: 12),
          OutlinedButton.icon(onPressed: _doShare, icon: const Icon(Icons.share), label: const Text('分享')),
        ],
      ]),
      if (_phase == SessionPhase.answerCreated || _phase == SessionPhase.offerCreated)
        Padding(padding: const EdgeInsets.only(top: 12), child: OutlinedButton.icon(
          onPressed: () => setState(() => _showPasteForAnswer = true),
          icon: const Icon(Icons.paste, size: 16), label: const Text('我已完成，粘贴对方应答'))),
    ])));

  Widget _pasteField() => Padding(padding: const EdgeInsets.only(top: 16),
    child: TextField(controller: _pasteCtrl, maxLines: 3,
      decoration: InputDecoration(hintText: '粘贴对方的应答数据...', border: const OutlineInputBorder(),
        suffixIcon: IconButton(icon: const Icon(Icons.send), onPressed: _submitAnswer)),
      onSubmitted: (_) => _submitAnswer()));

  Widget _statusChip() {
    final (icon, text, color) = switch (_phase) {
      SessionPhase.idle => (Icons.radio_button_unchecked, '等待操作', Colors.grey),
      SessionPhase.offerCreated => (Icons.upload, '等待对方接收', Colors.orange),
      SessionPhase.answerCreated => (Icons.download, '请将数据发给对方', Colors.orange),
      SessionPhase.handshaking => (Icons.swap_horiz, '握手进行中...', Colors.blue),
      SessionPhase.ready => (Icons.check_circle, '已连接', Colors.green),
      SessionPhase.failed => (Icons.error, '失败', Colors.red),
    };
    return Chip(avatar: Icon(icon, color: color, size: 18), label: Text(text, style: TextStyle(color: color, fontSize: 12)));
  }

  void _doCopy() { Clipboard.setData(ClipboardData(text: _shareData!)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制'))); }
  void _doShare() => Share.share(_shareData!);

  Future<void> _createOffer() async { setState(() => _loading = true);
    try { _shareData = await _session!.createOffer(); setState(() => _loading = false); }
    catch (e) { setState(() { _error = '创建失败: $e'; _loading = false; }); }}

  void _showPasteDialog() { final c = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('粘贴对方数据'), content: TextField(controller: c, maxLines: 5,
        decoration: const InputDecoration(hintText: '粘贴...', border: OutlineInputBorder())),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
        FilledButton(onPressed: () { Navigator.pop(ctx); _handleOffer(c.text); }, child: const Text('连接'))]));}

  Future<void> _handleOffer(String data) async { if (data.trim().isEmpty) return; setState(() => _loading = true);
    try { _shareData = await _session!.createAnswer(data.trim()); setState(() { _loading = false; _showPasteForAnswer = false; }); }
    catch (e) { setState(() { _error = '处理失败: $e'; _loading = false; }); }}

  Future<void> _submitAnswer() async { final d = _pasteCtrl.text.trim(); if (d.isEmpty) return; setState(() => _loading = true);
    try { await _session!.acceptAnswer(d); }
    catch (e) { setState(() { _error = '连接失败: $e'; _loading = false; }); }}
}
