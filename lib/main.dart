/// 三彩丸子 — E2EE+P2P 私密聊天
library;

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'crypto/identity.dart';
import 'l10n.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final dark = prefs.getBool('dark_mode') ?? false;
  runApp(SecureChatApp(darkMode: dark));
}

class SecureChatApp extends StatefulWidget {
  final bool darkMode;
  const SecureChatApp({super.key, this.darkMode = false});
  static _SecureChatAppState? of(BuildContext context) => context.findAncestorStateOfType<_SecureChatAppState>();
  @override
  State<SecureChatApp> createState() => _SecureChatAppState();
}

class _SecureChatAppState extends State<SecureChatApp> {
  late bool _dark;

  @override
  void initState() { super.initState(); _dark = widget.darkMode; }

  void toggleTheme() async {
    setState(() => _dark = !_dark);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', _dark);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: L10n.instance, builder: (_, __) => MaterialApp(
      title: '三彩丸子',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6C4AB6),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF6C4AB6),
        brightness: Brightness.dark,
      ),
      themeMode: _dark ? ThemeMode.dark : ThemeMode.light,
      home: _AppLoader(),
      ));
  }
}

class _AppLoader extends StatefulWidget {
  const _AppLoader();
  @override
  State<_AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<_AppLoader> {
  CryptoIdentity? _identity;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrGenerateIdentity();
  }

  Future<void> _loadOrGenerateIdentity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final manager = IdentityManager();

      final savedEdPub = prefs.getString('ed25519_pub');
      final savedEdPriv = prefs.getString('ed25519_priv');
      final savedXPub = prefs.getString('x25519_pub');
      final savedXPriv = prefs.getString('x25519_priv');

      if (savedEdPub != null &&
          savedEdPriv != null &&
          savedXPub != null &&
          savedXPriv != null) {
        _identity = manager.restoreIdentity(
          ed25519PublicKey: _fromHex(savedEdPub),
          ed25519PrivateKey: _fromHex(savedEdPriv),
          x25519PublicKey: _fromHex(savedXPub),
          x25519PrivateKey: _fromHex(savedXPriv),
        );
      } else {
        _identity = await manager.generateIdentity();
        await prefs.setString(
            'ed25519_pub', _toHex(_identity!.ed25519PublicKey));
        await prefs.setString(
            'ed25519_priv', _toHex(await _identity!.ed25519PrivateKey));
        await prefs.setString(
            'x25519_pub', _toHex(_identity!.x25519PublicKey));
        await prefs.setString(
            'x25519_priv', _toHex(await _identity!.x25519PrivateKey));
      }

      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _error = '密钥初始化失败: $e');
    }
  }

  Future<void> _regenerateIdentity() async {
    setState(() => _identity = null);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear(); // 清除旧的密钥
      await _loadOrGenerateIdentity(); // 重新生成
    } catch (e) {
      if (mounted) setState(() => _error = '重新生成失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() => _error = null);
                  _loadOrGenerateIdentity();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_identity == null) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text('正在初始化加密密钥...'),
              SizedBox(height: 4),
              Text(
                '首次启动需要生成 Ed25519 和 X25519 密钥对',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return SplashScreen(child: HomeScreen(key: ValueKey('${_identity!.ed25519PublicKey.hashCode}_${L10n.instance.lang}'), identity: _identity!));
  }

  static String _toHex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _fromHex(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < hex.length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }
}
