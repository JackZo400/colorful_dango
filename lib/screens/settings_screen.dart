/// 设置
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
  final _sigCtrl = TextEditingController(text: SignalingClient.cachedUrl ?? 'ws://38.22.90.80:8765');

  @override void dispose() { _sigCtrl.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) {
    final l = L10n.instance;
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('⚙️ 设置 / Settings')),
      body: ListView(children: [
        // 语言
        _section('🌐 语言 / Language', [
          SwitchListTile(
            title: const Text('中文'), subtitle: const Text('English'),
            value: l.lang == AppLang.zh,
            onChanged: (_) => l.toggle(),
          ),
        ]),
        // 主题
        _section(isDark ? '🌙 暗色模式' : '☀️ 亮色模式', [
          SwitchListTile(
            title: Text(isDark ? '暗色模式' : '亮色模式'),
            value: isDark,
            onChanged: (_) => SecureChatApp.of(context)?.toggleTheme(),
          ),
        ]),
        // 信令服务器
        _section('☁️ 信令服务器 / Signaling', [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: [
            TextField(controller: _sigCtrl, decoration: const InputDecoration(
              hintText: 'ws://38.22.90.80:8765', border: OutlineInputBorder(),
              helperText: '跨网络连接需要信令服务器'),
              onChanged: (v) => SignalingClient.cachedUrl = v,
            ),
          ])),
        ]),
        // 关于
        _section('💜 关于三彩丸子', [
          const ListTile(
            title: Text('三彩丸子', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            subtitle: Text('v1.1.0-beta'),
          ),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text(
            '一款端到端加密的私密聊天工具。\n\n'
            '你的消息只存在于你和对方之间，\n'
            '不经过任何服务器的存储。\n\n'
            '💻 全部代码由 AI 生成\n'
            '🧑 项目创造者 JackZhao\n\n'
            '安全 · 私密 · 开源 · 免费',
            style: TextStyle(fontSize: 14, height: 1.6),
          )),
        ]),
      ]),
    );
  }

  Widget _section(String title, List<Widget> children) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.fromLTRB(16, 24, 16, 8), child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary))),
    ...children,
    const Divider(),
  ]);
}
