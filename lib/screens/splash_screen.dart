/// 开屏动画 — 三彩丸子
library;

import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final Widget child;
  const SplashScreen({super.key, required this.child});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade, _scale, _slide;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
    _fade = Tween(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.3, curve: Curves.easeOut)));
    _scale = Tween(begin: 0.5, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.3, curve: Curves.elasticOut)));
    _slide = Tween(begin: 30.0, end: 0.0).animate(CurvedAnimation(parent: _ctrl, curve: const Interval(0.3, 0.6, curve: Curves.easeOutCubic)));
    _ctrl.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 500), () { if (mounted) setState(() => _done = true); });
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [cs.primary, cs.primary.withAlpha(200), cs.primaryContainer], begin: Alignment.topLeft, end: Alignment.bottomRight)),
        child: Center(child: AnimatedBuilder(animation: _ctrl, builder: (_, child) {
          return Opacity(opacity: _fade.value, child: Transform.scale(scale: _scale.value, child: Transform.translate(offset: Offset(0, _slide.value), child: Column(
            mainAxisSize: MainAxisSize.min, children: [
            Container(width: 100, height: 100, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(28), boxShadow: [BoxShadow(color: Colors.black.withAlpha(30), blurRadius: 20)]),
              child: const Icon(Icons.favorite, size: 52, color: Color(0xFF6C4AB6))),
            const SizedBox(height: 20),
            const Text('三彩丸子', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 4)),
            const SizedBox(height: 8),
            Text('私密聊天 · 端到端加密', style: TextStyle(fontSize: 13, color: Colors.white.withAlpha(180), letterSpacing: 2)),
            const SizedBox(height: 32),
            SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white.withAlpha(150)))),
          ]))));
        })),
      ),
    );
  }
}
