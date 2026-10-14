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
4. Select MACHINE using the button in the bottom right corner of the vscode window<br />
![plot](files/img/select_machine.png)
5. Build a basic/minimal image using the buttons in the bottom left corner of the vscode window<br />
![plot](files/img/build_buttons.png)
6. Find the build result in the `build/tmp/deploy/images/<machine>` directory
7. Flash the image
    - SDCARD: run the **Flash SD card (bmaptool)** task, or use the helper script
    - NAND: run the **Flash SPI NAND (upgrade_tool)** task, or see the [tutorial](/flash_spi_nand.md)
8. Boot your device

## Flashing

Two helper scripts are provided, and both are also available as vscode tasks
(**Terminal → Run Task…**).

### SD card

```
sudo ./flash_sd.sh -m luckfox-pico-max -D /dev/sdb
```

The equivalent manual command is:

```
sudo bmaptool copy ./build/tmp/deploy/images/luckfox-pico-max/core-image-base-luckfox-pico-max.rootfs.wic /dev/sdb
```

### SPI NAND

```
sudo ./flash_spi_nand.sh --deploy-dir ./build/tmp/deploy/images/luckfox-pico-mini-b-spi-nand
```

Run either script with `--help` for all options.

## Logging in

```
login: root
password: password
```

Change the password (in `core-image-%.bbappend`, or with the `passwd` command)
before deploying anywhere it matters.

## Extras

`fastfetch` is included for a Linux overview.


