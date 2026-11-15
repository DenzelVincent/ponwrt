# wuziwei fork 评估与移植方案

日期：2026-11-15
对象：https://github.com/wuziwei/ponwrt-ZN504-HG5585F （下称 fork）
本地：DenzelVincent/ponwrt，实施分支 bugfix（原名 port/wuziwei-fixes，2026-11-15 改通用名；基于 master 51012c8ac4）

## 一、fork 基本情况（证据）

- fork 父仓库就是本项目上游 pbs05/ponwrt（GitHub API parent 字段确认）。
- compare 结果：ahead 69 / behind 0，163 个文件改动（tmp/fork-compare.json）。
- 创建 2026-11-08，最近推送 2026-11-15（活跃）；14 star / 7 fork。
- fork 目标机型：兆能 ZN504XG-D、烽火 HG5585F CT/CU；本仓库 an7581.mk 本就支持
  这些机型及 Gemtek/Nokia 等，故板级修复也在移植范围（用户拍板：多设备，有用的都纳入）。
- 本地相对上游未改动 target/linux/airoha/、package/emortal/、package/system/rpcd/、
  package/network/config/（git diff upstream/master..HEAD 核实）→ fork 补丁基线与我们一致。
- README 营销措辞重，逐项核对代码后按下列分类定性。
- fork 最新 release 止于 v2026.11.14-2227；931 的 hunk4 行数声明有误（见三），
  932 在 11-15 才加 → 这两个内核补丁很可能未真正通过 fork 自己的 CI，我们必须自建验证。

## 二、逐项定性

### A. 已移植：SoC 级真实修复

| 项 | 内容 | 证据 |
|---|---|---|
| 931-net-airoha-fix-wan-ipv6-pppoe-flow-offload.patch | PPE 四缺陷：路由 IPv6 误落 L2 黑洞、PPPoE session ID 被清、IPv6 条目 NPU 计数 stall、MTU 未留 PPPoE+VLAN 16 字节余量 | 上下文注释出自我们 930 补丁（930:69），基线吻合；hunk4 行数已修正 |
| 932-net-airoha-ppe-support-bridge-fdb-port-offload.patch | br-lan egress 经 br_fdb_find_port 解析桥从口，WAN→LAN 才能硬件卸载；FDB 未学习安全回退 CPU | fork 称 88% 下行此前走 CPU；CONFIG_BRIDGE 门控写法正确 |
| 133-rpcd-async-scan.patch | WiFi 扫描 fork 子进程+ubus 延迟应答+30s 超时，不阻塞 rpcd 事件 loop | 天然兼容：有线目标不触发扫描；rpcd 源码构建期拉取，需编译验证 |

适用前提：931/932 只在 flow_offloading_hw=1 时生效。核查结论：该值出厂已默认为 1，两个分支都是，
无需改动。原判断读的 package/network/config/firewall/files/firewall.config 属 firewall3，
而 an7581.config 选的是 firewall4（firewall3 未选），那个文件不进固件。
firewall4 无 files/，默认配置来自上游源码包（钉 e6f600c4），由
001-firewall4-add-support-for-fullcone-nat.patch 添加 flow_offloading_hw 1；
实测两个补丁对该提交按 quilt 顺序均 apply 通过，应用后 root/etc/config/firewall:9 即为该项。
运行时前提：fw4.uc 的 resolve_hw_offload_devices() 会试 nft_try_hw_offload()，硬件拒绝时打
warn "Hardware flow offloading unavailable, falling back to software offloading" 并置 false，
所以配置为 1 不等于硬件卸载真生效，验收要看这条 warn 是否出现。

### B. 已移植：板级修正与 WiFi 兼容项（按机型/有无 WiFi 天然门控）

