/// 设置页面
library;

import 'package:flutter/material.dart';
import '../main.dart';
import '../l10n.dart';
import '../p2p/signaling_client.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _sigUrl = TextEditingController(text: SignalingClient.cachedUrl ?? 'ws://');

  @override void dispose() { _sigUrl.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final l = L10n.instance;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('⚙️ 设置 / Settings')),
      body: ListView(children: [
        // 语言
        _Section(title: '语言 / Language', children: [
          SwitchListTile(
            title: Text(l.get('signal_tab'), style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text(l.lang == AppLang.zh ? '中文' : 'English'),
            value: l.lang == AppLang.zh,
            onChanged: (_) => l.toggle(),
          ),
        ]),
        // 主题
        _Section(title: '主题 / Theme', children: [
          SwitchListTile(
            title: const Text('暗色模式'),
            subtitle: const Text('Dark mode'),
            value: Theme.of(context).brightness == Brightness.dark,
            onChanged: (_) => SecureChatApp.of(context)?.toggleTheme(),
          ),
        ]),
        // 信令服务器
        _Section(title: '信令服务器 / Signaling', children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(
            controller: _sigUrl, decoration: const InputDecoration(hintText: 'ws://your-server:8765', border: OutlineInputBorder()),
            onChanged: (v) => SignalingClient.cachedUrl = v,
          )),
        ]),
        // 关于
        _Section(title: l.get('about'), children: [
          ListTile(title: const Text('三彩丸子'), subtitle: const Text('v1.1.0-beta'), trailing: const Icon(Icons.info_outline)),
          ListTile(title: Text(l.get('about_content')), subtitle: const Text('🤖 AI · 👤 JackZhao'), isThreeLine: true, dense: true),
        ]),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 8), child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary))),
    ...children,
    const Divider(),
  ]);
}
