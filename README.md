# 🍡 三彩丸子 / Colorful Dango

加密聊天应用 — 安全、私密、跨平台。

A secure private chat app — cross-platform, no registration needed.

---

## 📥 下载 / Download

| 平台 | 链接 |
|------|------|
| Android | [APK](https://github.com/JackZo400/colorful_dango/releases/latest/download/colorful_dango_android.apk) |
| Windows | [EXE](https://github.com/JackZo400/colorful_dango/releases/latest/download/colorful_dango_windows.exe) |

## ✨ 功能 / Features

- 加密聊天，消息不经过任何服务器
- 消息撤回、清空聊天记录（双向同步）
- 联系人保存，退出不丢失
- 明亮/暗色模式一键切换
- 跨平台：Windows · Android · Linux
- 无需注册，无需手机号
- 支持自建信令服务器实现跨网络连接

## 🌐 自建信令服务器（可选）

如果你想让不同网络下的设备也能互相发现，需要一台有公网 IP 的 VPS：

```bash
# 1. 上传服务器代码
scp bin/server.dart root@你的VPS:/root/

# 2. 登录服务器
ssh root@你的VPS

# 3. 安装 Dart（如果没有）
apt-get update && apt-get install -y dart

# 4. 运行
nohup dart run /root/server.dart > /var/log/dango.log 2>&1 &

# 5. 确认运行中
cat /var/log/dango.log
# 应该看到：信号服务器已启动: ws://0.0.0.0:8765
```

然后在 App 的「添加联系人 → 信令」中输入 `ws://你的VPS地址:8765` 即可。

*信令服务器仅转发连接信息，不存储任何聊天内容或密钥。*

## 🛠 从源码构建 / Build from Source

```bash
git clone https://github.com/JackZo400/colorful_dango.git
cd colorful_dango
flutter pub get
flutter run -d windows    # Windows
flutter run -d android    # Android  
flutter run -d linux      # Linux
```

需要 Flutter SDK：https://docs.flutter.dev/get-started/install

## 📄 许可 / License

MIT
