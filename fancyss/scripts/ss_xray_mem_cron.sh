#!/bin/sh

# fancyss xray 内存看门狗（cron 定时执行，非守护进程）
# 每 5 分钟由 cron 触发一次，检查 xray 物理内存（RSS），超过阈值则重启

MAX_RSS_KB=204800  # 200MB，超过则重启
LOG_FILE="/tmp/upload/ss_log.txt"

# 检查 xray 是否在运行（pidof 可能返回多个 PID，分流模式下常见）
XRAY_PIDS=$(pidof xray 2>/dev/null)
[ -z "${XRAY_PIDS}" ] && exit 0

# 累加所有 xray 进程的 RSS（物理内存，单位 KB）
RSS_KB=0
for _pid in ${XRAY_PIDS}; do
	if [ -f "/proc/${_pid}/status" ]; then
		mem_kb=$(awk '/VmRSS/{print $2}' "/proc/${_pid}/status" 2>/dev/null || echo 0)
		RSS_KB=$((RSS_KB + mem_kb))
	fi
done
unset _pid
[ "${RSS_KB}" -eq 0 ] && exit 0
RSS_MB=$((RSS_KB / 1024))
MAX_MB=$((MAX_RSS_KB / 1024))

# 记录当前内存并判断是否需要重启
if [ "${RSS_KB}" -gt "${MAX_RSS_KB}" ]; then
	echo "【$(TZ=UTC-8 date -R +%Y%m%d\ %X)】: ⚠️ xray 内存过高：${RSS_MB}MB (阈值: ${MAX_MB}MB)，触发重启" >> "${LOG_FILE}" 2>/dev/null
	# 飞书通知：内存异常
	_feishu_webhook="$(dbus get ss_basic_feishu_webhook 2>/dev/null)"
	if [ -n "${_feishu_webhook}" ]; then
	(
		_hostname="$(nvram get computer_name 2>/dev/null || echo "Router")"
		curl-fancyss -sk --connect-timeout 3 --max-time 5 -X POST \
			-H "Content-Type: application/json" \
			-d "{\"msg_type\":\"text\",\"content\":{\"text\":\"🔴 [${_hostname}] xray 内存异常！\n当前：${RSS_MB}MB (阈值: ${MAX_MB}MB)\n时间：$(TZ=UTC-8 date -R '+%Y-%m-%d %H:%M:%S')\n操作：自动重启 fancyss\"}}" \
			"${_feishu_webhook}" >/dev/null 2>&1
	) &
	fi
	/koolshare/ss/ssconfig.sh restart >/dev/null 2>&1
else
	echo "【$(TZ=UTC-8 date -R +%Y%m%d\ %X)】: ✅ xray 内存正常：${RSS_MB}MB (阈值: ${MAX_MB}MB)" >> "${LOG_FILE}" 2>/dev/null
fi

# 日志大小控制：超过 100KB 时只保留最后 50KB
if [ -f "${LOG_FILE}" ]; then
	LOG_SIZE=$(wc -c < "${LOG_FILE}" 2>/dev/null || echo 0)
	if [ "${LOG_SIZE}" -gt 102400 ]; then
		TMP="${LOG_FILE}.tmp"
		tail -c 51200 "${LOG_FILE}" > "${TMP}" 2>/dev/null && cat "${TMP}" > "${LOG_FILE}" 2>/dev/null
		rm -f "${TMP}" 2>/dev/null
	fi
fi
