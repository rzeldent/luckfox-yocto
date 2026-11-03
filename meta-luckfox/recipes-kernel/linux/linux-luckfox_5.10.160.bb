SUMMARY = "Source-built Luckfox RV1103/RV1106 vendor kernel"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

inherit kernel

SRC_URI = "git://github.com/LuckfoxTECH/luckfox-pico.git;protocol=https;branch=main;destsuffix=luckfox-sdk \
           file://0001-kbuild-disable-dangling-pointer-warning.patch \
           file://0002-fix-wide-enum-constants-for-gcc15.patch \
           file://base.cfg \
           file://camera-on.cfg file://camera-off.cfg \
           file://npu-on.cfg file://npu-off.cfg \
           file://rga-on.cfg file://rga-off.cfg"
SRCREV = "824b817f889c2cbff1d48fcdb18ab494a68f69d1"
S = "${UNPACKDIR}/luckfox-sdk/sysdrv/source/kernel"
LINUX_VERSION = "5.10.160"
KERNEL_LOCALVERSION = "-luckfox"
KERNEL_IMAGETYPE = "zImage"
KERNEL_CONFIG_COMMAND = "oe_runmake -C ${S} O=${B} olddefconfig"
DEPENDS += "openssl-native flex-native"
COMPATIBLE_MACHINE = "^luckfox-pico(-plus|-max|-mini|-pi)?$"

LUCKFOX_KERNEL_FRAGMENTS = "base.cfg ${@'camera-on.cfg' if bb.utils.contains('LUCKFOX_FEATURES', 'camera', True, False, d) else 'camera-off.cfg'} ${@'npu-on.cfg' if bb.utils.contains('LUCKFOX_FEATURES', 'npu', True, False, d) else 'npu-off.cfg'} ${@'rga-on.cfg' if bb.utils.contains('LUCKFOX_FEATURES', 'rga', True, False, d) else 'rga-off.cfg'}"

# Only original kernel source is built. SDK release .ko/.S payloads are unused.
python do_prepare_luckfox_dts() {
    from luckfox_config import configure_vendor_dts

    try:
        configure_vendor_dts(d.getVar("S"), d.getVar("LUCKFOX_VENDOR_DEVICETREE"),
                             d.getVar("LUCKFOX_FEATURES").split())
    except ValueError as error:
        bb.fatal(str(error))
}
addtask prepare_luckfox_dts after do_patch before do_configure

do_configure:prepend() {
    install -m 0644 ${S}/arch/arm/configs/luckfox_rv1106_linux_defconfig ${B}/.config
    for fragment in ${LUCKFOX_KERNEL_FRAGMENTS}; do
        ${S}/scripts/kconfig/merge_config.sh -m -O ${B} ${B}/.config ${UNPACKDIR}/${fragment}
    done
}

python do_validate_luckfox_kernel_config() {
    import os
    from luckfox_config import validate_kernel_config

    with open(os.path.join(d.getVar("B"), ".config")) as stream:
        config = stream.read()
    fragments = []
    for name in d.getVar("LUCKFOX_KERNEL_FRAGMENTS").split():
        with open(os.path.join(d.getVar("UNPACKDIR"), name)) as stream:
            fragments.append(stream.read())
    try:
        validate_kernel_config(config, fragments)
    except ValueError as error:
        bb.fatal(str(error))
}
addtask validate_luckfox_kernel_config after do_configure before do_compile
