#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

PROJECT="eycorsican/leaf"
BIN_NAME="leaf"
API_URL="https://api.github.com/repos/${PROJECT}/releases/latest"

get_latest_version() {
    local LATEST_RELEASE=$(curl -sS -H 'Accept: application/vnd.github+json' "${API_URL}")
    local LATEST_VERSION=$(echo "$LATEST_RELEASE" | jq -r '.tag_name' | sed 's/^v//g')
    echo "latest leaf version is $LATEST_VERSION"
}

get_latest_version

if [ -d "v${LATEST_VERSION}" ]; then
    echo "already have latest!"
    exit 0
fi

mkdir -p "v${LATEST_VERSION}"
cd "v${LATEST_VERSION}"

ARCH_LIST=("aarch64-unknown-linux-musl" "arm-unknown-linux-musleabi" "armv7-unknown-linux-musleabihf" "x86_64-unknown-linux-musl")
FILE_MAP=(["aarch64-unknown-linux-musl"]="leaf_arm64" ["arm-unknown-linux-musleabi"]="leaf_armv5" ["armv7-unknown-linux-musleabihf"]="leaf_armv7" ["x86_64-unknown-linux-musl"]="leaf_x86_64")

for arch in "${ARCH_LIST[@]}"; do
    url="https://github.com/eycorsican/leaf/releases/download/v${LATEST_VERSION}/leaf-${arch}.gz"
    out_name="${FILE_MAP[$arch]}"

    echo "downloading ${out_name}..."
    curl -fsSL -o "${out_name}.gz" "$url"
    gunzip "${out_name}.gz"
    chmod +x "${out_name}"

    echo "compressing with upx: ${out_name}"
    upx --lzma --ultra-brute "${out_name}"
done

md5sum leaf_* > md5sum.txt
cd ..
echo -n "v${LATEST_VERSION}" > latest.txt
echo "done: v${LATEST_VERSION}"
