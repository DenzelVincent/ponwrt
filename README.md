# PonWrt

PonWrt 基于 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt)，增加了对 Airoha AN7581 和 AN7583 PON 设备的支持。

## ⚠️ 免责声明

PonWrt 是一个用于研究和开发的开源光猫固件项目。

刷写固件或修改 PON 相关配置存在风险，可能导致设备无法启动、配置或设备数据丢失、PON 无法注册等问题。操作前请务必备份原厂固件及设备相关数据。

使用者应自行确保相关操作符合当地法律法规及运营商相关规定。请勿将本项目用于未经授权的网络接入、冒用或复制他人设备身份，或干扰运营商网络正常运行。

因刷写、配置或使用本项目产生的设备故障、网络服务异常及其他后果，由使用者自行承担。

## 支持设备

| SoC | 设备 | Profile | 原厂校准/身份数据分区 |
| --- | --- | --- | --- |
| AN7581 | FiberHome HG5382A | `fiberhome_hg5382a` | `factory` |
| AN7581 | FiberHome HG5585F CT | `fiberhome_hg5585f-ct` | `factory` |
| AN7581 | FiberHome HG5585F CU | `fiberhome_hg5585f-cu` | `factory` |
| AN7581 | Gemtek XG2010G | `gemtek_xg2010g` | `dsd` |
| AN7581 | Nokia XG-040G-MD UBI | `nokia_xg-040g-md-ubi` | `bosa`、`ri` |
| AN7581 | Nokia XG-040G-TF UBI | `nokia_xg-040g-tf-ubi` | `bosa`、`ri` |
| AN7581 | UnionMan UNG00A | `unionman_ung00a` | `reservearea` |
| AN7581 | ZNXT ZN504XG-D | `znxt_zn504xg-d` | `reservearea` |
| AN7581 | ZNXT ZN515XG-D | `znxt_zn515xg-d` | `reservearea` |
| AN7581 | H3C HM2004-DU | `h3c_hm2004-du` | `factory` |
| AN7583 | Nokia XG-040G-MF | `nokia_xg-040g-mf`、`nokia_xg-040g-mf-ubi` | `bosa`、`ri` |

## 编译

> 本分支 `AN7581-GPON` 用于 AN7581 设备的 GPON 固件构建（XGS-PON 请用 `master`）。相对 `master` **没有代码改动**，分支差异只有：
>
> - `an7581-gpon.config`：GPON 云编译产物 `.config` 的本地快照，云侧配置变更后需重新生成
> - `feeds.conf.default`：PON 两个 feed 指向本仓库 fork，内容与 pbs05 上游一致，未固定提交
>
> 此前的 GPON 代码改造已于 2026-10-19 移除：内核 PCS patch 608 与 `master` 基线完全一致，PON 驱动/用户态也没有 GPON 专属修改。

```sh
#  安装编译所需的工具链和库
sudo apt update -y
sudo apt full-upgrade -y
sudo apt install -y ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential \
  bzip2 ccache clang cmake cpio curl device-tree-compiler ecj fastjar flex gawk gettext gcc-multilib \
  g++-multilib git gnutls-dev gperf haveged help2man intltool lib32gcc-s1 libc6-dev-i386 libelf-dev \
  libglib2.0-dev libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev libncurses-dev libpython3-dev \
  libreadline-dev libssl-dev libtool libyaml-dev libz-dev lld llvm lrzsz mkisofs msmtp nano \
  ninja-build p7zip p7zip-full patch pkgconf python3 python3-pip python3-ply python3-docutils \
  python3-pyelftools qemu-utils re2c rsync scons squashfs-tools subversion swig texinfo uglifyjs \
  upx-ucl unzip vim wget xmlto xxd zlib1g-dev zstd

#  或者使用ImmortalWrt一键脚本安装依赖
sudo bash -c 'bash <(curl -s https://build-scripts.immortalwrt.org/init_build_environment.sh)'

#  拉取源码（GPON 分支；XGS-PON 用 master 分支与上游仓库）
#  浅克隆只取当前快照，编译够用；需要完整历史/版本号时去掉 --depth 1
git clone --depth 1 -b AN7581-GPON https://github.com/DenzelVincent/ponwrt.git
cd ponwrt

#  更新并安装 feeds（软件包源）
#  本分支 feeds.conf.default 的 pon_drivers / pon_userspace 指向本仓库 fork，内容与 pbs05 上游一致
#  这两行未固定提交，会跟随 fork 默认分支最新提交；需要可复现构建时在 URL 后加 ^commit
#  已存在的 feed 目录不会被 update 切换到新提交，需要时先 rm -rf feeds/<name> 再 update
./scripts/feeds update -a
./scripts/feeds install -a

#  第三方插件：lucky 已作为 feed 固定提交（见 feeds.conf.default 的 lucky 行），由上面两步自动安装
#  仅配置 A 需要再克隆 airoha-npu：仓库根目录直接放 Makefile，不是 feed 格式，缺了会被静默跳过、不报错
#  顺序要求：必须在 feeds install 之后执行（此时 luci-base 等 feed 包已就位，插件依赖才能被解析）
git clone --depth 1 https://github.com/DenzelVincent/luci-app-airoha-npu.git package/luci-app-airoha-npu

#  选择配置（A / B 二选一；两者都已默认选中 kmod-airoha-xpon / kmod-airoha-pon-frontend /
#  luci-app-pon / airoha-ponctl·pond·pon-debug，不用再进 menuconfig）
#  A. 复现 GPON 云编译产物：只编 nokia_xg-040g-md-ubi 一个 profile，PON 组件与第三方界面按 CI 全量选中
cp an7581-gpon.config .config
#  B. （可选）编译上游支持的全部 AN7581 设备：an7581.config 选了 12 个 profile，耗时远长于单设备
#     目标是 AN7583 就把下面的 an7581 换成 an7583
# cp configs/an7581.config .config
# ./scripts/kconfig.pl + configs/an7581.config configs/release.config > .config


#  开始编译
# -j$(nproc) 表示用所有 CPU 核心并行编译，加快速度
make defconfig
make download -j8 V=s
make -j$(nproc)
```

