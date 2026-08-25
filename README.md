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
| `vendor/samsung/c7ltechn/` | Proprietary blobs extracted from stock firmware (441 MB) + generated `c7ltechn-vendor.mk` |
| `manifest/c7ltechn-16.0.xml` | Local manifest for `repo init` / CI |
| `tools/gen-vendor-mk.py` | Regenerates `c7ltechn-vendor.mk` from the blob tree |
| `tools/system-blobs.txt` | Curated list of system-side proprietary blobs |
| `.github/workflows/build.yml` | CI: sync LOS 16.0 + build + upload artifacts |

## How to build

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

### On GitHub Actions

Push to this repo → workflow `build` (manual `workflow_dispatch` or on push).
**Important:** a full LOS 16 build needs ~60 GB disk and ~16 GB RAM.

- `ubuntu-latest` (7 GB RAM / 14 GB disk) will almost certainly run out of disk during `repo sync`.
- Use a **GitHub Larger Runner** for real builds, e.g. `ubuntu-22.04-16core`
  (set via the `runner` input of the workflow).

Artifacts: `boot.img`, `recovery.img`, `system.img` + SHA256SUMS.

## Status / milestones

- [x] M1 — CI pipeline + device tree + full vendor blobs (target: **compiles**)
- [ ] M2 — boots to launcher (kernel/dtb, init, display bring-up)
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
