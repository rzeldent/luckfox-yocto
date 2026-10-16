# luckfox-yocto

Pre-configured example of Yocto project for Luckfox boards.

## Description

This is an example and starting point for working with the [meta-rv110x](https://github.com/RamasyaR/meta-rv110x) metalayer, which supports the Luckfox Pico, Pico Plus, Pico Max and Pico Mini A/B boards.

## Supported machines

Each board has an SD card variant and, where the board has SPI NAND, a
corresponding `-spi-nand` variant.

| Machine | Board | Boot medium |
| --- | --- | --- |
| `luckfox-pico` | Luckfox Pico | SD card |
| `luckfox-pico-spi-nand` | Luckfox Pico | SPI NAND |
| `luckfox-pico-plus` | Luckfox Pico Plus | SD card |
| `luckfox-pico-plus-spi-nand` | Luckfox Pico Plus | SPI NAND |
| `luckfox-pico-max` | Luckfox Pico Max | SD card |
| `luckfox-pico-max-spi-nand` | Luckfox Pico Max | SPI NAND |
| `luckfox-pico-mini-a` | Luckfox Pico Mini A | SD card |
| `luckfox-pico-mini-b` | Luckfox Pico Mini B | SD card |
| `luckfox-pico-mini-b-spi-nand` | Luckfox Pico Mini B | SPI NAND |

The SD card images resize the root filesystem to fill the card on first boot,
so the full capacity of the card is usable.

## Dependencies

* [Visual Studio Code](https://code.visualstudio.com/)
* [Yocto Project BitBake vscode extension](https://marketplace.visualstudio.com/items?itemName=yocto-project.yocto-bitbake)
* [Task Buttons vscode extension](https://marketplace.visualstudio.com/items?itemName=spencerwmiles.vscode-task-buttons)
* `bmaptool` (for writing SD cards)

## Quick Start
1. Install vscode
2. Install extensions
3. Clone and open this repo in vscode
4. Select MACHINE using the button in the bottom right corner of the vscode window
5. Build a basic/minimal image using the task **Ctrl/Shift/P**, Run Task and select **build core-image-minimal**
6. Find the build result in the `build/tmp/deploy/images/<machine>` directory
7. Flash the image
    - SDCARD: **Ctrl/Shift/P**, Run Task and select **Write SD card**
    - NAND: **Ctrl/Shift/P**, Run Task and select **Flash SPI NAND**
8. Boot your device


## Logging in

```
login: root
password: password
```

Change the password (in `core-image-%.bbappend`, or with the `passwd` command)
before deploying anywhere it matters.

## Extras

`fastfetch` is included for a Linux overview.

## Erase NAND

With the board booted from SD and the SPI NAND visible as a raw MTD device,
erase it from the target. Wiping the IDB this way is what makes the board fall
back into MaskROM (USB download) mode on the next power-up, which is the way
back when `flash_spi_nand.sh` fails part-way and leaves the flash holding a
bootable-looking, incomplete image.

```
ubidetach -m 0 2>/dev/null || true     # detach UBI first if it's attached
flash_erase -N /dev/mtd0 0 0           # whole chip, don't skip bad blocks
```

From the U-Boot console instead: `mtd erase.dontskipbad spi-nand0`.
