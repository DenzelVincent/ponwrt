#!/bin/sh
# 阶段: ./scripts/feeds install -a 之后 (cwd = openwrt/), 与 patch-feed-packages.sh 并列调用
# 用途: 把 patches/ 下两个功能性补丁打进 pon feed 本体 (EN7572 激光稳态判定+EPON 线路重开, LOID 补零方向)
# 落点: package/feeds 是软链, 补 feeds/<name>/ 本体即生效; feeds update 会冲掉, 顺序固定 update -> install -> 本脚本

set -eu

apply_pon_patch() {
	feed_dir="$1"
	patch_file="$(pwd)/$2"
	[ -d "$feed_dir" ] || { echo "::error::$feed_dir 不存在 (feeds 未安装?)"; exit 1; }
	[ -f "$patch_file" ] || { echo "::error::$patch_file 缺失"; exit 1; }
	# 幂等: 反向 apply 检查通过即已打过
	if git -C "$feed_dir" apply --reverse --check "$patch_file" 2>/dev/null; then
		echo "$2 已应用, 跳过"
		return 0
	fi
	git -C "$feed_dir" apply --check "$patch_file" || { echo "::error::$2 无法应用于当前 $feed_dir (feed 基线变了?)"; exit 1; }
	git -C "$feed_dir" apply "$patch_file"
	echo "已应用 $2 -> $feed_dir"
}

apply_pon_patch feeds/pon_drivers patches/01-pon-drivers-epon-laser-recovery.patch
apply_pon_patch feeds/pon_userspace patches/02-pon-userspace-loid-padding-wire-view.patch

echo "PON feed 补丁完成"
