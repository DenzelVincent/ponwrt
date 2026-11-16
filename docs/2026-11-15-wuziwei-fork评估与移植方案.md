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
| 01-pon-drivers-epon-laser-recovery.patch | EN7572 SYS_TX_READY 8 次采样确认（~140ms 稳态，防冷启动假就绪）+ EPON LLID 卡死线路重开 worker（含固件重载升级） | EN7572 部分在共享前端驱动，对本机 XG-PON 同样有效；是比 feed 10-24 旧修（33e02a3 TX readiness、a24ef29 恢复 ladder，11-07 合入 PR #11）更新的 11-11 版，epon.c 226 增 145 删属重写而非并列新增；对 fork tip 2789b970 `git apply --check` 通过 |
| 02-pon-userspace-loid-padding-wire-view.patch | LOID 左/右补零方向可选（华为等 OLT 互操作）+ 链路层原始报文展示 + pon-reopen 配套 | feed 无此功能（`pad_left`/`loid_pad` 全仓库 0 命中）；对 fork tip cce9d756 `git apply --check` 通过；含既有 luci-app-pon 的功能性 UI，非新主题面板 |
| ~~scripts/apply-pon-feed-patches.sh~~（方案作废，**已删**） | 原为 feeds install 后把两补丁打进 feed 本体，幂等（反向 check 判已应用），锚点失配报 ::error:: | **从未被接线**：固件工作流只调用 `$SCRIPT_PATCH_FEED_PACKAGES`（patch-feed-packages.sh），两仓库全文扫描无第二个调用方 → 这两个修复至今没进过任何 CI 产物。改走 fork 是它们第一次真正落地 |

落地方式：fork pbs05/openwrt-pon-drivers 与 pbs05/openwrt-pon-userspace，把两个补丁作为真实提交打进去，
bugfix 的 feeds.conf.default 改成 fork 地址 + ^<40位sha>；master 保持 pbs05 不钉。
补丁进 feed 自己的版本历史后，scripts/feeds 克隆出来就是修好的源码，不再需要应用脚本、
也不再被 feeds update 冲掉，故 patches/01、patches/02、scripts/apply-pon-feed-patches.sh 一并删除（patches/ 目录随之消失）。

状态：**已落地（2026-11-15）**。两个 fork 的 main 与 pbs05 上游 tip 逐字符相同（`git ls-remote` 对照），
补丁作为真实提交打在 tip 之上并已推送：

| fork | 基线（=上游 tip） | 修复提交 | 改动面 |
|---|---|---|---|
| DenzelVincent/openwrt-pon-drivers | `2789b970a6bfcc5ee56cee699622201b8061b67c` | `d574aedbb6dc98d02e2b772a5d3163727a381d15` | 9 文件 594 增 189 删 |
| DenzelVincent/openwrt-pon-userspace | `cce9d756742487b378749c606b30e13ee9b0f093` | `e5f85de1c146eef11bd8ff93e4cda69af6312a90` | 17 文件 659 增 38 删 |

行尾与改动面校验：两个 fork 都是 `core.autocrlf=true`、无 `.gitattributes`、工作区 CRLF / blob LF，
`git add` 归一化后 `git diff --cached --numstat` 与补丁的 `git apply --numstat` **逐行完全一致**（9 行 / 17 行），
证明没有行尾造成的整文件伪改动；26 个文件 blob CR 全为 0。
新增的 `pon-reopen`、`pon-reopen.init` 在 git 里是补丁声明的 644，Makefile 用 `INSTALL_BIN` 安装（置 755），不影响可执行性。
PKG_RELEASE bump 在补丁内：frontends 13→14、xpon 69→71、ponctl 1→2、daemons 2→3、luci-app-pon 3→4。

连带后果：publish-feed-repos.yml 固定 master，Pages 上的 pon_userspace 仍是未修版；
bugfix 固件内置的是修好且 PKG_RELEASE 已 bump 的版本，apk 不会降级，设备端安全，但 Pages 与内置版本会分叉。
本地编译注意：带 `^ref` 的 feed 在 `scripts/feeds` 里不会再 update，换 pin 后须先删 `feeds/pon_drivers` 与 `feeds/pon_userspace`。

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
- ~~patches/01-…、02-… + scripts/apply-pon-feed-patches.sh~~（方案已废并删除：改走 feed fork 真实提交，见二·C）
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

### 追加：bugfix 首次 CI 编译失败与修复（2026-11-16）

现象：编译仓库 bugfix 分支 CI 日志 `logs_118338312753/2_build-firmware.txt` 报
`ERROR: target/linux failed to build`。工作流三次重试（7826 / 7835 / 7852 行）是**同一个错**，
只有第三次带 `V=s` 打出编译器诊断（7852–7876 行）：

```
airoha_ppe.c:444:54: error: 'struct <anonymous>' has no member named 'id'
  444 |   u16 vid = data->vlan.num ? data->vlan.id : 0;
```

