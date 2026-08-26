#!/bin/bash
#
# port-rom.sh — 同平台(msm8953)二进制移植流水线：mido/LOS 基座 ROM → SM-C7000 (c7ltechn)
#
# 流程：取基座(用户上传的 release zip) → 解包 system → 合并 C7 vendor → 换 C7 boot → 注入属性 → 重组镜像
#
set -euo pipefail

REPO=AwdndWindowsServer/c7ltechn-los16
VENDOR_REPO=AwdndWindowsServer/c7ltechn-vendor
BASE_RELEASE_TAG=mido-base-rom
C7_VENDOR_LOCAL=/root/c7/port/vendor/system/vendor   # 本机 dump（优先）

OUT=/root/c7/port-out
WORK=/tmp/port-work
mkdir -p "$OUT" "$WORK"
rm -rf "$WORK"/*

echo "== [1/7] 获取 C7 boot.img（从 Actions artifact 最新 boot 产物）"
BOOT_ART=$(gh api "repos/$REPO/actions/artifacts" --jq '.artifacts[] | select(.name | startswith("c7ltechn-boot")) | .id' 2>/dev/null | head -1)
if [ -n "$BOOT_ART" ]; then
  cd "$WORK" && gh api "repos/$REPO/actions/artifacts/$BOOT_ART/zip" > boot.zip
  python3 -c "
import zipfile
z=zipfile.ZipFile('$WORK/boot.zip'); z.extractall('$WORK')
" && cp "$WORK/boot.img" "$OUT/boot.img"
  echo "    boot.img: $(stat -c%s "$OUT/boot.img") bytes (C7 内核+ramdisk)"
else
  echo "    !! 未找到 boot artifact"; exit 1
fi

echo "== [2/7] 获取基座 ROM（用户上传的 release zip）"
gh release download "$BASE_RELEASE_TAG" -R "$REPO" -D "$WORK/base" 2>&1 | head -2
BASE_ZIP=$(find "$WORK/base" -name '*.zip' | head -1)
[ -z "$BASE_ZIP" ] && { echo "!! release 里没有 zip — 等用户上传"; exit 1; }
echo "    基座: $(basename "$BASE_ZIP") ($(du -h "$BASE_ZIP" | cut -f1))"

echo "== [3/7] 解包基座"
cd "$WORK" && unzip -o -q "$BASE_ZIP" -d base-x
ls base-x/ | head

echo "== [4/7] 提取 system（sparse→raw→目录）"
SYSTEM_IMG=$(find base-x -name 'system.img' | head -1)
[ -z "$SYSTEM_IMG" ] && { echo "!! 基座无 system.img"; exit 1; }
simg2img "$SYSTEM_IMG" system.raw 2>/dev/null || cp "$SYSTEM_IMG" system.raw
mkdir -p sys-mnt && mount -o loop,ro system.raw sys-mnt 2>/dev/null && { cp -a sys-mnt/. sys/; umount sys-mnt; } || {
  mkdir -p sys && debugfs -R "rdump / sys/" system.raw >/dev/null 2>&1 || { echo "!! 提取 system 失败（需 root）"; exit 1; }
}
echo "    system 文件数: $(find sys -type f | wc -l)"

echo "== [5/7] 合并 vendor（mido 公共 HAL + C7 覆盖）"
VENDOR_IMG=$(find base-x -name 'vendor.img' | head -1)
if [ -n "$VENDOR_IMG" ]; then
  simg2img "$VENDOR_IMG" vendor.raw 2>/dev/null || cp "$VENDOR_IMG" vendor.raw
  mkdir -p v-mnt && mount -o loop,ro vendor.raw v-mnt 2>/dev/null && { cp -a v-mnt/. vnd/; umount v-mnt; } || {
    mkdir -p vnd && debugfs -R "rdump / vnd/" vendor.raw >/dev/null 2>&1 || true
  }
  echo "    mido vendor 文件数: $(find vnd -type f | wc -l)"
else
  mkdir -p vnd; echo "    (基座无独立 vendor，用 /system/vendor)"
fi
# C7 覆盖
if [ -d "$C7_VENDOR_LOCAL" ]; then
  cp -a "$C7_VENDOR_LOCAL/." vnd/
  echo "    C7 vendor 覆盖完成（覆盖后文件数: $(find vnd -type f | wc -l)）"
else
  echo "    !! 本地 C7 vendor 不存在，从 vendor 仓库拉"
  cd "$WORK" && git clone --depth 1 "https://github.com/$VENDOR_REPO.git" vrepo 2>/dev/null && cp -a vrepo/vendor/samsung/c7ltechn/proprietary/vendor/. vnd/ || true
fi

echo "== [6/7] 注入 C7 属性到 build.prop"
BP=sys/build.prop
if [ -f "$BP" ]; then
  sed -i \
    -e 's/^ro.product.model=.*/ro.product.model=SM-C7000/' \
    -e 's/^ro.product.brand=.*/ro.product.brand=samsung/' \
    -e 's/^ro.product.device=.*/ro.product.device=c7ltechn/' \
    -e 's/^ro.product.name=.*/ro.product.name=c7ltezc/' \
    -e 's/^ro.product.manufacturer=.*/ro.product.manufacturer=samsung/' \
    -e 's/^ro.build.fingerprint=.*/ro.build.fingerprint=samsung\/c7ltezc\/c7ltechn:8.0.0\/R16NW\/C7000ZCS3CRJ1:user\/release-keys/' \
    "$BP" 2>/dev/null || true
  grep -E 'ro.product.(model|device|name)=' "$BP"
fi

echo "== [7/7] 重组镜像"
# system: 目录 → ext4（大小按内容+余量）
SYS_SIZE=$(( $(du -sm sys | cut -f1) + 300 ))
mke2fs -q -t ext4 -L system -d sys "system-new.img" "${SYS_SIZE}M" 2>/dev/null && cp system-new.img "$OUT/system.img" || cp system.raw "$OUT/system.img"
echo "    system.img: $(du -h "$OUT/system.img" | cut -f1)"
# vendor: 目录 → ext4
VND_SIZE=$(( $(du -sm vnd | cut -f1) + 100 ))
mke2fs -q -t ext4 -L vendor -d vnd "vendor-new.img" "${VND_SIZE}M" 2>/dev/null && cp vendor-new.img "$OUT/vendor.img"
echo "    vendor.img: $(du -h "$OUT/vendor.img" 2>/dev/null | cut -f1)"

echo ""
echo "===== 产物（$OUT/）====="
ls -la "$OUT/"
echo "刷机（TWRP）：boot.img → Boot；system.img → System；vendor.img → Vendor"
