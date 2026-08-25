# SM-C7000 (c7ltechn) — Android 9/10 移植手册

> 目标设备：Samsung Galaxy C7（SM-C7000，代号 `c7ltechn`，国行 `c7ltezc`）
> 平台：Qualcomm MSM8953（骁龙 625）/ arm64 + 32-bit 兼容
> 基础固件：C7000ZCS3CRJ1（Android 8.0.0 / R16NW / 内核 3.18.71-14188519，2018-10-11）
> 本手册基于工作区 `/root/c7/port/` 下从 `c7extract.zip` 提取的完整 system/boot 分析编写。

---

## 0. 结论摘要

| 项目 | 结论 |
|---|---|
| 首选目标 | **LineageOS 16.0（Android 9）** — 与 8.0 的 HAL 接口差异最小，Samsung msm8953 闭源驱动可复用度最高 |
| 进阶目标 | LineageOS 17.1（Android 10）— 需 HIDL/适配大改，建议在 LOS16 跑通之后再做 |
| 可行性 | **硬件驱动条件已具备**：本 dump 已提取全部闭源 blob（vendor 1758 项 + system 481 项候选）。主要工作量在 **RIL（sec-ril）、相机 HAL、指纹 HAL、SELinux 策略** 四块 |
| 硬性前提 | ① 设备能解锁 bootloader（`ro.oem_unlock_supported=1`，但国行部分批次出厂锁定，见 §1）② 一台 ≥16GB 内存、≥200GB 磁盘的 Linux 构建机（本工作区资源不足以编译 AOSP/LOS） |
| 本套件提供 | vendor/system 完整驱动清单、boot.img/ramdisk 拆解资料、fstab/init/相机/音频配置分析、设备树骨架模板、本手册 |

---

## 1. 前置条件（先做，别跳过）