同日志 7454 / 7461 / 7468 行三条 `recursive dependency detected!`（qt5base-gui、fwknopd/FWKNOPD_GPG、
squeezelite-custom）是 feed 既有噪声：紧随其后 7474 行 `# configuration written to .config`，与本次失败无关。

根因：`airoha_flow_data.vlan` 是匿名结构 `{ struct { u16 id; __be16 proto; } hdr[2]; u8 num; }`，
**没有标量 `vlan.id`**（上游 v6.18 `drivers/net/ethernet/airoha/airoha_eth.h`）。
932 是 11-15 才移植进来的，四·1 的怀疑由此证实：fork 自己的 CI 没编过它。
旁证：第三次重试只重编了 `airoha_ppe.o`，gcc 整个翻译单元只报这一个错，
说明同文件 925 用的 `data->vlan.hdr[data->vlan.num - 1].id` 编译通过。

修复（提交 `8889a4e91b`，只动 932 一个文件，3 增 2 删）：
- `data->vlan.id` → `data->vlan.hdr[data->vlan.num - 1].id`，与 925:169 已在用的写法一致，
  取最外层出向 tag，与 932 自身「查不到再按 vid=0 兜底」的语义相容。
  越界安全：上游 `FLOW_ACTION_VLAN_PUSH` 在 `num == 2` 时直接返回 -EOPNOTSUPP，故 num ≤ 2。
- 该 hunk 声明 `@@ -462,11 +465,26 @@` → `+465,27`（一行拆两行，new_count +1）。

校验：`tmp/verify-patch-hunks.py` 逐 hunk 比对声明与实际行数、并核跨 hunk 累计偏移，
925 / 931 / 932 / 133 共 4 补丁 27 hunk **0 失败**；932 暂存 blob CR=0、`i/lf w/lf attr/text eol=lf`。

WSL 对照编译实测（2026-11-16，容器 `opde-builder`，源码 `/home/opde/workdir/ponwrt`）：
该检出在 `AN7581-GPON` 分支、内核 6.18.55（bugfix 是 6.18.60），且 608 补丁有用户未提交改动，
故**不切分支、不动源码树**，只在其已打满补丁的 `build_dir/…/linux-6.18.55` 上做单文件对照：
- 真实头文件核到 `airoha_eth.h:516` 的 `vlan = { hdr[2]{id,proto}; num }`；925 的同款表达式在该树 `airoha_ppe.c:390` 已编过。
- `patch --dry-run --fuzz=0` 应用 932：两个 hunk 全中，仅偏移 -37 行（该分支无 931）。
- 取 `.airoha_ppe.o.cmd` 里的原始编译命令（gcc-14.4.0_musl / aarch64），源文件换成 tmp 副本、
  输出与 dep 文件重定向到 tmp，旧/新各编一次：
  **旧 932 → 复现 CI 同一错误** `'struct <anonymous>' has no member named 'id'`（负对照成立，证明测试有效）；
  **修复后 932 → COMPILE OK**，产物 `new.o` 284848 字节、`ELF 64-bit ARM aarch64 relocatable`，
  `nm` 里有 `br_fdb_find_port` 引用（说明 CONFIG_BRIDGE 分支真编进去了）。
- 全程只写容器内 `/home/opde/tmp-932`（测后已删），源码树 `git status` 与测前逐字相同；
  脚本留档 `tmp/wsl-932-compile-test.sh`，两份补丁 md5 传输前后一致。

覆盖边界：这是**单翻译单元**编译，不是 bugfix 整内核/整镜像构建。bugfix 侧 932 能应用、
且整个 TU 只有这一个错，由 CI 日志本身证明（第三次重试只重编 airoha_ppe.o）。
整镜像与实机验收仍须用户侧执行（见四·1）。

## 四、风险与验收

- 931/932 未经 fork CI 真正编译——**932 已证实**（11-16 首次 CI 即编译失败，见三·追加）。
  932 修复后已在 WSL 做单翻译单元对照编译通过（负对照复现原错误），但**整内核/整镜像仍未构建**；
  931 连单文件验证都还没做。仍须：WSL 容器先单包编译内核（quilt 应用全部补丁），再整镜像；命令单行由用户执行。
  环境注意：容器 `opde-builder` 现有检出在 `AN7581-GPON`、内核 6.18.55，且 608 补丁有用户未提交改动，
  验 bugfix 要另开 worktree 或先保住现场，**不能直接 checkout 覆盖**。
