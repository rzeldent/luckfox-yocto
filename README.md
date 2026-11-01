# luckfox-yocto

Source-oriented Yocto configuration for Luckfox RV1103/RV1106 boards.

## Description

The pinned `meta-rv110x` BSP is extended by the repository-owned `meta-luckfox`
layer. `luckfox-project` selects the Luckfox SDK's Linux 5.10.160 **original
kernel source**, not SDK `.ko` files. The existing patched mainline provider
remains selectable with `LUCKFOX_KERNEL = "mainline"`.

**Current verification:** source Kconfig and device-tree checks are available,
but no Yocto image or target boot has been validated for the new vendor provider.
Image builds on the current Ubuntu host are blocked by AppArmor's
unprivileged-user-namespace restriction. An administrator must grant scoped
BitBake permission; do not disable the sanity check or AppArmor.

## Supported machines

Use a distinct machine and image per board and boot medium. The SDK identifies
Pico and Pico Plus as **RV1103**, despite the older layer's `rv1106-*` DT names.

| Machine | Board | SoC |
| --- | --- | --- |
| `luckfox-pico-sd-card` | Luckfox Pico | RV1103 |
| `luckfox-pico-plus-sd-card`, `luckfox-pico-plus-spi-nand` | Luckfox Pico Plus | RV1103 |
| `luckfox-pico-max-sd-card`, `luckfox-pico-max-spi-nand` | Luckfox Pico Max | RV1106 |
| `luckfox-pico-mini-sd-card`, `luckfox-pico-mini-spi-nand` | Luckfox Pico Mini; NAND requires a populated NAND part | RV1103G |

Pico Pro and Max share the SDK's `rv1106g-luckfox-pico-pro-max` DT; this is not
proof of identical installed RAM or NAND capacity. RAM comes from boot-time DDR
initialization, not a board-size declaration in these DTs.

For the existing mainline provider, select only its supported driver flags:

```bitbake
LUCKFOX_KERNEL = "mainline"
LUCKFOX_FEATURES = "camera npu"
```

The SDK also contains Pi, Ultra, Zero, WebBee and 86Panel DTs. Pi/Ultra/Zero/
86Panel primarily have eMMC SDK configurations. The existing layer's Pi machine
incorrectly reuses the Pico bootloader, and Pi's SD slot uses a different
controller. The product image rejects Pi until bootloader/storage integration is
validated. Pi's vendor kernel DT is included in the source DT tests, **not**
advertised as a working image. Legacy Pico/Pi NAND machine files are likewise not
evidence of supported NAND hardware. Do not flash one board's image onto another.

### Feature flags (`LUCKFOX_FEATURES`)

`LUCKFOX_FEATURES` selects source kernel drivers. The default is `camera npu rga`.
Set it in `build/conf/local.conf`, or export it together with
`BB_ENV_PASSTHROUGH_ADDITIONS=LUCKFOX_FEATURES`. Unknown features fail rather than
silently producing a different image.

| Feature | Description |
| --- | --- |
| `camera` | Source SC3336 sensor, CIF, CSI PHY and vendor ISP drivers |
| `npu` | Source rknpu driver; does **not** install proprietary inference userspace |
| `rga` | Source vendor multi-RGA driver; 2D scaling/rotation, **not** video encoding |
| `rtl8723bs` | Existing source rtw88 driver, mainline NAND builds only; vendor integration is not validated |
| `nand-mtd` | Existing BSP flag for non-boot NAND exposure; not NAND geometry configuration |

The legacy `vcodec` flag is rejected: the generic mainline/vendor MPP driver does
not bind the RV110x encoder. Use `rga` for source-built graphics acceleration.
With the vendor provider, disabled features remove their kernel configurations
and disable the relevant DT functions. Disabling camera also avoids its CMA
request when no other DMA feature is selected. `LUCKFOX_CMA_SIZE` defaults to 24M
with camera/NPU/RGA, or 0M without them; tune it against actual RAM and workloads.

RTL8723BS and SD boot cannot occupy the same SDMMC bus. Their combination fails
configuration validation. The vendor DT adaptation makes the normal slot
removable, disables the SDK FIQ console in favor of `ttyS2`, and removes the
SDK's hard-coded `/dev/mmcblk1p7` boot argument so extlinux selects the image root.

### Optional image packages

`luckfox-image` does not inherit the wildcard `core-image-*` debug additions and
does not recommend every compiled kernel module. Set `LUCKFOX_IMAGE_FEATURES`
to a space-separated selection of ordinary Yocto image features:

