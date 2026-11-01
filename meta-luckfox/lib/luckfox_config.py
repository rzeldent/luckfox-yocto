"""Validate Luckfox feature and NAND combinations without guessing hardware."""

from pathlib import Path


DRIVERS = frozenset(("camera", "npu", "rga", "vcodec", "rtl8723bs", "nand-mtd"))


def nand_capacity(nand_size, erase_size, rootfs_offset, reserved_blocks):
    return int(nand_size) - int(rootfs_offset) - int(erase_size) * int(reserved_blocks)


def validate_configuration(*, machine, kernel, drivers, image_features,
                           allow_proprietary, libc, page_size="", erase_size="",
                           nand_size="", rootfs_offset="1179648", reserved_blocks="24"):
    if kernel not in ("vendor", "mainline"):
        raise ValueError("LUCKFOX_KERNEL must be vendor or mainline")
    unknown = set(drivers) - DRIVERS
    if unknown:
        raise ValueError("Unknown LUCKFOX_FEATURES: " + " ".join(sorted(unknown)))
    if machine.startswith("luckfox-pico-pi-"):
        raise ValueError("Pico Pi kernel DT is available, but its eMMC/alternate-SD bootloader integration is not validated")
    if "rtl8723bs" in drivers and machine.endswith("-sd-card"):
        raise ValueError("rtl8723bs occupies the SD boot bus; use NAND or omit rtl8723bs")
    if "vcodec" in drivers:
        raise ValueError("RV110x encoder requires opaque SDK kernel payloads, not the generic source MPP driver; use rga for source-built 2D acceleration")
    if kernel == "mainline" and "rga" in drivers:
        raise ValueError("RV110x RGA2 requires the source vendor driver; select LUCKFOX_KERNEL = vendor")
    if kernel == "vendor" and "rtl8723bs" in drivers:
        raise ValueError("The packaged rtw88 driver targets mainline; vendor-kernel Wi-Fi integration is not validated")
    if "npu-runtime" in image_features and "npu" not in drivers:
        raise ValueError("npu-runtime requires the npu driver feature")
    if "npu-runtime" in image_features and kernel != "vendor":
        raise ValueError("The RKNN mini runtime requires the vendor DMA-heap driver ABI")
    if "media-runtime" in image_features:
        raise ValueError("Complete Rockit media runtime requires opaque mpp_vcodec and rockit kernel payloads; it is not enabled by this source-only layer")
    if {"npu-runtime", "media-runtime"} & set(image_features):
        if allow_proprietary != "1":
            raise ValueError("Proprietary userspace requires LUCKFOX_ALLOW_PROPRIETARY_USERSPACE = 1")
        if libc != "glibc":
            raise ValueError("Proprietary runtime packages require TCLIBC = glibc")
    if machine.endswith("-spi-nand"):
        if machine.startswith(("luckfox-pico-pi-", "luckfox-pico-spi-")):
            raise ValueError("This board has no SDK-supported NAND boot configuration")
        if not page_size or not erase_size or not nand_size:
            raise ValueError("Set verified LUCKFOX_NAND_PAGE_SIZE, LUCKFOX_NAND_ERASE_SIZE and LUCKFOX_NAND_SIZE in bytes")
        try:
            page, erase, size, offset, reserve = map(
                int, (page_size, erase_size, nand_size, rootfs_offset, reserved_blocks))
        except ValueError as error:
            raise ValueError("NAND geometry must use decimal byte counts and block counts") from error
        if page < 512 or page & (page - 1) or erase <= 2 * page or erase % page:
            raise ValueError("Invalid NAND page/erase geometry")
        minimum_reserve = ((size // erase) * 20 + 1023) // 1024 + 4
        if size % erase or offset % erase or reserve < minimum_reserve:
            raise ValueError("NAND size/layout must be eraseblock-aligned and reserve at least %s blocks for UBI/bad-block headroom" % minimum_reserve)
        if nand_capacity(size, erase, offset, reserve) <= 2 * erase:
            raise ValueError("NAND rootfs budget is too small")
        if 131072 % erase:
            raise ValueError("Existing SPL/U-Boot partition layout requires eraseblocks dividing 128KiB")


def validate_kernel_config(config, fragments):
    """Catch feature selections silently discarded by Kconfig dependencies."""
    actual = {}
    for line in config.splitlines():
        if line.startswith("CONFIG_") and "=" in line:
            key, value = line.split("=", 1)
            actual[key] = value
        elif line.startswith("# CONFIG_") and line.endswith(" is not set"):
            actual[line[2:-11]] = "n"
    for fragment in fragments:
        for line in fragment.splitlines():
            if line.startswith("CONFIG_") and "=" in line:
                key, expected = line.split("=", 1)
                if actual.get(key, "n") != expected:
                    raise ValueError("%s requested %s, resolved to %s" %
                                     (key, expected, actual.get(key, "n")))


def configure_vendor_dts(source, dtb, drivers):
    board = Path(source) / "arch/arm/boot/dts" / Path(dtb).with_suffix(".dts")
    if not board.is_file():
        raise ValueError("Missing vendor board DT: " + str(board))
    additions = [
        '/ { chosen { /delete-property/ bootargs; stdout-path = "serial2:115200n8"; }; };',
        '&fiq_debugger { status = "disabled"; };',
        '&uart2 { status = "okay"; };',
    ]
    for label, feature in (("npu", "npu"), ("rga2", "rga")):
        status = "okay" if feature in drivers else "disabled"
        additions.append('&%s { status = "%s"; };' % (label, status))
    if "camera" not in drivers:
        for label in ("rkcif", "rkisp", "csi2_dphy_hw"):
            additions.append('&%s { status = "disabled"; };' % label)
    if "pico-pi" not in dtb:
        additions.append('&sdmmc { /delete-property/ non-removable; /delete-property/ supports-sdio; /delete-property/ cap-sdio-irq; no-sdio; };')
    board.write_text(board.read_text() + "\n" + "\n".join(additions) + "\n")
