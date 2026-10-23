#!/bin/bash

# 使用本地 Go 编译最新 xray
# 适用于 macOS 环境

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/.build_xray"

echo "========================================="
echo "使用本地 Go 编译 Xray 最新版本"
echo "========================================="

# 设置 Go 环境
export GOROOT=/opt/homebrew/Cellar/go/1.26.1/libexec
export PATH=$GOROOT/bin:$PATH

# 检查 Go 是否可用
if ! command -v go &> /dev/null; then
    echo "错误: Go 不可用，请检查安装"
    exit 1
fi

echo "Go 版本: $(go version)"
echo "========================================="

# 创建构建目录
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# 克隆或更新 Xray-core
if [ ! -d "Xray-core/.git" ]; then
    echo "克隆 Xray-core 仓库..."
    git clone https://github.com/XTLS/Xray-core.git
else
    echo "更新 Xray-core 仓库..."
    cd Xray-core
    git fetch --tags origin
    cd ..
fi

cd Xray-core

# 获取最新版本标签
VERSIONTAG=$(git tag -l "v*" --sort=-v:refname | head -n 1)

if [ -z "$VERSIONTAG" ]; then
    echo "错误: 无法获取最新版本标签"
    exit 1
fi

echo "最新版本: $VERSIONTAG"
git checkout -f "$VERSIONTAG"

COMMITHASH=$(git rev-parse --short=7 HEAD)
OUTDIR="${VERSIONTAG}-${COMMITHASH}"

echo "编译目录: $OUTDIR"
mkdir -p "${SCRIPT_DIR}/${OUTDIR}"

# 编译函数
build_one() {
    local arch="$1"
    local GOARM=""
    local GOARCH=""

    case "$arch" in
        armv5)
            GOARM=5
            GOARCH=arm
            ;;
        armv7)
            GOARM=7
            GOARCH=arm
            ;;
        arm64)
            GOARM=""
            GOARCH=arm64
            ;;
    esac

    echo "========================================="
    echo "编译 xray_$arch (GOARCH=$GOARCH, GOARM=$GOARM)"
    echo "========================================="

    env CGO_ENABLED=0 GOOS=linux GOARM="$GOARM" GOARCH="$GOARCH" \
        go build -v -o "xray_$arch" -trimpath -ldflags="-s -w -buildid=" ./main

    # UPX 压缩（如果可用）
    if command -v upx &> /dev/null; then
        echo "UPX 压缩 xray_$arch..."
        upx --lzma --best "xray_$arch"
    else
        echo "警告: UPX 未安装，跳过压缩"
    fi

    # 移动到输出目录
    mv "xray_$arch" "${SCRIPT_DIR}/${OUTDIR}/"
}

# 编译三个架构
build_one armv5
build_one armv7
build_one arm64

# 生成 md5sum
cd "${SCRIPT_DIR}/${OUTDIR}"
md5sum xray_armv5 xray_armv7 xray_arm64 > md5sum.txt

echo "========================================="
echo "编译完成！"
echo "版本: $VERSIONTAG"
echo "目录: $OUTDIR"
echo "========================================="
ls -lh

# 更新 latest_2.txt
echo -n "$OUTDIR" > "${SCRIPT_DIR}/latest_2.txt"
echo "========================================="
echo "已更新 latest_2.txt: $OUTDIR"
echo "========================================="

echo "========================================="
echo "全部完成！"
echo "========================================="