### 1.1 设备侧
1. **确认能解锁**：设置→开发者选项→OEM 解锁。国行骁龙 Samsung 若无此开关，参考 [XDA 上的讨论](https://xdaforums.com/t/samsung-c7-sm-c7000-factory-locked-failed-root.4153913/)——部分出厂锁定批次无法解锁/root，**这种情况移植无从谈起**。
2. 刷第三方 TWRP（[getdroidtips 有 C7 的 TWRP 教程](https://www.getdroidtips.com/twrp-recovery-samsung-galaxy-c7/)）。
3. **进 TWRP 全量备份 EFS**（`/dev/block/bootdevice/by-name/efs`、`persist`、`modemst1/2`）——IMEI/基带数据，刷挂救命的。
4. 备份当前官方系统可用的 modem/dsp/tz 等分区镜像（本 dump 没有这些分区，见 §6.3）。
5. 记录当前基带版本（设置→关于→基带版本，应与 C7000ZCS3CRJ1 匹配）。

### 1.2 构建机
- Ubuntu 18.04/20.04 x86_64，**内存 ≥16GB**（LOS16 建议 16GB，swap 另加 16GB），磁盘 ≥200GB（源码+ccache+产物），网络可访问 android.googlesource.com / github。
- 依赖与 Java 版本严格按 [LineageOS 构建 wiki](https://wiki.lineageos.org/devices/mido/build/)（LOS16 用 OpenJDK 8/9，LOS17.1 用 11）。
- 若本机条件允许，也可在云构建（GitHub Actions / CI）里跑 `m bacon`。

---

## 2. 架构选型与参考树

```
基础设备树参考（同平台，官方支持）：
  device/xiaomi/mido          — 官方 LOS 16/17.1/18.1，msm8953，内核/HAL 适配最成熟
  kernel/xiaomi/msm8953       — LOS 维护的 3.18 内核（android-9.0 分支），含 msm8953 板级支持
Samsung msm8953 私有部分参考：
  中文社区 Galaxy C5/C7 非官方 LOS 树（若有），或按本手册 §4/§5 自行适配
内核源码：
  opensource.samsung.com → SM-C7000 (c7ltechn) → Android 8.0 (OREOMR1) 3.18 内核源码
```

**选型理由**：mido 与 C7 同为 msm8953 + 3.18 内核 + 非 Treble 时代 HAL，内核板级差异主要在设备树；Samsung 私有部分（sec-ril、相机、指纹）不在 mido 树里，必须从本 dump 的 blob + Samsung 内核源码适配。**不要选 Exynos 参考树**（如 a5y17lte 是 Exynos 7880，完全不通用）。

---

## 3. LOS 源码树布局

```
~/los16/
├── device/samsung/c7ltechn/        ← 本套件 §4 模板（自行落地）
├── kernel/samsung/msm8953/         ← 或直接 kernel/xiaomi/msm8953 + 移植补丁
├── vendor/samsung/c7ltechn/        ← proprietary blobs（§6 接入）
├── vendor/lineage/ ...             ← repo 初始化自带
└── .repo/local_manifests/c7.xml    ← 声明以上三个仓库
```

初始化命令（示例）：
```bash
repo init -u https://github.com/LineageOS/android.git -b lineage-16.0
mkdir -p .repo/local_manifests
# 编辑 c7.xml 加入 device/samsung/c7ltechn、kernel/...、vendor/samsung/c7ltechn
repo sync -j8
```

---

## 4. 设备树 device/samsung/c7ltechn

### 4.1 文件清单
| 文件 | 职责 |
|---|---|
| `AndroidProducts.mk` | 注册 `lineage_c7ltechn` 产品 |
| `lineage_c7ltechn.mk` | 产品定义：继承 mido 公共部分、声明设备名/厂商 |
| `BoardConfig.mk` | 板级配置：分区、ABI、boot 镜像参数（本节全部关键值） |
| `device.mk` | 设备特性：PRODUCT_PACKAGES、init 脚本、fstab、权限文件 |
| `extract-files.sh` / `setup-makefiles.sh` | 从 dump 提取 blob → `vendor/samsung/c7ltechn/proprietary/`，再生成 makefile 片段 |
| `proprietary-files*.txt` | 闭源清单（本套件 `port/out/` 已生成） |
| `rootdir/` | fstab.qcom、init.*.rc、ueventd.rc（从本 dump ramdisk/vendor 移植） |
| `sepolicy/` | SELinux 增量策略（Samsung 域） |
| `overlay/` | 资源覆盖（状态栏/机型名等，可选） |

### 4.2 本设备关键板级参数（BoardConfig.mk 要点）

```makefile
# —— 平台 ——
TARGET_BOARD_PLATFORM := msm8953
TARGET_BOARD_PLATFORM_GPU := qcom-adreno506
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := cortex-a53
# 32 位兼容（系统含大量 32 位 HAL/库）
TARGET_2ND_ARCH := arm
TARGET_2ND_ARCH_VARIANT := armv7-a-neon
TARGET_2ND_CPU_ABI := armeabi-v7a
TARGET_2ND_CPU_ABI2 := armeabi
TARGET_2ND_CPU_VARIANT := cortex-a53
TARGET_USES_64_BIT_BINDER := true

# —— 分区（C7 无独立 vendor/dtb —— 非 Treble）——
BOARD_VENDORIMAGE_PARTITION_SIZE := 0        # vendor 内容进 /system/vendor（与官方一致）
BOARD_BOOTIMAGE_PARTITION_SIZE := 33554432   # 32MiB（按 dump 的 boot.img 尺寸；最终以 Odin PIT 为准）
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 33554432  # 约 32MiB，PIT 校准
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 3221225472   # ~3GiB，PIT 校准（官方 system 解包约 3.2GB）
BOARD_USERDATAIMAGE_PARTITION_SIZE := 26843545600 # 按你机器容量（32/64GB 版）从 PIT 取

# —— boot 镜像 ——
BOARD_KERNEL_BASE := 0x80000000
BOARD_KERNEL_PAGESIZE := 2048               # 与 boot.img 头部一致（实测 page_size=2048）
BOARD_KERNEL_CMDLINE := ...                 # 从 stock boot.img 头部读（本 dump 头部 cmdline 为空，Samsung 用默认）
BOARD_MKBOOTIMG_ARGS := --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 --second_offset 0x00f00000 --tags_offset 0x00000100
# （msm8953 标准偏移，以 mido 树为准微调；三星 boot.img 实测 header 中 kernel_addr=0x00800080 等值需复核）

# —— 存储 ——
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE := ext4
# forceencrypt=footer 必须在 fstab 中移除/改 encryptable（见 §4.3）

# —— 内核 ——
TARGET_KERNEL_SOURCE := kernel/samsung/msm8953   # 或 kernel/xiaomi/msm8953
TARGET_KERNEL_CONFIG := c7ltechn_chn_defconfig   # 从 Samsung 开源内核 arch/arm64/configs/ 找实际文件名
```

### 4.3 rootdir / fstab（来自本 dump，关键差异）

`vendor/etc/fstab.qcom`（已在 dump 中，路径 `vendor/system/vendor/etc/fstab.qcom`）——移植时**必须修改**：

```diff
- /dev/block/bootdevice/by-name/userdata  ...  forceencrypt=footer,quota  wait,check,forceencrypt=footer,quota
+ /dev/block/bootdevice/by-name/userdata  ...  encryptable=footer,quota    wait,check,encryptable=footer,quota
```
（否则 LOS 首启会强制加密并可能抹数据；LOS 默认关闭强制加密）

- `bootdevice` 符号链接：`/dev/block/platform/soc/7824900.sdhci`（init.target.rc 中 `wait ... soc/${ro.boot.bootdevice}`）
- 挂载点清单：`/system`、`/data`、`/cache`、`/persist`、`/efs`、`/dsp`（dsp 分区）、`/firmware`（apnhlos 分区，vfat）、`/firmware-modem`（modem 分区，vfat）、`/preload`（hidden 分区）、`/frp`（config）、`/misc`
- 分区号（mmcblk0pN，来自 partitions.txt）：boot=p24, recovery=p25, system=p38, cache=p39, userdata=p40, modem=p34, dsp=p33, apnhlos=p35, efs=p16, persist=p28, hidden=?(vold 用 by-name/hidden)

### 4.4 各硬件模块适配要点（均为本 dump 实测）

**RIL（最难，决定"日常可用"）**
- 依赖：`libril.so`（Samsung 改版）、`libsec-ril.so` + `libsec-ril-dsds.so`（DSDS 双卡）、`libqmi*`、`libqcril*`、`rild` 及其 `init.qcom.rc` 启动项
- 设备树需：`PRODUCT_PACKAGES += libsec-ril libsec-ril-dsds libril ...`；`TARGET_RIL_VARIANT` 不用 AOSP 默认路径，直接覆盖 `/vendor/lib(64)/libril.so` 与 `rild`；Samsung 版 libril 依赖 `vendor.sec.rild.libpath` 属性（build.prop 已有）
- 属性（build.prop 实测）：`vendor.sec.rild.libpath=/vendor/lib64/libsec-ril.so`、`...libpath2=...dsds.so`、`ro.telephony.default_network=9,1`、`persist.radio.multisim.config=dsds`
- 调试：`adb logcat -s RILC RILJ qcril`；rild 崩溃多半是 libril 与平台库版本不匹配
- 参考：mido 的 `init.qcom.rc` 中 rild 启动段可直接搬（同 QC 平台），只换 Samsung 库

**相机（HAL 栈：QC mm-camera + Samsung 封装）**
- blob：`camera.msm8953.so`、`libmmcamera_interface.so`、`libmm-qcamera.so`、`vendor.samsung.hardware.camera.provider@2.4-impl.so`、`libSisoCameraDistortionEffects.so`、`libdualcameraddm.so`、`libjni_dualcamera.so` 等
- 配置：`vendor/etc/camera/`（`msm8953_camera.xml` + 各传感器 chromatix/module_info：s5k3p3sx(16MP 后置)、s5k3p8sx、s5k4h5yc、s5k5e3yx、sr846、imx241、imx258、sr259）
- 相机传感器驱动在**内核**（Samsung 源码板级 dts + mm-camera 驱动），必须用 Samsung 内核源码补丁
- 相机 HAL 对 `android.hardware.camera.*` 接口版本敏感——LOS16 用 Camera2 + provider 2.4/2.6，若 HAL 只认 2.4 需在设备树固定接口版本

**指纹（Samsung 私有，风险高）**
- blob：`vendor/lib(64)/hw/fingerprint.default.so`，导出符号 `ss_fingerprint_*`（Samsung Secure Fingerprint，走 TZ/secure world）
- 需要：内核驱动（Samsung 源码）+ TZ 固件（tz 分区，官方固件提取）+ `android.hardware.biometrics.fingerprint@2.1` 接口
- LOS 侧用 `FINGERPRINT` 兼容层：确认 mido 树 `hardware/qcom` 或 `vendor/lineage` 的 fingerprint 兼容实现能否直接挂 Samsung HAL；不行则参考 Samsung 8.0 的 `fingerprintd` 适配
- **风险**：若 TZ 版本不匹配，指纹 HAL 可能直接 crash——这是"日常可用"目标里最不确定的一项

**NFC（NXP PN548AD）**
- blob：`libpn548ad_fw.so`、`vendor/lib(64)/hw/nfc_nci.default.so`、`vendor.nxp.nxpnfc@1.0-impl.so`、`com.qualcomm.qti.ant@1.0-impl.so`、`libnfc-nci.so`（system）
- LOS 用 AOSP `packages/apps/Nfc` + NCI 栈，需确认 AOSP NCI 库与 NXP HAL 的版本兼容；`nfc_nci.default.so` 由设备树 `PRODUCT_PACKAGES` 提供
- 参考：`android_hardware_nxp` 仓库（NXP NFC HAL 开源适配）

**音频（QC + Samsung 定制策略）**
- blob：`audio.primary.msm8953.so`、`audio_platform_info.xml`（+`_extcodec.xml`）、`*_cal.acdb`（QC AudioCal，扬声器/听筒/耳机/HDMI 各一套）、`Tfa9897.cnt`（NXP TFA9897 功放配置）、`audio_policy_configuration_sec.xml`（Samsung 定制策略，含通话路由）
- 移植时：`audio_policy_configuration.xml` 用 LOS 默认生成，但**通话音量/路由参数以 `_sec.xml` 为准**——音频策略是 Samsung 8.0 特有的坑
- 喇叭/听筒校准数据在 `vendor/etc/*_cal.acdb`，若丢失会无声/破音

**传感器（QC + Broadcom BHY 传感器中枢）**
- blob：`sensors.msm8953.so`（QC）、`bhy_firmware/ram_patch.fw`（博通 BHY 固件）、`/vendor/bin/hw/` 传感器服务
- 内核需 BHY 驱动（Samsung 源码）

**显示/GPU（QC SDM）**
- blob：`hwcomposer.msm8953.so`、`gralloc.msm8953.so`、`vulkan.msm8953.so`、`/vendor/firmware/a530*`（Adreno 530 GPU 固件）
- 面板驱动在内核（Samsung 源码 dts）——屏幕不亮/花屏先查这里

**Wi-Fi / 蓝牙 / GNSS / 电源 / 健康**
- WiFi：`/vendor/firmware/wlan/prima/*`（WCNSS cfg/nv）+ `wcnss_service`/`wcnss_filter`/`macloader` + `init.wifi.rc`；LOS16 用 `android.hardware.wifi@1.0` 适配
- 蓝牙：`bluetooth.default.so`（博通）+ `rampatch_tlv*.img` + `nvm_tlv*.bin` + `ice40.bin`（firmware 目录）
- GNSS：`vendor.qti.gnss@1.0-impl.so`、`vendor.samsung.hardware.gnss@1.0-impl.so`、`gps.conf`/`izat.conf`/`flp.conf`（vendor/etc）
- 电源：`power.qcom.so`；健康：`android.hardware.health@1.0-service`

### 4.5 SELinux
- stock 策略为 `SEPF_SM-C7000_8.0.0_0015`，**不能直接用于 LOS**（policy 版本/域不兼容）
- 从 mido/LOS 基础策略出发，增量添加 Samsung 域：`sec-ril`（rild 的 Samsung 库）、`ss_`（Secure Storage）、`knox`/`tima`、`bhy`（传感器中枢）、`ss_esep`（eSE）等
- 调试：`adb shell dmesg | grep avc`，逐个放行；首启建议 `setenforce 0` 排查功能性，稳定后再 enforcing

---

## 5. 内核

1. **获取源码**：[opensource.samsung.com](https://opensource.samsung.com) 搜索 SM-C7000 → 下载 Android 8.0 内核源码（3.18.71 基线，对应本 dump 的 `3.18.71-14188519`）。
2. **策略**：以 `kernel/xiaomi/msm8953`（LOS android-9.0 分支）为基底（含 LOS 需要的安全/稳定性补丁），把 Samsung 板级内容移植过来：
   - `arch/arm64/boot/dts/qcom/`：c7ltechn 板级 dts（面板、触摸、传感器、指纹、电池、音频 codec 节点）
   - Samsung 特有驱动：`drivers/input/fingerprint/`（ss 指纹）、BHY 传感器驱动、Samsung 电池/充电驱动
   - 模块配置：`CONFIG_WIL6210`、`CONFIG_BT_POWER` 等保持与 stock 一致（stock `/system/lib/modules/*.ko` vermagic=3.18.71-14188519，自编内核若 vermagic 一致可直接用 stock 模块，但建议重新编译）
3. **defconfig**：`arch/arm64/configs/c7ltechn_chn_defconfig`（源码树内）。**本 dump 的 boot.img 未嵌 IKCONFIG，无法从镜像提取完整 .config**——以源码 defconfig 为准。
4. **必改**：`CONFIG_DM_VERITY`（可留但 fstab 去 verify）、`CONFIG_ANDROID` 相关保持、关闭 Samsung 特有安全（`CONFIG_SEC_RKP`/`CONFIG_KNOX` 视 LOS 需要裁剪，注意 TZ 侧校验）。
5. 产物：`boot.img`（kernel + ramdisk + dtb appended，3.18 无独立 dtbo）。

---

## 6. Vendor Blob 接入（本套件直接可用）

### 6.1 已生成的清单（`/root/c7/port/out/`）
| 文件 | 内容 |
|---|---|
| `proprietary-files-vendor.txt` | **1758 项**，全部 vendor blob（= 官方 `/system/vendor/*` 全量） |
| `proprietary-files-system.txt` | **481 项** system 侧候选（按关键字筛选，**需人工评审**：部分如 libcamera_client/libsensorservice 是 AOSP 提供，应删除） |
| `proprietary-files.txt` | 上述合并 |
| `vendor-inventory.txt` | vendor 全部条目 + 类型/大小/链接目标 |

### 6.2 接入流程
```bash
# 1) 把本套件复制到构建机
# 2) 在设备树中放 extract-files.sh，指向 dump 根（/root/c7/port/vendor/system）：
#    路径约定：清单中 vendor/* → dump 的 /system/vendor/*；system/* → dump 的 /system/*
#    注意 46 个绝对符号链接（如 vendor/app/RootPA/lib/arm/libcommonpawrapper.so -> /system/vendor/lib/...）
#    提取时必须用 cp -a / tar 保留链接属性
# 3) 运行 extract-files.sh 填充 vendor/samsung/c7ltechn/proprietary/
# 4) 运行 setup-makefiles.sh 生成 vendor 模块 makefile
```
> 由于 C7 无独立 vendor 分区（`BOARD_VENDORIMAGE_PARTITION_SIZE := 0`），blob 编译后安装到 `/system/vendor`，与官方布局一致。

### 6.3 本 dump 缺失的分区固件（必须从官方 Odin 固件补）
| 分区 | 内容 | 用途 |
|---|---|---|
| `modem` (p34) | NON-HLOS.bin | 基带固件——无它无信号 |
| `dsp` (p33) | adsp 固件 | 音频/传感器 DSP |
| `tz` (p5) | TrustZone | 指纹/DRM/secure world |
| `rpm` (p4)、`aboot` (p6)、`devcfg` (p19) | 底层固件 | 引导链 |
| `apnhlos` (p35) | wcnss 固件 | WiFi/BT 校准 |

获取：SamMobile/官方 C7000ZCS3CRJ1 四件套 Odin tar，用 Odin/heimdall 单独刷入**且保持与 system 兼容的基带版本**；**切勿**在移植过程中刷官方 system 覆盖我们的构建产物。这些分区属于"刷机环境"，不属于 ROM 构建产物，LOS 编译不需要，但设备运行必需。

---

## 7. 编译

```bash
source build/envsetup.sh
breakfast c7ltechn            # 或 lunch lineage_c7ltechn-userdebug
m bacon -j$(nproc)            # 首编建议 -j4~8 + ccache
```
产物：`out/target/product/c7ltechn/boot.img`、`system.img`、`recovery.img`。
首编注意：ccache 建议 50GB+；3.18 内核单独 `m bootimage` 可加速迭代。

---

## 8. 刷机与首启调试

### 8.1 刷机（TWRP）
1. TWRP 备份 EFS/persist/modemst1/2（再次强调）。
2. 刷入顺序：`boot.img` → `system.img` → `recovery.img`（保留官方 modem/dsp/tz 不动）。
3. `adb shell setenforce 0` 允许的话先关 SELinux 排查；重启循环则 `adb logcat -b all` / `dmesg` 定位。

### 8.2 调试速查
| 症状 | 排查 |
|---|---|
| 不开机/循环 | `adb logcat`、`dmesg`；查 init 脚本里 import 的文件是否存在；fstab 路径是否正确 |
| 无信号 | `logcat -s RILC RILJ`、`getprop | grep ril`；确认 libril/sec-ril 加载、`vendor.sec.rild.libpath` 属性 |
| 相机黑屏 | 相机 HAL crash 日志；chromatix/模块配置路径；内核 mm-camera 驱动 |
| 指纹不可用 | 指纹 HAL 日志；TZ 版本；`/dev/` 节点权限 |
| 无声 | acdb/audio_policy 配置；TFA9897 功放；`logcat -s AudioFlinger AudioPolicyManager` |
| WiFi 打不开 | wcnss_service/macloader；WCNSS nv 配置；`logcat -s WifiHW` |
| SELinux 拒绝 | `dmesg | grep avc` 逐条补策略 |

### 8.3 日常可用验证清单（逐项打勾）
- [ ] 通话（含免提、通话音量）、短信
- [ ] 4G/移动数据、双卡切换（DSDS）
- [ ] WiFi（含 5GHz）、热点
- [ ] 蓝牙（音频 A2DP/通话）
- [ ] GPS 定位
- [ ] 相机：前后摄、拍照、录像、闪光灯
- [ ] 指纹解锁
- [ ] NFC（读卡）
- [ ] 音频：扬声器、耳机、麦克风、铃声
- [ ] 传感器：距离（通话息屏）、光线、加速度、陀螺仪、磁力计
- [ ] 振动、按键、指纹/Home
- [ ] 充电、电池曲线、省电
- [ ] 息屏/锁屏/闹钟/通知
- [ ] 存储：内置存储、OTG、SD（C7 为单卡+SIM2 位）

---

## 9. 风险与注意

1. **EFS 是命根子**：IMEI/基带校准，刷前必备份，刷挂无法恢复（除售后）。
2. **forceencrypt 处理**：fstab 改错会抹数据或卡加密循环。
3. **国行锁机风险**：解锁失败一切免谈；先用 TWRP 实测能否刷入。
4. **基带敏感性**：Samsung RIL 与基带版本强耦合，保持 C7000ZCS3CRJ1 基带。
5. **非 Treble 限制**：不要直接套用 Treble 设备的 vendor 分区方案；17.1 需额外做 HAL 接口升级（audio 2.0→、camera provider 2.4→2.6 等），建议 LOS16 稳定后再上。
6. **blob 版本耦合**：vendor 库与 framework 版本必须同代（8.0 blob + 9.0 framework 需要逐个验证接口），`libcamera_client` 等 AOSP 覆盖库不要从 dump 带出。
7. **时间预期**：按 msm8953 平台经验，单人熟悉流程后：内核+设备树 bring-up 1~2 周；RIL/相机/指纹逐项 2~4 周；稳定 daily 用 1~2 个月量级（视可用参考树而定）。

---

## 10. 本套件文件索引

```
/root/c7/
├── c7extract.zip                      # 原始固件包（boot.img + system.tar.gz + build.prop + partitions.txt）
├── c7extract/                         # 解压后的原始文件
└── port/
    ├── vendor/system/                 # system 分区完整解包（3.2GB，blob 提取源）
    ├── boot/                          # boot.img 拆解
    │   ├── kernel.zimage              # 压缩内核（3.18.71-14188519）
    │   └── ramdisk/                   # ramdisk 解包（init.rc、default.prop、SELinux 策略文件、sbin）
    ├── out/
    │   ├── proprietary-files-vendor.txt   # ★ vendor 驱动全量清单（1758 项）
    │   ├── proprietary-files-system.txt   # ★ system 候选清单（481 项，需评审）
    │   ├── proprietary-files.txt          # ★ 合并清单（LOS extract-files.sh 输入）
    │   └── vendor-inventory.txt           # vendor 条目明细（类型/大小/链接）
    ├── device/                        # 设备树骨架模板（见 README）
    └── docs/porting-guide.md          # 本手册
```