| Feature | Included functionality |
| --- | --- |
| `hardware-tools` | V4L2/media, I2C and MTD/UBIFS inspection tools |
| `ssh-server-dropbear` | Optional small SSH server |
| `tools-debug` | Optional Yocto debugging tools |
| `software-codecs` | Source FFmpeg, without falsely advertised RV110x rkmpp encoding |
| `npu-runtime` | Proprietary `librknnmrt`, vendor DMA-heap ABI only |

Required DDR boot firmware is allowed and remains separate from kernel modules.
Proprietary NPU/media userspace is **off by default**. To include NPU inference:

```bitbake
LUCKFOX_FEATURES = "npu"
LUCKFOX_IMAGE_FEATURES = "npu-runtime"
LUCKFOX_ALLOW_PROPRIETARY_USERSPACE = "1"
TCLIBC = "glibc"
```

An explicit `luckfox-proprietary` license flag also guards recipes containing
proprietary payloads. Closed libraries are marked `CLOSED`, rather than borrowing
an unrelated RKNN Toolkit license for Rockit/RTSP. Opting in is not a substitute
for checking the vendor's redistribution terms. `media-runtime` is currently rejected even after opting in:
complete Rockit streaming needs opaque **kernel** payloads, not merely userspace
libraries. Optional userspace permission is not permission for closed modules.

## Dependencies

