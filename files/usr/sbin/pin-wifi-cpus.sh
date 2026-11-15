#!/bin/sh
# mt76 线程 CPU 亲和: tx 绑末核, napi 轮转其余核, 避免软中断全挤 core 0
# 核数自适应(双核 MT7981/四核 AN7581 通用); 无 mt76 线程时自然空转
ncpu=$(nproc 2>/dev/null) || exit 0
[ "$ncpu" -ge 2 ] || exit 0
tx_mask=$((1 << (ncpu - 1)))
idx=0
for pid in $(ls /proc | grep '^[0-9]*$' | sort -n); do
	[ -r "/proc/$pid/comm" ] || continue
	read -r cname < "/proc/$pid/comm" 2>/dev/null || continue
	case "$cname" in
		mt76-tx*)
			taskset -p "$(printf '%x' "$tx_mask")" "$pid" >/dev/null 2>&1
			;;
		napi/phy*)
			cpu=$((idx % (ncpu - 1)))
			taskset -p "$(printf '%x' $((1 << cpu)))" "$pid" >/dev/null 2>&1
			idx=$((idx + 1))
			;;
	esac
done
