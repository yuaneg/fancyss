#!/bin/sh

# fancyss xray 内存看门狗（cron 定时执行，非守护进程）
# 每 5 分钟由 cron 触发一次，检查 xray 物理内存（RSS），超过阈值则重启

MAX_RSS_KB=204800  # 200MB，超过则重启
LOG_FILE="/tmp/upload/ss_xray_restart.log"
XRAY_ACCESS_LOG="/tmp/upload/xray_access.log"
XRAY_ERROR_LOG="/tmp/upload/xray_error.log"
XRAY_LOG_MAX_BYTES=1048576  # 每个Xray日志最大1MiB，超过后保留后一半

# 功能：限制单个Xray日志大小；使用同一inode写回，避免替换正在写入的日志文件。
truncate_xray_log() {
	local file="$1"
	[ -f "${file}" ] || return 0

	local size
	size=$(wc -c < "${file}" 2>/dev/null || echo 0)
	[ "${size}" -gt "${XRAY_LOG_MAX_BYTES}" ] || return 0

	local keep=$((XRAY_LOG_MAX_BYTES / 2))
	local tmp_file="${file}.truncate.$$"
	if tail -c "${keep}" "${file}" > "${tmp_file}" 2>/dev/null; then
		cat "${tmp_file}" > "${file}" 2>/dev/null || true
	fi
	rm -f "${tmp_file}" >/dev/null 2>&1
}

# 即使Xray未运行或本轮无需重启，也先控制历史日志大小。
truncate_xray_log "${XRAY_ACCESS_LOG}"
truncate_xray_log "${XRAY_ERROR_LOG}"

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
	_TS="$(TZ=UTC-8 date -R '+%Y-%m-%d %H:%M:%S')"
	echo "${_TS} | ⚠️ xray 内存异常 | ${RSS_MB}MB | 阈值: ${MAX_MB}MB | 操作: 自动重启" >> "${LOG_FILE}" 2>/dev/null
	# 日志大小控制：超过 10KB 时只保留最后 5KB
	if [ -f "${LOG_FILE}" ]; then
		LOG_SIZE=$(wc -c < "${LOG_FILE}" 2>/dev/null || echo 0)
		if [ "${LOG_SIZE}" -gt 10240 ]; then
			TMP="${LOG_FILE}.tmp"
			tail -c 5120 "${LOG_FILE}" > "${TMP}" 2>/dev/null && cat "${TMP}" > "${LOG_FILE}" 2>/dev/null
			rm -f "${TMP}" 2>/dev/null
		fi
	fi
	/koolshare/ss/ssconfig.sh restart >/dev/null 2>&1
fi
