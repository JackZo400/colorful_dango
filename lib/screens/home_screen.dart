/// 三彩丸子 v1.0.0-alpha — 干净首页
library;

import 'package:flutter/material.dart';
import '../main.dart';
import '../crypto/identity.dart';
import '../models/peer.dart';
import '../models/peer_storage.dart';
import '../p2p/sessions.dart';
import 'add_contact_screen.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  final CryptoIdentity identity;
  const HomeScreen({super.key, required this.identity});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<Peer> _peers = [];
  final IdentityManager _im = IdentityManager();
  String _fpHex = '加载中...';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final fp = await _im.fingerprint(widget.identity);
    final saved = await PeerStorage.loadAll();
    if (mounted) setState(() {
      _fpHex = fp.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase();
      _peers.addAll(saved);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('三彩丸子'), centerTitle: true, actions: [
      IconButton(icon: const Icon(Icons.dark_mode), tooltip: '深色模式', onPressed: () => SecureChatApp.of(context)?.toggleTheme()),
      IconButton(icon: const Icon(Icons.info_outline), tooltip: '关于', onPressed: _showAbout),
    ]),
    body: Column(children: [
      _IdCard(fpHex: _fpHex),
      const Divider(height: 1),
      Expanded(child: _peers.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.people_outline, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16), Text('暂无联系人', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 4), Text('点击下方按钮开始', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
          ]))
        : ListView(padding: const EdgeInsets.only(bottom: 80), children: _peers.map((p) => Dismissible(
            key: ValueKey(p.id), direction: DismissDirection.endToStart,
            onDismissed: (_) { PeerStorage.remove(p.id); Sessions.remove(p); setState(() => _peers.remove(p)); },
            background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
            child: ListTile(
              leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primary, child: Text(p.shortFingerprint.substring(0, 2), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold))),
              title: Text(p.displayName, style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
              subtitle: Text(Sessions.isOnline(p) ? '在线' : '离线', style: TextStyle(color: Sessions.isOnline(p) ? Colors.green : Colors.grey, fontSize: 12)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                final s = Sessions.get(p);
                if (s != null && s.isReady) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peer: p, session: s)));
                } else {
                  _reconnect(p);
                }
              }))).toList())),
    ]),
    floatingActionButton: FloatingActionButton.extended(onPressed: _addContact, icon: const Icon(Icons.person_add), label: const Text('添加联系人')),
  );

  Future<void> _addContact() async {
    final peer = await Navigator.push<Peer>(context, MaterialPageRoute(builder: (_) => AddContactScreen(identity: widget.identity)));
    if (peer != null && mounted) {
      await PeerStorage.save(peer);
      setState(() { _peers.removeWhere((p) => p.id == peer.id); _peers.add(peer); });
      final s = Sessions.get(peer);
      if (s != null) Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peer: peer, session: s)));
    }
  }

  void _reconnect(Peer p) => showDialog(context: context, builder: (ctx) => AlertDialog(
    title: const Text('重新连接'), content: Text('${p.displayName}\n\n连接到同一信令服务器或通过手动方式重新连接。'),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
      FilledButton(onPressed: () { Navigator.pop(ctx); _addContact(); }, child: const Text('添加联系人'))]));

  void _showAbout() => showDialog(context: context, builder: (ctx) => AlertDialog(
    title: const Text('三彩丸子'), content: const Text('E2EE+P2P 私密聊天\n端到端加密 · 零服务器存储\nv1.0.0-alpha'),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭'))]));
}

class _IdCard extends StatelessWidget {
  final String fpHex;
  const _IdCard({required this.fpHex});
  @override
  Widget build(BuildContext context) => Container(width: double.infinity, padding: const EdgeInsets.all(16),
    color: Theme.of(context).colorScheme.primaryContainer,
    child: Column(children: [
      Icon(Icons.fingerprint, size: 36, color: Theme.of(context).colorScheme.onPrimaryContainer),
      const SizedBox(height: 4), Text('身份指纹', style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer, fontSize: 11)),
      const SizedBox(height: 2), SelectableText(fpHex, style: TextStyle(fontSize: 14, fontFamily: 'monospace', fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onPrimaryContainer)),
    ]));
}
