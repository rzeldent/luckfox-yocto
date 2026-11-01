SUMMARY = "Selectable Luckfox RV1103/RV1106 image"
LICENSE = "MIT"

inherit core-image

IMAGE_INSTALL = "packagegroup-core-boot ${CORE_IMAGE_EXTRA_INSTALL}"
IMAGE_FEATURES += "${LUCKFOX_IMAGE_FEATURES}"
NO_RECOMMENDATIONS = "1"

FEATURE_PACKAGES_hardware-tools = "v4l-utils i2c-tools mtd-utils mtd-utils-ubifs"
FEATURE_PACKAGES_npu-runtime = "librknnmrt"
FEATURE_PACKAGES_media-runtime = "rga rkipc"
FEATURE_PACKAGES_software-codecs = "ffmpeg"

IMAGE_ROOTFS_SIZE = "8192"
IMAGE_ROOTFS_EXTRA_SPACE = "0"
IMAGE_OVERHEAD_FACTOR = "1.3"

python do_luckfox_check_configuration() {
    from luckfox_config import validate_configuration

    try:
        validate_configuration(
            machine=d.getVar("MACHINE"),
            kernel=d.getVar("LUCKFOX_KERNEL"),
            drivers=d.getVar("LUCKFOX_FEATURES").split(),
            image_features=d.getVar("IMAGE_FEATURES").split(),
            allow_proprietary=d.getVar("LUCKFOX_ALLOW_PROPRIETARY_USERSPACE"),
            libc=d.getVar("TCLIBC"),
            page_size=d.getVar("LUCKFOX_NAND_PAGE_SIZE"),
            erase_size=d.getVar("LUCKFOX_NAND_ERASE_SIZE"),
            nand_size=d.getVar("LUCKFOX_NAND_SIZE"),
            rootfs_offset=d.getVar("LUCKFOX_NAND_ROOTFS_OFFSET"),
            reserved_blocks=d.getVar("LUCKFOX_NAND_RESERVED_BLOCKS"),
        )
    except ValueError as error:
        bb.fatal(str(error))
}
addtask luckfox_check_configuration before do_rootfs after do_prepare_recipe_sysroot

python do_luckfox_check_nand_size() {
    import glob
    import os
    from luckfox_config import nand_capacity

    if not d.getVar("MACHINE").endswith("-spi-nand"):
        return
    capacity = nand_capacity(
        d.getVar("LUCKFOX_NAND_SIZE"), d.getVar("LUCKFOX_NAND_ERASE_SIZE"),
        d.getVar("LUCKFOX_NAND_ROOTFS_OFFSET"), d.getVar("LUCKFOX_NAND_RESERVED_BLOCKS"),
    )
    paths = glob.glob(os.path.join(d.getVar("IMGDEPLOYDIR"), d.getVar("IMAGE_NAME") + "*.ubi"))
    if len(paths) != 1:
        bb.fatal("Expected exactly one built UBI image, found %s" % paths)
    size = os.path.getsize(paths[0])
    if size > capacity:
        bb.fatal("UBI image is %s bytes; NAND budget after reserved blocks is %s bytes" % (size, capacity))
    bb.note("UBI image: %s bytes; usable NAND budget: %s bytes" % (size, capacity))
}
do_image_ubi[postfuncs] += "do_luckfox_check_nand_size"