| 项 | 内容 |
|---|---|
| an7581-fiberhome-hg5585f-ct.dts | 电信版硬件仅 USB 2.0，usb0 锁定 USB2 PHY；写法与 common dtsi 的 usb1 既有锁定一致，usb0_phy 标签已核实（an7581.dtsi:608） |
| pin-wifi-cpus.sh + 99-wifi-affinity | mt76 线程亲和打散；原版硬编码 4 核掩码，已改写为 nproc 自适应（tx 绑末核、napi 轮转其余核，掩码按 %x 输出避免 taskset 十六进制误读）；hotplug 仅 phy*-ap0 add 触发，有线天然不生效 |
| autocore Makefile 加 airoha% + cpuinfo 跳过 airoha 温度 | 装 tempinfo 后概览页多一行独立"温度"（CPU+WiFi，WiFi 温度是架构行没有的新信息）；同时把 airoha 加进 cpuinfo 温度跳过名单（沿用 ipq/mediatek/qualcommax 既有设计），架构行不再重复显示 CPU 温度、只留频率。用户拍板 tempinfo 保留 |
| cpufreq.uci 加 airoha 档（845413a386 撤掉后由 54fb4465eb 恢复） | ondemand 500M-1.2G/10/50。编译仓库 an7581.config 未启用 CONFIG_PACKAGE_cpufreq，包 DEPENDS:=@(arm\|\|aarch64) 无 DEFAULT_y，defconfig 仍 not set，故档位在产出固件里仍是死代码。用户拍板不启用该包，恢复的提交保留不动 |

### C. PON feed 功能性修复（改走 feed fork 提交 + 钉 sha）

| 项 | 内容 | 证据 |
|---|---|---|
| 01-pon-drivers-epon-laser-recovery.patch | EN7572 SYS_TX_READY 8 次采样确认（~140ms 稳态，防冷启动假就绪）+ EPON LLID 卡死线路重开 worker（含固件重载升级） | EN7572 部分在共享前端驱动，对本机 XG-PON 同样有效；feed HEAD 无 reopen_holding（0 匹配），是比 feed 10-24 旧修更新的 11-11 版；对 feed 浅克隆 git apply --check 通过 |
| 02-pon-userspace-loid-padding-wire-view.patch | LOID 左/右补零方向可选（华为等 OLT 互操作）+ 链路层原始报文展示 + pon-reopen 配套 | feed 无此功能（commit 列表核实）；git apply --check 通过；含既有 luci-app-pon 的功能性 UI，非新主题面板 |
| ~~scripts/apply-pon-feed-patches.sh~~（方案作废，待删） | 原为 feeds install 后把两补丁打进 feed 本体，幂等（反向 check 判已应用），锚点失配报 ::error:: | tmp 克隆实测：首次应用成功、二次跳过。改走 fork 提交后不再需要，与 patches/01、02 一并删除 |

落地方式：fork pbs05/openwrt-pon-drivers 与 pbs05/openwrt-pon-userspace，把两个补丁作为真实提交打进去，
bugfix 的 feeds.conf.default 改成 fork 地址 + ^<40位sha>；master 保持 pbs05 不钉。
补丁进 feed 自己的版本历史后，scripts/feeds 克隆出来就是修好的源码，不再需要应用脚本、
也不再被 feeds update 冲掉，故 patches/01、patches/02、scripts/apply-pon-feed-patches.sh 一并删除。
状态：待用户建 fork 并提供两个 sha 后实施，详见编译仓库
docs/2026-11-15-files迁移与源码分支选择设计.md 第三节 C 与第六节。
连带后果：publish-feed-repos.yml 固定 master，Pages 上的 pon_userspace 仍是未修版；
bugfix 固件内置的是修好且 PKG_RELEASE 已 bump 的版本，apk 不会降级，设备端安全，但 Pages 与内置版本会分叉。

### D. 核实后排除（证据）

