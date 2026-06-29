#!/bin/bash
# liboqs 构建脚本 — Linux / macOS / WSL
# 编译 ML-KEM-768 后量子加密库
#
# 用法:
#   chmod +x setup_liboqs.sh
#   ./setup_liboqs.sh
#
# 输出:
#   build/liboqs/lib/liboqs.so   (Linux)
#   build/liboqs/lib/liboqs.dylib (macOS)

set -euo pipefail

LIBOQS_VERSION="0.10.1"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build/liboqs"
LIBOQS_SRC="$BUILD_DIR/src"

echo "=== 编译 liboqs v${LIBOQS_VERSION} ==="

# 1. 下载 liboqs 源码
if [ ! -d "$LIBOQS_SRC" ]; then
    echo "[1/4] 下载 liboqs..."
    mkdir -p "$BUILD_DIR"
    curl -L "https://github.com/open-quantum-safe/liboqs/archive/refs/tags/${LIBOQS_VERSION}.tar.gz" \
        -o "$BUILD_DIR/liboqs.tar.gz"
    tar xzf "$BUILD_DIR/liboqs.tar.gz" -C "$BUILD_DIR"
    mv "$BUILD_DIR/liboqs-${LIBOQS_VERSION}" "$LIBOQS_SRC"
    rm "$BUILD_DIR/liboqs.tar.gz"
else
    echo "[1/4] liboqs 源码已存在"
fi

# 2. 创建构建目录
echo "[2/4] 配置 CMake..."
mkdir -p "$LIBOQS_SRC/build"
cd "$LIBOQS_SRC/build"

# 3. CMake 配置 — 仅编译 ML-KEM-768
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DOQS_MINIMAL_BUILD="OQS_KEM_alg_ml_kem_768" \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_INSTALL_PREFIX="$BUILD_DIR"

# 4. 编译 & 安装
echo "[3/4] 编译..."
cmake --build . --parallel "$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

echo "[4/4] 安装到 $BUILD_DIR..."
cmake --install .

# 5. 复制到 Flutter 可访问位置
echo "=== 完成 ==="
echo ""
echo "库文件位置:"
if [ -f "$BUILD_DIR/lib/liboqs.so" ]; then
    echo "  $BUILD_DIR/lib/liboqs.so"
    echo ""
    echo "Linux 部署:"
    echo "  1. cp $BUILD_DIR/lib/liboqs.so linux/flutter/ephemeral/"
    echo "  2. 或在系统范围内: sudo cp $BUILD_DIR/lib/liboqs.so /usr/local/lib/ && sudo ldconfig"
elif [ -f "$BUILD_DIR/lib/liboqs.dylib" ]; then
    echo "  $BUILD_DIR/lib/liboqs.dylib"
    echo ""
    echo "macOS 部署:"
    echo "  复制到应用的 Frameworks 目录"
fi
