#!/bin/bash

# 使用 Docker 编译最新 xray
# 避免 macOS 环境差异导致的编译问题

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/.build_xray"

echo "========================================="
echo "使用 Docker 编译 Xray 最新版本"
echo "========================================="

# 检查 Docker 是否运行
if ! command -v docker &> /dev/null; then
    echo "错误: 未找到 Docker，请先安装 Docker"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "错误: Docker 未运行，请启动 Docker"
    exit 1
fi

# 创建构建目录
mkdir -p "${BUILD_DIR}"

# 使用 Docker 编译
docker run --rm \
    -v "${BUILD_DIR}:/build" \
    -v "${SCRIPT_DIR}:/source" \
    -w /build \
    golang:1.23-alpine \
    sh -c '
        set -e

        # 安装必要的工具
        apk add --no-cache git bash upx wget

        echo "========================================="
        echo "环境准备完成"
        echo "========================================="

        # 克隆或更新 Xray-core
        if [ ! -d "Xray-core/.git" ]; then
            echo "克隆 Xray-core 仓库..."
            git clone https://github.com/XTLS/Xray-core.git
        fi

        cd Xray-core

        # 获取最新版本标签
        git fetch --tags origin
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
        mkdir -p "/source/$OUTDIR"

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

            # UPX 压缩
            upx --lzma --best "xray_$arch"

            # 移动到输出目录
            mv "xray_$arch" "/source/$OUTDIR/"
        }

        # 编译三个架构
        build_one armv5
        build_one armv7
        build_one arm64

        # 生成 md5sum
        cd "/source/$OUTDIR"
        md5sum xray_armv5 xray_armv7 xray_arm64 > md5sum.txt

        echo "========================================="
        echo "编译完成！"
        echo "版本: $VERSIONTAG"
        echo "目录: $OUTDIR"
        echo "========================================="
        ls -lh
    '

# 更新 latest_2.txt
LATEST_DIR=$(ls -dt "${BUILD_DIR}"/v*/ 2>/dev/null | head -1)
if [ -n "$LATEST_DIR" ]; then
    VERSION=$(basename "$LATEST_DIR")
    echo -n "$VERSION" > "${SCRIPT_DIR}/latest_2.txt"
    echo "========================================="
    echo "已更新 latest_2.txt: $VERSION"
    echo "========================================="
else
    echo "错误: 未找到编译输出目录"
    exit 1
fi

echo "========================================="
echo "全部完成！"
echo "========================================="
