#!/bin/sh
# ============================================================================
# start_leaf_from_xray.sh
#
# 用途：读取 /koolshare/ss/xray.json，当 outbound 为单个 socks 协议时，
#       用 leaf 单进程替代 xray，同时监听 SOCKS5 (23456) 和透明代理 (3333) 端口
#
# Leaf 优势：
#   - 单二进制文件，同时支持 SOCKS5 + 透明代理
#   - 内存占用极低 (~3-5 MB)
#   - 原生支持 SOCKS5 → SOCKS5 转发
#   - 完整支持 TCP + UDP
#
# 退出码：
#   0 - 成功启动或已经由其他进程接管
#   1 - xray.json 不存在或解析失败
#   2 - outbound 不是单个 socks 出站
# ============================================================================

set -e

XRAY_JSON="/koolshare/ss/xray.json"
LEAF_BIN="/koolshare/bin/leaf"
LEAF_CONF="/koolshare/ss/leaf.json"
IPT2SOCKS_BIN="/koolshare/bin/ipt2socks"
JQ_BIN=""

echo_date() {
    echo "【$(TZ=UTC-8 date -R +%Y%m%d\ %X)】: $*"
}

pick_jq_bin() {
    if [ -x "/koolshare/bin/jq" ]; then
        printf '%s\n' "/koolshare/bin/jq"
        return 0
    fi
    command -v jq 2>/dev/null || return 1
}

die() {
    echo_date "$@" >&2
    exit "${2:-1}"
}

[ -f "${XRAY_JSON}" ] || die "${XRAY_JSON} 不存在，无法生成 leaf 启动参数" 1

JQ_BIN="$(pick_jq_bin)" || die "找不到可用的 jq 命令，请确保 /koolshare/bin/jq 存在或在 PATH 中" 1

OUTBOUND_COUNT=$("${JQ_BIN}" '.outbounds | length' "${XRAY_JSON}" 2>/dev/null) || die "xray.json 格式错误，无法解析 outbounds" 1

if [ "${OUTBOUND_COUNT}" != "1" ]; then
    echo_date "检测到 ${OUTBOUND_COUNT} 个 outbound，当前脚本仅支持单个 outbound 场景，跳过 leaf 替换"
    exit 2
fi

PROTOCOL=$("${JQ_BIN}" -r '.outbounds[0].protocol // empty' "${XRAY_JSON}") || die "无法读取 outbound 协议字段" 1

case "${PROTOCOL}" in
    socks)
        ;;
    *)
        echo_date "outbound 协议为 '${PROTOCOL}'，非 socks，跳过 leaf 替换，继续使用 xray"
        exit 2
        ;;
esac

SS_SERVER=$("${JQ_BIN}" -r '.outbounds[0].settings.servers[0].address // empty' "${XRAY_JSON}")
SS_PORT=$("${JQ_BIN}" -r '.outbounds[0].settings.servers[0].port // empty' "${XRAY_JSON}")

for field in SS_SERVER SS_PORT; do
    eval "val=\${${field}}"
    [ -n "${val}" ] || die "缺少必要的 socks 字段: ${field} (${val})" 2
done

# 生成 leaf 配置文件（只监听 SOCKS5）
cat > "${LEAF_CONF}" <<EOF
{
  "log": {
    "level": "warn"
  },
  "inbounds": [
    {
      "tag": "socks-in",
      "listen": "127.0.0.1",
      "port": 23456,
      "protocol": "socks"
    }
  ],
  "outbounds": [
    {
      "tag": "socks-out",
      "protocol": "socks",
      "settings": {
        "address": "${SS_SERVER}",
        "port": ${SS_PORT}
      }
    }
  ]
}
EOF

echo_date "启动 leaf SOCKS5: 127.0.0.1:23456 -> ${SS_SERVER}:${SS_PORT}"

${LEAF_BIN} -c "${LEAF_CONF}" >/dev/null 2>&1 &

LEAF_PID=$!
echo_date "leaf SOCKS5 pid=${LEAF_PID}"

echo_date "启动 ipt2socks 透明代理: 0.0.0.0:3333 -> ${SS_SERVER}:${SS_PORT}"

# ipt2socks 监听透明代理（接收 iptables REDIRECT/TPROXY 流量）
${IPT2SOCKS_BIN} -l 3333 -b 0.0.0.0 -B :: -n 10000 -R \
    -s "${SS_SERVER}" -p "${SS_PORT}" >/dev/null 2>&1 &

IPT2SOCKS_PID=$!
echo_date "ipt2socks transparent proxy pid=${IPT2SOCKS_PID}"

echo_date "所有进程已启动，可通过 ps 或 netstat 验证 23456/3333 端口"
exit 0
