# c7ltechn-los16

LineageOS 16.0 (Android 9) port for the **Samsung Galaxy C7 (SM-C7000, `c7ltechn`)**,
built in CI on **GitHub Actions**.

- Platform: Qualcomm MSM8953 (Snapdragon 625), arm64 + 32-bit compat
- Kernel: 3.18 `lineageos_c7ltechn_defconfig` (from the Galaxy-MSM8953 kernel tree)
- Stock base: `C7000ZCS3CRJ1` (Android 8.0.0, non-Treble, **no vendor partition** — `/vendor` is a symlink to `/system/vendor`)

## Repository layout

| Path | Contents |
|---|---|
| `device/samsung/c7ltechn/` | LineageOS 16.0 device tree (BoardConfig, device.mk, system.prop, rootdir, vintf manifests, mkbootimg) |
| `manifest/c7ltechn-16.0.xml` | Local manifest for `repo init` / CI |
| `tools/gen-vendor-mk.py` | Regenerates the vendor makefile from the blob tree |
| `tools/system-blobs.txt` | Curated list of system-side proprietary blobs |
| `.github/workflows/build.yml` | CI: sync LOS 16.0 + build + upload artifacts |

Vendor blobs live in a separate repository:
[`AwdndWindowsServer/c7ltechn-vendor`](https://github.com/AwdndWindowsServer/c7ltechn-vendor)
(`vendor/samsung/c7ltechn/` — proprietary blobs + generated `c7ltechn-vendor.mk`).

## How to build

### On GitHub Actions (recommended)

Push to this repo, or use `workflow_dispatch`. Two jobs:

| Job | Runner | What it does |
|---|---|---|
| `kernel-build` | standard (`ubuntu-latest`) | Syncs only `kernel/samsung/msm8953` + the aarch64-4.9 toolchain (~1.5 GB) and builds `Image.gz-dtb` from `lineageos_c7ltechn_defconfig`. Uploads the kernel as an artifact. **Runs on every push.** |
| `rom-build` | **larger runner only** | Full `m bacon` (boot/recovery/system). **Requires a GitHub Larger Runner label** via the `runner` input (e.g. `ubuntu-22.04-16core`) — a full LOS16 build needs ~60 GB disk and ~16 GB RAM, which standard runners do not have. **Free-plan accounts cannot use larger runners; a GitHub Pro/Team plan or paid org is required.** |

Run the ROM build later with:

```bash
gh workflow run build -R AwdndWindowsServer/c7ltechn-los16 -f runner=ubuntu-22.04-16core
```

### Locally

```bash
repo init -u https://github.com/LineageOS/android.git -b lineage-16.0 --depth=1
mkdir -p .repo/local_manifests
cp <this repo>/manifest/c7ltechn-16.0.xml .repo/local_manifests/
repo sync -c -j8 --no-tags
source build/envsetup.sh
lunch lineage_c7ltechn-userdebug
m bacon -j$(nproc)
```

## Status / milestones

- [x] M1 — CI pipeline + device tree + full vendor blobs + standalone **kernel build job**
- [x] M1b — **`Image.gz-dtb` kernel artifact green** (built from `lineageos_c7ltechn_defconfig`; fixes: 4.9 wrapper scripts, TRACE_INCLUDE_PATH, USB gadget -> AOSP configfs, set_ncm_ready)
- [ ] M2 — ROM build green (sync + device-tree validation in progress); boots to launcher (kernel/dtb, init, display bring-up)
- [ ] M3 — RIL (calls/SMS/data, dual SIM), WiFi, Bluetooth, GPS
- [ ] M4 — camera, fingerprint, NFC, audio tuning, sensors
- [ ] M5 — SELinux enforcing, daily-usable hardening

Known gaps / TODO (see `porting-guide.md` in the original analysis for details):

1. **Runner**: enable Larger Runners on the GitHub account for full builds.
2. **Missing firmware partitions** (not in this repo — extract from official
   Odin `C7000ZCS3CRJ1` and keep on the device): `modem` (NON-HLOS), `dsp`,
   `tz`, `rpm`, `aboot`, `apnhlos`.
3. **Camera** needs the Samsung camera compat sources (`CameraParameters.cpp`,
   `Fence.cpp` etc. — see the j7popltespr LOS16 tree) and chromatix tuning —
   M4 work.
4. **Fingerprint** (Samsung `ss_fingerprint_*` HAL) needs kernel driver + TZ
   firmware; highest-risk item for daily use.
5. SELinux is **permissive** in the current kernel cmdline; tighten later.
6. The stock `forceencrypt` on `/data` was changed to `encryptable=footer`.

## Acknowledgements

- Stock firmware dump analysis (this repo's blobs come from `C7000ZCS3CRJ1`)
- [Galaxy-MSM8953](https://github.com/Galaxy-MSM8953) — kernel + reference
  msm8953 Samsung device trees (j7popltespr lineage-16.0 pattern)
- LineageOS 16.0