- **未修，待拍板：932 调 `br_fdb_find_port()` 会踩 RTNL 断言。**
  上游 v6.18 `net/bridge/br_fdb.c` 的 `br_fdb_find_port()` 首行是 `ASSERT_RTNL()`，
  而 `include/linux/rtnetlink.h` 里它是无条件的 `WARN_ONCE(!rtnl_is_locked(), …)`
  （不受 CONFIG_PROVE_LOCKING 影响；本内核 PROVE_LOCKING 与 DEBUG_LOCK_ALLOC 均 not set）。
  调用链 `flow_offload_work_handler`（workqueue）→ `nf_flow_offload_tuple` →
  `block_cb->cb(TC_SETUP_CLSFLOWER, …)` → `airoha_ppe_setup_tc_block_cb`（持 `flow_offload_mutex`）→
  `airoha_ppe_foe_entry_prepare`，全程只另有 `down_read(&flowtable->flow_block_lock)`，没有 RTNL；
  本仓库 915-01 对 `nf_flow_table_offload.c` 只加 DSCP dissector，不改锁。
  `rtnl_is_locked()` 是 `mutex_is_locked(&rtnl_mutex)`（看全局有无持锁者，不是当前任务），
  所以后果是**概率性一次 WARN splat**，不是 panic；查表本身 RCU 安全（函数内部自取 rcu_read_lock）。
  真实隐患：返回的 slave netdev 在 rcu_read_unlock 之后使用且未 dev_hold，
  WiFi AP 口（phy0-ap0）随 wifi down/换信道 unregister 时有窄窗口竞态。
  候选：①先接受 WARN 与窄竞态跑验收；②桥分支里包 `rtnl_lock()`——TC flower 路径是 RTNL→flow_offload_mutex，
  反向取锁有 AB-BA 死锁风险，不建议；③**推荐**：改用本驱动已在用的 `dev_fill_forward_path()`
  （706-01 的 `net/core/dev.c` hunk 全文无 RTNL 断言，`airoha_ppe_get_wdma_info` 就在 `rcu_read_lock()` 下调用它；
  桥侧 `br_fill_forward_path` 走 `br_fdb_find_rcu`/`br_port_get_rcu`，见 675-05:55），
  属重写 932 的查口机制，需另开一轮并重新编译验证。
- 运行时验收：出厂已默认开启 flow_offloading_hw，先确认 fw4 未打 Hardware flow offloading unavailable 回退 warn，再验 IPv6 吞吐/连通、PPPoE session 稳定（如适用）、
  BT 多连接 CPU/softirq 与 CDM 计数、长时间无 NPU stall；WiFi 机型另验扫描不卡 LuCI。
- PON 补丁验收：冷启动出光上线稳定（EN7572 稳态判定）、LOID 补零方向切换（如 OLT 需要）。
- 回退：内核与 rpcd 补丁删掉重编即可，无配置耦合；PON 修复把 feeds.conf.default 改回 pbs05 上游地址即回退，不污染上游。

## 五、决策记录

- 2026-11-15 用户拍板：本仓库支持多设备，有用的补丁都纳入，用新分支维护；主题面板不要。
- 2026-11-15 分支策略定案：master 保持不动（上游变动由用户自行合入），只维护一条 bug 修复分支；不按 WiFi 拆源码分支（两类默认配置/服务无分歧，WiFi 纯 device-profile 配置轴）。否决了"master 基准镜像+集成分支"重构方案。例外：2026-11-15 接受 files/ 迁移与配套 .gitignore/.gitattributes 改动进 master（overlay 所有权归一），修复本身仍只在 bugfix。
- 2026-11-15 分支改名 port/wuziwei-fixes → bugfix（通用名，后续修复都进这里）。
- 2026-11-15 tempinfo 保留；cpuinfo 把 airoha 加进温度跳过名单，架构行去掉重复 CPU 温度（提交 30958fb44f）。cpufreq 档位 845413a386 撤掉后由 54fb4465eb 恢复，包未选入仍是死代码，用户拍板不启用、保留不动。
- 已实施：A+B 落盘并校验，提交于 bugfix（7eeb396c58 移植 + 30958fb44f 架构行去温度 + 845413a386 撤 cpufreq + 54fb4465eb 恢复 cpufreq 档位）。
- 2026-11-15 用户点名授权「把所有改动提交推送」，本轮全部提交已推送（此前各轮均为用户自行推送）。
- [x] PON 修复改走 feed fork 提交 + 钉 sha：两个 fork 已建并检出到本地，补丁作为真实提交打在 main 上
      （drivers `d574aedb…`、userspace `e5f85de1…`）并已推送；bugfix 的 feeds.conf.default 钉这两个 sha，
      patches/01、02 与 scripts/apply-pon-feed-patches.sh 已删；master 仍指 pbs05 不钉。详见二·C。
- [ ] 用户侧编译+实机验收（PON 修复此前从未进过 CI 产物，本轮是第一次真正落地，编译验证不可省）
- [x] flow_offloading_hw 出厂已默认开启（核查确认，无需改动）；改为验收硬件是否真的接受卸载
- [x] cpufreq 包不启用（用户拍板）；845413a386 撤掉后由 54fb4465eb 恢复档位，因包未选入仍是死代码，保留不动
- [x] 2026-11-16 修复 932 编译错误（`8889a4e91b`，bugfix，未推送）：只换取 VLAN 的写法 + 重算 hunk 行数，
      未动 932 的查口机制，范围严格限定在「让 bugfix 编过」。
- [ ] 2026-11-16 新发现待拍板：932 的 `br_fdb_find_port()` 在无 RTNL 的卸载 workqueue 上会触发
      `ASSERT_RTNL()` 一次 WARN，并有 slave netdev 窄窗口竞态；是否改走 `dev_fill_forward_path()` 见四·2。