| 项 | 原因 |
|---|---|
| /etc/Wireless SKU dat、07_an7581_bsp_wifi_mac preinit、mt7916-an-eeprom hotplug/init | fork 的 WiFi 同样用 mt76（release.config: kmod-mt7915e=y）；vendor 驱动文件与 mtwifi-macaddr 路径对 mt76 无效；EEPROM 上游 DTS NVMEM cell 已覆盖（hg5585f-common.dtsi:287 eeprom@1000，与 fork dd offset 一致） |
| en7581_MT7916_npu_* 固件 blobs | NPU 固件名由 DTS firmware-name 指定（123 补丁），hg5585f/zn50x DTS 均无该属性 → 永不被加载；基础 en7581_npu_* 已有 airoha-en7581-npu-firmware 包（an7581.config:652） |
| image.mk 裁剪 usb-sfp 变体 | fork 的发布策略（只出 4 镜像），非修复；多设备仓库保留全部变体 |
| 03-iptv-bridge-mac-fix | 作用于 luci-app-iptv，fork 自己已删该包集成（d1ac6ad6ee）；我们不做 IPTV 单线复用 |
| Vantage 主题、luci-app-airoha-npu、lucky、momo/sing-box 预置与版本 bump、99-custom-settings、release.config、build-zn504.yml、README | 主题面板/个人配置/发布策略，用户明确不要；CI 在编译仓库且"仅 tag 发布"口径冲突 |
| sysupgrade.conf、backup/restore-fiberhome-pon.sh | 主要保 momo 非 /etc 路径；/etc/config/pon 默认随 /etc 保留，脚本属额外功能非修复 |
| sysctl 16MB 缓冲、99-multicast | IPTV/BT 调优非修复；2MB 默认缓冲对 512MB OOM 史设备是风险；关 IGMP snooping 增加组播泛洪 |
| firewall wan_6、config_generate 删 lan6、90-ipv6-fix fe80::1 假路由 | 个人接口命名与组网 workaround，假默认路由潜在有害 |
| integrate-temperature.py + temperature-rpc.uc | CI 期改 luci feed 的外观集成，违反 feed 补丁口径 |
| eip93 剔除 | configs/an7581.config:3324 早已 not set |

## 三、实施记录（2026-11-15）

落盘文件（分支 bugfix，原 port/wuziwei-fixes）：
- target/linux/airoha/patches-6.18/931-…、932-…
- package/system/rpcd/patches/133-rpcd-async-scan.patch
- patches/01-…、02-… + scripts/apply-pon-feed-patches.sh
- files/usr/sbin/pin-wifi-cpus.sh、files/etc/hotplug.d/net/99-wifi-affinity
- .gitignore（放开 /files 以纳入 overlay；加 PON 凭据/备份隐私忽略规则）
- package/emortal/autocore/Makefile、package/emortal/autocore/files/cpuinfo；cpufreq 档位在 package/emortal/cpufreq/files/cpufreq.uci（原记录误写成 autocore 下）
- target/linux/airoha/dts/an7581-fiberhome-hg5585f-ct.dts

关键修正与校验：
- 931 第 4 hunk 原作者声明 -896,7/+897,8 实为 8/9（少算一行上下文），已修正为
  -896,8/+897,9；后续 hunk 起始行号与修正后累计偏移逐一核对一致。
- 全部 5 个补丁 hunk 行数复验 OK（124 hunk）；PON 两补丁对 feed HEAD 实测 apply 通过。
- 全部新增/修改文件 CR 字节校验为 0（LF）；三个 shell 脚本 bash -n 通过。
- apply 脚本 tmp 克隆实测幂等。

### 追加：files/ overlay 所有权归一（2026-11-15）

起因：编译仓库 ImmortalWrt-firmware-build 也有一份 `files/`（只放设备端自建源清单），
固件工作流用 `[ -e files ] && mv files openwrt/files` 搬进源码树。本仓库 bugfix 已有 `files/`
（mt76 亲和性两个文件）时，`mv` 到已存在目录会**嵌套**成 `openwrt/files/files/…` 而不是合并，
清单因此不进 rootfs。归一所有权后那行 `mv` 直接删掉（不是改成 cp）。

落盘：
- master：`.gitignore:16` 的 `/files` 注释掉、末尾补 bugfix 那 9 条 PON 凭据/备份隐私忽略规则
  （`/files` 一旦跟踪，凭据与 ISP 备份就有入库风险）；`.gitattributes` 追加 `files/** text eol=lf`；
  新增 `files/etc/apk/repositories.d/customfeeds.list`。提交 9f30e5bf69 + 0c45eb1630。
- bugfix：同一条 `.gitattributes` 规则 + 同一份清单（blob 与 master 相同，87ed1c4669）。提交 4e836ad6df。
  `.gitignore` 本来就放开了 `/files` 且有隐私块，未改；改完两分支 `.gitignore` 逐字节相同。
