# 刷机指南 — SM-C7000 LineageOS 16.0 (开发中)

> ⚠️ **开发阶段产物**：目前只有 `boot.img`（内核+ramdisk）稳定产出，
> `system.img` 仍在 CI 迭代中。本指南描述已可用部分的操作。
> 刷机有风险，数据自行备份；EFS 必须先备份。

## 前提（必须）

1. **备份 EFS**（TWRP → Backup → 勾选 EFS/Modem/Efs，存到 SD 卡/电脑）——
   IMEI/基带数据，刷挂无法恢复。
2. 确认设备能解锁（开发者选项 → OEM 解锁；国行部分批次锁定则无法继续）。
3. 已装第三方 TWRP（SM-C7000 有现成 TWRP 资源）。

## 产物来源

GitHub Actions：`AwdndWindowsServer/c7ltechn-los16` → Actions → 最新 run → Artifacts

| Artifact | 内容 | 状态 |
|---|---|---|
| `c7ltechn-kernel-N` | `Image.gz-dtb`（内核） | ✅ 稳定 |
| `c7ltechn-boot-N` | `boot.img`（内核+ramdisk） | ✅ 稳定 |
| `c7ltechn-los16-N` | boot+recovery+system 完整包 | 🚧 迭代中（2 核 runner 超时） |

## 刷 boot.img（已验证可用部分）

### 方法 A：TWRP
1. 下载 `c7ltechn-boot-N` artifact，解压得到 `boot.img`。
2. 手机进 TWRP。
3. Install → Install Image → 选 `boot.img` → 选择分区 **Boot** → 滑动刷入。
4. 重启（不勾选"重新安装 TWRP"）。

### 方法 B：Odin（需打包 tar）
```bash
tar -H ustar -c boot.img > c7ltechn-boot.tar
```
Odin → AP 选该 tar → 刷入（仅刷 BOOT 分区，不动其他分区）。

### 方法 C：fastboot（若可用）
```bash
fastboot flash boot boot.img
```

## 预期现象与排查（目前阶段）

- **能开机进 recovery/系统**：继续等 system.img。
- **黑屏/重启循环**：目前预期内——内核已带 c7ltechn 板级支持，
  但 display/panel 驱动仍需调试验证（M2b 进行中）。
- **无信号/相机/指纹不可用**：预期内，RIL/相机/指纹是后续里程碑。

## 刷回官方

用官方 `C7000ZCS3CRJ1` Odin 四件套刷回（BOOTLADER/AP/CP/CSC），
或 TWRP 恢复你之前备份的 boot 分区。