* [Visual Studio Code](https://code.visualstudio.com/)
* [Yocto Project BitBake vscode extension](https://marketplace.visualstudio.com/items?itemName=yocto-project.yocto-bitbake)
* [Task Buttons vscode extension](https://marketplace.visualstudio.com/items?itemName=spencerwmiles.vscode-task-buttons)
* `bmaptool` (for writing SD cards)

## Building SD and NAND images

The initial selected target is **Pico Plus (RV1103)**. Initialize pinned layers
in this checkout; no main-checkout devtool workspace is used:

```sh
git submodule update --init
. openembedded-core/oe-init-build-env build
MACHINE=luckfox-pico-plus-sd-card bitbake luckfox-image
```

For a NAND-constrained image, use `LUCKFOX_FEATURES = ""` and
`LUCKFOX_IMAGE_FEATURES = ""`, then add only the required drivers and tools.
No FFmpeg, Wi-Fi or streaming packages are appended globally.

NAND requires **verified physical** page size, eraseblock size and chip capacity
in decimal bytes. The Pico Plus SDK's partition totals alone do not establish
these. Obtain the actual NAND part marking and, from a booted board, `mtdinfo -a`
or the matching kernel MTD identification. Set:

```bitbake
# Examples only, NOT confirmed Pico Plus geometry:
# LUCKFOX_NAND_PAGE_SIZE = "2048"
# LUCKFOX_NAND_ERASE_SIZE = "131072"
# LUCKFOX_NAND_SIZE = "134217728"
```

Only after confirming geometry:

```sh
MACHINE=luckfox-pico-plus-spi-nand bitbake luckfox-image
```

NAND flash readiness is **blocked pending that confirmation**. The upstream
boot layout is retained: SPL at 0, U-Boot at 128KiB, rootfs at 1152KiB. This is
**not** the SDK's env/idblock/boot/oem layout. Geometry checks reject incompatible
eraseblock alignment. UBI construction uses measured geometry and reserves 24
physical blocks on a 128MiB/128KiB-eraseblock part (44 on a 256MiB part), reserving
20 bad-block slots per 1024 physical blocks plus four UBI overhead blocks. The final `.ubi`
must fit the remaining raw partition budget. Existing bad blocks and ECC still
need target confirmation. SPL and U-Boot must fit their own partitions as well.

SD uses the BSP GPT WIC layout: loader1 at sector 64, U-Boot at sector 16384 and
ext4 rootfs at sector 32768. SD images include the existing first-boot rootfs
resize service.

Outputs belong outside version control under `build/tmp/deploy/images/${MACHINE}`.
The SD deliverables are `luckfox-image-${MACHINE}.rootfs.wic` and `.wic.bmap`;
NAND needs `.ubi`, `idbloader.img` and `u-boot*.img` as a matching set. Before
delivery, inspect actual image formats/layouts, measure sizes and generate
`sha256sum` checksums. No image artifacts are currently available.

VS Code's default task is **Build luckfox-image**. Existing core image tasks
remain available as larger debug-oriented images.

The NAND task erases the whole SPI NAND before writing, so anything already stored on it is lost. That erase is not optional in practice: a `.ubi` is smaller than its partition, and UBI refuses to attach if any block still holds another image's sequence number.

## Hardware media and source limitations

The SDK at revision `824b817f889c2cbff1d48fcdb18ab494a68f69d1` has original
C source for rknpu, CIF, ISP, camera sensors and multi-RGA. The vendor recipe
builds those and checks that Kconfig has not silently discarded selected
features. It does not import SDK precompiled modules.

The actual RV110x H.264/H.265 pipeline loads **`mpp_vcodec.ko` and `rockit.ko`**,
distributed under `sysdrv/drv_ko/{kmpp,rockit}/release_*_arm`. The alternate
`*_arm_asm` trees contain compiler-generated assembly from unavailable original
C files, not a maintainable source port. Neither the generic source MPP driver
nor installing `rkipc` supplies this missing encoder implementation. These opaque
kernel payloads and their MCU firmware are excluded.

Public source recipes for MPP, RGA and RKAIQ remain in the BSP, but a library
build alone establishes neither kernel ABI compatibility nor hardware behavior.
RKNN inference additionally needs the optional proprietary runtime and a
matching converted model. Camera 3A needs sensor-specific IQ data and a compatible
userspace engine. No camera capture, inference, scaling, encoding or frame-rate
claim is made without target execution.

### Validation

Run policy tests without a full Yocto build:

```sh
python3 -m unittest discover -s tests -v
```

For native Kconfig checks of all eight camera/NPU/RGA combinations and compiled
DT checks of five vendor boards with features on/off, point at a **separate
source export**, not the read-only SDK checkout:

```sh
LUCKFOX_KERNEL_SOURCE=/path/to/exported/sysdrv/source/kernel \
    python3 -m unittest discover -s tests -v
```

These checks require host GCC/make and `dtc`. They validate configuration and DT
semantics, not target module compilation, boot or acceleration. Before declaring
an image ready, complete BitBake builds and inspect kernel modules, extlinux,
GPT/UBI, package manifests and measured partition sizes, then test on each SKU.

## Logging in

The new product image leaves Yocto's default root account locked. Configure
credentials before deployment; for a deliberately insecure bench-only image,
explicitly select Yocto's `allow-empty-password empty-root-password` features.

The existing **core-image** debug builds, not `luckfox-image`, retain their
original password and OpenSSH additions. Over UART (`ttyS2`) or the USB CDC-ACM
serial gadget:

```
login: root
password: password
```

Change the password (in `core-image-%.bbappend`, or with the `passwd` command) before deploying anywhere it matters. The USB port is also the power port, so anyone who can plug in a cable can reach that login prompt.

## Extras
`fastfetch` is included in the existing core-image debug builds, not forced into
the NAND-oriented product image.

## Configure RTL8723BS Wi-Fi

For a board built with the `rtl8723bs` feature, the driver creates `wlan0`.
To join a WPA2-Personal network, create `/etc/wpa_supplicant.conf` on the
board with your network details:

```
ctrl_interface=/var/run/wpa_supplicant
update_config=1
country=US

network={
    ssid="your Wi-Fi name"
    psk="your Wi-Fi password"
    key_mgmt=WPA-PSK
}
```

Replace `country` with your two-letter regulatory country code and set the file
permissions so only root can read the passphrase:

```
chmod 600 /etc/wpa_supplicant.conf
```

The init script reads this file on boot, starts `wpa_supplicant`, and requests
an address for `wlan0` with DHCP. After editing the file, apply it without
rebooting by restarting the service (do not start `wpa_supplicant` by hand while
it is running, that fails with "ctrl_iface exists"):

```
/etc/init.d/rtl8723bs-init restart
```

Check the result with `wpa_cli -i wlan0 status` (look for `wpa_state=COMPLETED`),
`ip addr show wlan0` and `ip route`. The RTL8723BS is 2.4 GHz only, so the
network must broadcast on 2.4 GHz. The repeated
`RTW88 IRQ during scan` lines are temporary driver diagnostics; the packaged
driver removes that per-interrupt console log.

## Erase NAND

With the board booted from SD and the SPI NAND visible as a raw MTD device, erase it from the target. Wiping the IDB this way is what makes the board fall back into MaskROM (USB download) mode on the next power-up, which is the way back when `flash_spi_nand.sh` fails part-way and leaves the flash holding a bootable-looking, incomplete image.

```
ubidetach -m 0 2>/dev/null || true      # detach UBI first if it's attached
flash_erase -N /dev/mtd0 0 0            # whole chip, don't skip bad blocks
```

From the U-Boot console instead: `mtd erase.dontskipbad spi-nand0`.
