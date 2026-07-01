library;
import 'package:flutter/material.dart';
import '../main.dart';
import '../crypto/identity.dart';
import '../l10n.dart';
import '../models/connection_result.dart';
import '../models/peer.dart';
import '../models/peer_storage.dart';
import '../p2p/sessions.dart';
import 'add_contact_screen.dart';
import 'connect_screen.dart';
import 'settings_screen.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  final CryptoIdentity identity;
  const HomeScreen({super.key, required this.identity});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<Peer> _peers = []; final IdentityManager _im = IdentityManager();
  String _fpHex = '...';
  @override void initState() { super.initState(); _load(); L10n.instance.addListener(_onLang); Sessions.onStatusChanged = (id, online) { if (mounted) setState(() {}); }; }
  @override void dispose() { L10n.instance.removeListener(_onLang); super.dispose(); }

  Future<void> _load() async {
    final fp = await _im.fingerprint(widget.identity);
    final saved = await PeerStorage.loadAll();
    if (mounted) setState(() { _fpHex = fp.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':').toUpperCase(); _peers.addAll(saved); });
  }

  final l = L10n.instance;

  @override
  Widget build(BuildContext cx) {
    final cs = Theme.of(cx).colorScheme;
    return Scaffold(extendBodyBehindAppBar: true,
      appBar: AppBar(title: _colorfulTitle(), centerTitle: true, backgroundColor: Colors.transparent, elevation: 0, actions: [
        IconButton(icon: const Icon(Icons.settings), onPressed: () => Navigator.push(cx, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
      ]),
      body: Container(decoration: BoxDecoration(gradient: LinearGradient(colors: [cs.primaryContainer.withAlpha(60), cs.surface], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
        child: SafeArea(child: Column(children: [
        _IdCard(fpHex: _fpHex), const Divider(height: 1),
        Expanded(child: _peers.isEmpty
          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.people_outline, size: 64, color: cs.outline), const SizedBox(height: 16),
              Text(l.get('no_contacts'), style: Theme.of(cx).textTheme.titleMedium?.copyWith(color: cs.outline)),
              const SizedBox(height: 4), Text(l.get('tap_to_start'), style: Theme.of(cx).textTheme.bodySmall?.copyWith(color: cs.outline))]))
          : ListView(padding: const EdgeInsets.only(bottom: 80), children: _peers.map((p) => Dismissible(
              key: ValueKey(p.id), direction: DismissDirection.endToStart,
              onDismissed: (_) { PeerStorage.remove(p.id); Sessions.remove(p); setState(() => _peers.remove(p)); },
              background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
              child: ListTile(
                leading: CircleAvatar(backgroundColor: cs.primary, child: Text(p.shortFingerprint.substring(0, 2), style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold))),
                title: Text(p.displayName, style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
                subtitle: Text(Sessions.lastText(p.id) ?? (Sessions.isOnline(p) ? l.get('online') : l.get('offline')), style: TextStyle(color: Sessions.isOnline(p) ? Colors.green : Colors.grey, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right),
                onTap: () { final s = Sessions.get(p); if (s != null && s.isReady) { Navigator.push(cx, MaterialPageRoute(builder: (_) => ChatScreen(peer: p, session: s))); } else { _addContact(); } },
                onLongPress: () => _rename(p),
              ))).toList())),
      ]))),
      floatingActionButton: FloatingActionButton.extended(onPressed: _addContact, icon: const Icon(Icons.person_add), label: Text(l.get('add_contact'))),
    );
  }

  Future<void> _addContact() async {
    final peer = await Navigator.push<Peer>(context, MaterialPageRoute(builder: (_) => AddContactScreen(identity: widget.identity)));
    if (peer != null && mounted) { await PeerStorage.save(peer); setState(() { _peers.removeWhere((p) => p.id == peer.id); _peers.add(peer); }); final s = Sessions.get(peer); if (s != null) Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peer: peer, session: s))); }
  }

  void _reconnect(Peer p) => showDialog(context: context, builder: (ctx) => AlertDialog(
    title: Text(l.get('reconnect')), content: Text('${p.displayName}\n\n${l.get('reconnect_msg')}'),
    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.get('cancel'))), FilledButton(onPressed: () { Navigator.pop(ctx); _addContact(); }, child: Text(l.get('add_contact')))]));

  void _rename(Peer p) {
    final ctrl = TextEditingController(text: p.displayName);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text(p.displayName), content: TextField(controller: ctrl, autofocus: true),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.get('cancel'))), FilledButton(onPressed: () async {
        p.displayName = ctrl.text; await PeerStorage.save(p);
        setState(() {}); Navigator.pop(ctx);
      }, child: Text(l.get('save')))],
    ));
  }

  void _showAbout() => showDialog(context: context, builder: (ctx) => AlertDialog(title: _colorfulTitle(),
    content: Text(l.get('about_content')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.get('close')))]));

  Widget _colorfulTitle() => ShaderMask(shaderCallback: (b) => const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFFEC4899), Color(0xFFF59E0B)]).createShader(b),
    child: const Text('三彩丸子', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)));
}

class _IdCard extends StatelessWidget {
  final String fpHex; const _IdCard({required this.fpHex});
  @override Widget build(BuildContext cx) => Container(width: double.infinity, padding: const EdgeInsets.all(16),
    color: Theme.of(cx).colorScheme.primaryContainer,
    child: Column(children: [
      Icon(Icons.fingerprint, size: 36, color: Theme.of(cx).colorScheme.onPrimaryContainer),
      const SizedBox(height: 4), Text(L10n.instance.get('fingerprint'), style: TextStyle(color: Theme.of(cx).colorScheme.onPrimaryContainer, fontSize: 11)),
      const SizedBox(height: 2), SelectableText(fpHex, style: TextStyle(fontSize: 14, fontFamily: 'monospace', fontWeight: FontWeight.bold, color: Theme.of(cx).colorScheme.onPrimaryContainer)),
    ]));
}