固件位于 `bin/targets/airoha/an7581/` 或 `bin/targets/airoha/an7583/`。

### 修改代码后的增量编译

本分支没有 GPON 专属代码改动，按上游常规方式增量编译即可。

**内核补丁 / 内核配置**

```sh
make target/linux/clean
make target/linux/compile -j$(nproc) V=s
make -j$(nproc)                   # 重打固件镜像
```

`target/linux/clean` 会删除当前目标的 `build_dir/target-*/linux-*`，强制重新解压并重打补丁；只做增量编译不会重新应用修改后的补丁。

**feed 软件包（PON 驱动 / 用户态）**

PON 两个 feed 没有固定提交，`feeds update` 会拉到 fork 默认分支的最新提交；切换提交或改了源码后清包重编：

```sh
rm -rf feeds/pon_drivers          # 用户态改动改为 feeds/pon_userspace
./scripts/feeds update pon_drivers
./scripts/feeds install -a
make defconfig

# 驱动：frontends 与 xpon 有符号依赖，两个包都要重编
make package/feeds/pon_drivers/airoha-pon-frontends/clean
make package/feeds/pon_drivers/airoha-xpon/clean
make package/feeds/pon_drivers/airoha-pon-frontends/compile -j$(nproc) V=s
make package/feeds/pon_drivers/airoha-xpon/compile -j$(nproc) V=s

# 用户态（按实际改动选择）：airoha-pon-daemons / airoha-ponctl /
# airoha-pon-debug / luci-app-pon / luci-app-iptv
make package/feeds/pon_userspace/airoha-ponctl/clean
make package/feeds/pon_userspace/airoha-ponctl/compile -j$(nproc) V=s

make -j$(nproc)                   # 重打固件镜像
```

仅做本地验证、暂时不推送时，可以直接改 `feeds/pon_drivers`（或 `feeds/pon_userspace`）里的源码，然后只清包重编；期间不要执行 `feeds update`。最终版本须提交到 fork 并推送，否则云编译取不到改动。

**构建记录**

每次出包至少记录以下四项，便于问题归因和跨构建对比：

```sh
git rev-parse HEAD
git -C feeds/pon_drivers rev-parse HEAD      # feed 未固定提交，记录实际拉到的提交
git hash-object target/linux/airoha/patches-6.18/608-net-pcs-airoha-add-AN7581-PON-line-modes.patch
sha256sum bin/targets/airoha/an7581/*.itb
```

## 刷入

使用 [AN758x-Stock2UBI](https://github.com/pbs05/an758x-stock2ubi) 备份原厂闪存并安装 UBI 布局。启动镜像和 Web 恢复界面由 [AN758x U-Boot](https://github.com/pbs05/uboot-an758x) 提供。

刷入 PonWrt 后，通过 U-Boot Web 或 LuCI 的"网络 → PON → 配置 → PON board data"恢复原厂校准和身份数据。烽火 `factory` 需要先使用 [FiberHome Factory](https://github.com/pbs05/fiberhome-factory) 转换；转换后的烽火数据、`reservearea` 和 `dsd` 写入 PonWrt 的 `factory` 卷；Nokia 的 `bosa` 和 `ri` 写入同名卷。
