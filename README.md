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

Features are space-separated tokens passed via `LUCKFOX_FEATURES` (in `local.conf`, environment, or VS Code build configuration). The default is `camera aic8800dc npu vcodec`.

| Feature | Description |
| --- | --- |
| `camera` | MIPI CSI camera stack (SC3336 sensor, CIF, ISP1) |
| `aic8800dc` | AIC8800DC WiFi/BT via SDIO (kernel modules, firmware, init, wpa-supplicant, bluez5) |
| `npu` | Rockchip NPU kernel driver (rknpu) |
| `vcodec` | VPU/VIDEO codec kernel drivers (RGA, VDEC) |

**Examples:**
- SD card boot with all features (default): `MACHINE=luckfox-pico-max-sd-card`
- SPI NAND boot: `MACHINE=luckfox-pico-max-spi-nand`
- Minimal build (no camera, no WiFi, no NPU): `MACHINE=luckfox-pico-sd-card LUCKFOX_FEATURES=""`

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


## Logging in

Over the UART (ttyS2), or over the USB port: the board presents itself to the host as a CDC-ACM serial device (`/dev/ttyACM*` on Linux, a COM port on Windows) carrying its own login prompt.

```
login: root
password: password
```

Change the password (in `core-image-%.bbappend`, or with the `passwd` command) before deploying anywhere it matters. The USB port is also the power port, so anyone who can plug in a cable can reach that login prompt.

## Extras
`fastfetch` is included for a Linux overview.

## Erase NAND

With the board booted from SD and the SPI NAND visible as a raw MTD device, erase it from the target. Wiping the IDB this way is what makes the board fall back into MaskROM (USB download) mode on the next power-up, which is the way back when `flash_spi_nand.sh` fails part-way and leaves the flash holding a bootable-looking, incomplete image.

```
ubidetach -m 0 2>/dev/null || true      # detach UBI first if it's attached
flash_erase -N /dev/mtd0 0              # whole chip, don't skip bad blocks
```

From the U-Boot console instead: `mtd erase.dontskipbad spi-nand0`.