- 编译仓库 AN7581：删 `files/` 整棵树与那行 `mv`，`.gitattributes` 删 `files/**` 与 `*.init` 两条死规则，
  两个发布脚本只改注释与报错文案、**解析路径不动**（回退分支正是源码根 `files/`，迁移后克隆即命中）。

为什么必须补 `.gitattributes`：本仓库首行是 `* -text`（不做任何行尾转换）+ 逐类型显式 LF，
原有规则没有一条覆盖 `files/` 或 `*.list`。不补的话 Windows 侧写入的 CRLF 会原样进 blob，
设备端 apk 解析 URL 会带上 `\r`。落地顺序固定：先提交规则，再添加清单文件。
实测两分支既有 overlay 文件 blob CR 均为 0，新规则不产生 renormalize 伪改动。

**两仓库必须成对推送**：只推一侧会出现中间态——本仓库已有 `files/` 而编译仓库仍执行 `mv`，
清单被嵌套丢掉；反之编译仓库已删 `files/` 而本仓库还没有，清单直接缺失。

分支选择连带后果：编译仓库固件工作流新增 `repo_branch` 输入（master / bugfix），
选 bugfix 不只带 PON 修复，还会带上本节那两个 mt76 亲和性脚本，不是纯净的 A/B 对照。

## 四、风险与验收

- 931/932 可能未经 fork CI 真正编译（hunk 错误+release 时间线），必须我们自建验证：
  WSL 容器先单包编译内核（quilt 应用全部补丁），再整镜像；命令单行由用户执行。
- 运行时验收：出厂已默认开启 flow_offloading_hw，先确认 fw4 未打 Hardware flow offloading unavailable 回退 warn，再验 IPv6 吞吐/连通、PPPoE session 稳定（如适用）、
  BT 多连接 CPU/softirq 与 CDM 计数、长时间无 NPU stall；WiFi 机型另验扫描不卡 LuCI。
- PON 补丁验收：冷启动出光上线稳定（EN7572 稳态判定）、LOID 补零方向切换（如 OLT 需要）。
- 回退：内核与 rpcd 补丁删掉重编即可，无配置耦合；PON 修复把 feeds.conf.default 改回 pbs05 上游地址即回退，不污染上游。

## 五、决策记录

- 2026-11-15 用户拍板：本仓库支持多设备，有用的补丁都纳入，用新分支维护；主题面板不要。
- 2026-11-15 分支策略定案：master 保持不动（上游变动由用户自行合入），只维护一条 bug 修复分支；不按 WiFi 拆源码分支（两类默认配置/服务无分歧，WiFi 纯 device-profile 配置轴）。否决了"master 基准镜像+集成分支"重构方案。例外：2026-11-15 接受 files/ 迁移与配套 .gitignore/.gitattributes 改动进 master（overlay 所有权归一），修复本身仍只在 bugfix。
- 2026-11-15 分支改名 port/wuziwei-fixes → bugfix（通用名，后续修复都进这里）。
- 2026-11-15 tempinfo 保留；cpuinfo 把 airoha 加进温度跳过名单，架构行去掉重复 CPU 温度（提交 30958fb44f）。cpufreq 档位 845413a386 撤掉后由 54fb4465eb 恢复，包未选入仍是死代码，用户拍板不启用、保留不动。
- 已实施：A+B 落盘并校验，C 改走 feed fork（待用户建 fork），提交于 bugfix（7eeb396c58 移植 + 30958fb44f 架构行去温度 + 845413a386 撤 cpufreq + 54fb4465eb 恢复 cpufreq 档位；不推送，用户执行）。
- [ ] PON 修复改走 feed fork 提交 + 钉 sha（待用户建 fork 并提供两个 40 位 sha；应用脚本方案作废）
- [ ] 用户侧编译+实机验收
- [x] flow_offloading_hw 出厂已默认开启（核查确认，无需改动）；改为验收硬件是否真的接受卸载
- [x] cpufreq 包不启用（用户拍板）；845413a386 撤掉后由 54fb4465eb 恢复档位，因包未选入仍是死代码，保留不动