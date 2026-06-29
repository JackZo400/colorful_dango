# 🍡 三彩丸子 (Colorful Dango)

E2EE + P2P 私密聊天应用，零服务器存储，端到端加密。

## ✨ 特性
- **端到端加密** — X25519 ECDH + Ed25519 签名 + AES-256-GCM
- **P2P 直连** — WebRTC DataChannel，消息不经过任何服务器
- **信令中继** — 可选 WebSocket 中继，跨网络自动连接
- **局域网发现** — UDP 组播免粘贴（同平台）
- **消息持久化** — 本地 SharedPreferences 存储，退出不丢
- **撤回 + 清空** — 双向同步
- **深色模式** — 一键切换
- **跨平台** — Windows / Android / Linux

## 🚀 快速开始
```bash
git clone https://github.com/yourname/colorful_dango.git
cd colorful_dango && flutter pub get
flutter run -d windows   # 或 -d android / -d linux
```

## 🌐 可选信令服务器
```bash
scp bin/server.dart root@your-vps:/root/
ssh root@your-vps
apt-get install -y dart
nohup dart run /root/server.dart > /var/log/dango.log 2>&1 &
# 连接 ws://your-vps:8765
```

## 🏗 架构
```
Alice ──WebRTC(E2EE)── Bob
  │                     │
  └── (可选) 信令中继 ──┘
```
信令仅转发 SDP，不存储消息/密钥/任何用户数据。

## 📦 技术栈
Flutter · cryptography · flutter_webrtc · shared_preferences · share_plus

## 📄 许可
MIT
