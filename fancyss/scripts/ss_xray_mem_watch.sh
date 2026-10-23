#!/bin/sh

# fancyss xray 内存监控脚本
# 定期检查 xray 内存使用，超过阈值则重启

source /koolshare/scripts/ss_base.sh 2>/dev/null || true

# 如果 ss_base.sh 加载失败，定义 fallback 函数
if ! type echo_date >/dev/null 2>&1; then
	echo_date() {
		echo "【$(TZ=UTC-8 date -R +%Y%m%d\ %X)】: $*"
	}
fi

LOG_FILE="/tmp/upload/ss_log.txt"
PIDFILE="/var/run/ss_xray_mem_watch.pid"
CHECK_INTERVAL=300  # 5分钟检查一次
MAX_XRAY_MEM_KB=80000  # 80MB 阈值（超过则重启，保守值）
WARN_XRAY_MEM_KB=60000  # 60MB 告警阈值

log_msg() {
	echo_date "$1" >> "${LOG_FILE}" 2>/dev/null || true
}

# 清理 PID 文件
cleanup_pidfile() {
	rm -f "${PIDFILE}" 2>/dev/null
}

# 捕获退出信号，清理 PID 文件
trap cleanup_pidfile EXIT TERM INT

get_xray_mem_kb() {
	local total_mem=0
	local pids
	pids=$(pidof xray 2>/dev/null)
	[ -z "${pids}" ] && echo 0 && return
	# pidof 可能返回多个 PID（如同时运行主进程和分流进程），需要累加所有进程的内存
	for pid in ${pids}; do
		if [ -f "/proc/${pid}/status" ]; then
			local mem_kb
			mem_kb=$(awk '/VmRSS/ {print $2}' "/proc/${pid}/status" 2>/dev/null || echo 0)
			total_mem=$((total_mem + mem_kb))
		fi
	done
	echo "${total_mem}"
}

check_and_restart_xray() {
	local mem_kb=$(get_xray_mem_kb)
	local mem_mb=$((mem_kb / 1024))

	if [ "${mem_kb}" -eq 0 ]; then
		# xray 没有运行，不处理
		return 0
	fi

	# 超过阈值，重启 xray
	if [ "${mem_kb}" -gt "${MAX_XRAY_MEM_KB}" ]; then
		log_msg "⚠️ xray 内存使用过高：${mem_mb}MB (阈值: $((MAX_XRAY_MEM_KB / 1024))MB)，重启 xray..."

		# 尝试优雅重启
		if [ -f "/koolshare/perp/xray/rc.main" ]; then
			perpctl h xray >/dev/null 2>&1
			sleep 2
			perpctl u xray >/dev/null 2>&1
		else
			# 使用完整重启流程确保 xray 被正确重启
			# 注意：restart 动作不会调用 kill_process，所以旧监控不会被自动杀死
			# 必须先删除 PID 文件并退出，让 restart 启动的新监控能正常创建 PID 文件
			cleanup_pidfile
			# 忽略 HUP 信号，防止父进程退出时影响后台重启流程
			trap '' HUP 2>/dev/null || true
			/koolshare/ss/ssconfig.sh restart >/dev/null 2>&1 &
			# 立即退出，新监控会由 restart 流程启动
			exit 0
		fi

		log_msg "✅ xray 重启完成"
		return 1
	fi

	# 超过告警阈值，记录日志但不重启
	if [ "${mem_kb}" -gt "${WARN_XRAY_MEM_KB}" ]; then
		log_msg "⚡ xray 内存使用告警：${mem_mb}MB (告警阈值: $((WARN_XRAY_MEM_KB / 1024))MB)"
	fi

	return 0
}

main() {
	log_msg "🔍 xray 内存监控启动（检查间隔: ${CHECK_INTERVAL}秒，阈值: $((MAX_XRAY_MEM_KB / 1024))MB）"

	while true; do
		# 检查是否还在运行
		if [ "$(dbus get ss_basic_enable 2>/dev/null)" != "1" ]; then
			log_msg "fancyss 已关闭，退出内存监控"
			exit 0
		fi

		check_and_restart_xray

		sleep ${CHECK_INTERVAL}
	done
}

# 防止重复启动（使用 PID 文件，兼容 BusyBox）
if [ -f "${PIDFILE}" ]; then
	old_pid=$(cat "${PIDFILE}" 2>/dev/null)
	if [ -n "${old_pid}" ] && [ -d "/proc/${old_pid}" ]; then
		# 旧进程仍在运行，退出
		exit 0
	fi
	# 旧 PID 文件无效，清理
	rm -f "${PIDFILE}" 2>/dev/null
fi

# 写入当前 PID
echo $$ > "${PIDFILE}" 2>/dev/null || true

main
