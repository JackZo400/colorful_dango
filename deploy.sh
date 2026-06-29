#!/bin/bash
# 三彩丸子信令服务器一键部署脚本
set -e

SERVER="root@156.239.3.244"
KEY=~/.ssh/dango_deploy

echo "=== 1. 上传公钥 ==="
ssh-copy-id -i ${KEY}.pub -o StrictHostKeyChecking=no $SERVER
echo ""

echo "=== 2. 安装 Dart (如未安装) ==="
ssh -i $KEY $SERVER 'command -v dart &>/dev/null && echo "Dart 已安装" || (apt-get update -qq && apt-get install -y -qq apt-transport-https ca-certificates gnupg && curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor > /usr/share/keyrings/dart.gpg && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/dart.gpg] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main" > /etc/apt/sources.list.d/dart_stable.list && apt-get update -qq && apt-get install -y -qq dart && echo "Dart 安装完成")'
echo ""

echo "=== 3. 上传服务器代码 ==="
scp -i $KEY bin/server.dart $SERVER:/root/server.dart
echo ""

echo "=== 4. 启动服务 ==="
ssh -i $KEY $SERVER 'pkill -f "dart run server.dart" 2>/dev/null; nohup dart run /root/server.dart > /var/log/dango-server.log 2>&1 & sleep 2; cat /var/log/dango-server.log'
echo ""
echo "✅ 部署完成！信令地址: ws://156.239.3.244:8765"
