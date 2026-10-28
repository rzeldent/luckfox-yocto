# luckfox-yocto

Pre-configured example of Yocto project for Luckfox boards.

## Description

This is an example and starting point for working with the [meta-rv110x](https://github.com/RamasyaR/meta-rv110x) metalayer, which supports the Luckfox Pico, Pico Plus, Pico Max, Pico Mini and Pico Pi boards.

## Supported machines

There are 5 base machines (one per board). Optional features are controlled via the `LUCKFOX_FEATURES` variable instead of separate machine names.

| Machine | Board | SoC |
| --- | --- | --- |
| `luckfox-pico-sd-card`, `luckfox-pico-spi-nand` | Luckfox Pico | RV1106 |
| `luckfox-pico-plus-sd-card`, `luckfox-pico-plus-spi-nand` | Luckfox Pico Plus | RV1106 |
| `luckfox-pico-max-sd-card`, `luckfox-pico-max-spi-nand` | Luckfox Pico Max | RV1106 |
| `luckfox-pico-mini-sd-card`, `luckfox-pico-mini-spi-nand` | Luckfox Pico Mini A/B | RV1103G |
| `luckfox-pico-pi-sd-card`, `luckfox-pico-pi-spi-nand` | Luckfox Pico Pi | RV1106 |

### Feature flags (`LUCKFOX_FEATURES`)

Features are space-separated tokens passed via `LUCKFOX_FEATURES` (in `local.conf`, environment, or VS Code build configuration). The default is `camera npu vcodec`. When set through the environment (not `local.conf`), BitBake only sees it if `BB_ENV_PASSTHROUGH_ADDITIONS=LUCKFOX_FEATURES` is exported too; the VS Code build configurations already do this.

| Feature | Description |
| --- | --- |
| `camera` | MIPI CSI camera stack (SC3336 sensor, CIF, ISP1) |
| `rtl8723bs` | Realtek RTL8723BS WiFi via SDIO (rtw88 driver package, WiFi only), SDIO ID `024c:b723` |
| `npu` | Rockchip NPU kernel driver (rknpu), RV1103 and RV1106 |
| `vcodec` | VPU/VIDEO codec kernel drivers (RGA, VDEC) |

**Examples:**
- SD card boot with all features (default): `MACHINE=luckfox-pico-max-sd-card`
- SPI NAND boot: `MACHINE=luckfox-pico-max-spi-nand`
- Minimal build (no camera, no WiFi, no NPU): `MACHINE=luckfox-pico-sd-card LUCKFOX_FEATURES=""`

For the Pico, Pico Plus, Pico Max, and Pico Mini, enabling `rtl8723bs` configures the SDMMC host for the SDIO WiFi module and its reset GPIO. Without this feature, the host is configured as a removable SD card slot.

The SD card images resize the root filesystem to fill the card on first boot, so the full capacity of the card is usable.

## Dependencies

* [Visual Studio Code](https://code.visualstudio.com/)
* [Yocto Project BitBake vscode extension](https://marketplace.visualstudio.com/items?itemName=yocto-project.yocto-bitbake)
* [Task Buttons vscode extension](https://marketplace.visualstudio.com/items?itemName=spencerwmiles.vscode-task-buttons)
* `bmaptool` (for writing SD cards)

## Quick Start
1. Install vscode
2. Install extensions
3. Clone and open this repo in vscode
4. Select MACHINE using the button in the bottom right corner of the vscode window (10 configurations available: 5 boards × SD/NAND)
5. Build a basic/minimal image using the task **Ctrl/Shift/P**, Run Task and select **build core-image-minimal**
6. Find the build result in the `build/tmp/deploy/images/<board>-sd-card` (SD) or `build/tmp/deploy/images/<board>-spi-nand` (NAND) directory
7. Flash the image
    - SDCARD: **Ctrl/Shift+P**, Run Task and select **Write SD card**
    - NAND: **Ctrl/Shift+P**, Run Task and select **Flash SPI NAND**
8. Boot your device

The NAND task erases the whole SPI NAND before writing, so anything already stored on it is lost. That erase is not optional in practice: a `.ubi` is smaller than its partition, and UBI refuses to attach if any block still holds another image's sequence number.

## New Multimedia Features (Hardware Video Encoding)

This layer now includes recipes for Rockchip's hardware video encoding stack on RV1103/RV1106:

### Added Recipes (`meta-rv110x/recipes-multimedia/`)
| Recipe | Description |
|--------|-------------|
| `rockchip-mpp` | MPP library + headers + pkgconfig (from Luckfox SDK + rockchip-linux/mpp) |
| `rockit` | Rockit library (RKMPI wrapper for hardware encode/decode) |
| `rkaiq` | ISP 3A algorithms library (auto-exposure, auto-white-balance, auto-focus) |
| `rga` | 2D graphics acceleration library (rotation, scaling, format conversion) |
| `rkmuxer` | Media muxing library (MP4, TS, FLV containers) |
| `rtsp` | RTSP streaming library |
| `rksysutils` | System utilities library |
| `rkipc` | Complete RTSP streaming application with hardware encoding |
| `ffmpeg_%.bbappend` | Adds `rkmpp` PACKAGECONFIG for FFmpeg |

### Enabled in `build/conf/local.conf`
The example `local.conf` already includes:
```bitbake
LICENSE_FLAGS_ACCEPTED = "commercial"
IMAGE_INSTALL:append = " ffmpeg"
LUCKFOX_FEATURES:append = " rtl8723bs"
IMAGE_INSTALL:append = " rockchip-mpp rockit rkaiq rga rkmuxer rtsp rksysutils rkipc"
```

### Streaming with rkipc (Recommended)
The `rkipc` application provides a complete RTSP server using hardware encoding:

```sh
# On the board
rkipc -a /usr/share/rkipc/rkipc-300w.ini

# On your PC
vlc rtsp://<board-ip>/live/0
```

The INI file (`rkipc-300w.ini` or `rkipc-400w.ini`) configures resolution, bitrate, codec (H.264/H.265), and RTSP paths.

### Using FFmpeg with h264_rkmpp
Once the kernel VEPU driver is available (see limitations below):

```sh
ffmpeg -f v4l2 -input_format nv12 -video_size 1280x720 -framerate 25 -i /dev/video0 \
  -c:v h264_rkmpp -b:v 2M -g 25 -f rtp_mpegts rtp://<PC_IP>:5000

# On PC
vlc rtp://@:5000
```

### ⚠️ Current Limitation: Kernel VEPU Driver
The hardware H.264/HEVC encoder (VEPU/RKVENC) requires a kernel driver that **only exists in Rockchip's vendor 5.10 kernel**, not in mainline Linux 7.1 used by this layer.

| Component | Status |
|-----------|--------|
| Kernel VEPU/RKVENC driver | ❌ Not in mainline (vendor 5.10 only) |
| `mpp_service` character device | ❌ Not available |
| Userspace libraries (MPP, Rockit, RKAIQ, RGA, etc.) | ✅ Provided via recipes |
| `rkipc` RTSP application | ✅ Recipe added (may work if minimal kernel support exists) |
| FFmpeg `h264_rkmpp` encoder | ✅ PACKAGECONFIG added (needs kernel driver) |

**Workarounds:**
1. **Use `rkipc`** - It uses the prebuilt Luckfox SDK libraries and may work with minimal kernel support
2. **Software encoding** - Add `PACKAGECONFIG:append:pn-ffmpeg = " x264"` (already works with `LICENSE_FLAGS_ACCEPTED = "commercial"`)
3. **Port the VEPU driver** - Copy from vendor kernel (`drivers/media/platform/rockchip/vepu/`, `rkvenc/`, `mpp_service/`) to mainline 7.1

For now, software encoding with `libx264` at 640×480 @ 15-20 fps with `-preset ultrafast` is the most reliable option on the Cortex-A7.

## Logging in

Over the UART (ttyS2), or over the USB port: the board presents itself to the host as a CDC-ACM serial device (`/dev/ttyACM*` on Linux, a COM port on Windows) carrying its own login prompt.

```
login: root
password: password
```

Change the password (in `core-image-%.bbappend`, or with the `passwd` command) before deploying anywhere it matters. The USB port is also the power port, so anyone who can plug in a cable can reach that login prompt.

## Extras
`fastfetch` is included for a Linux overview.

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
