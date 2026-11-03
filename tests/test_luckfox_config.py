import itertools
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "meta-luckfox/lib"))

from luckfox_config import (
    configure_vendor_dts,
    nand_capacity,
    validate_configuration,
    validate_kernel_config,
)


class ConfigurationTests(unittest.TestCase):
    def check_config(self, **changes):
        args = dict(machine="luckfox-pico-plus", kernel="vendor",
                    features=["camera", "npu", "rga"], image_features=[],
                    allow_proprietary="0", libc="glibc")
        args.update(changes)
        validate_configuration(**args)

    def test_source_only_profiles(self):
        for machine in ("pico", "pico-plus", "pico-mini", "pico-max"):
            for features in ([], ["camera"], ["npu"], ["rga"], ["camera", "npu", "rga"]):
                with self.subTest(machine=machine, features=features):
                    self.check_config(machine="luckfox-" + machine,
                                      features=features)

    def test_unknown_feature_is_not_silently_ignored(self):
        with self.assertRaisesRegex(ValueError, "Unknown"):
            self.check_config(features=["npou"])

    def test_opaque_encoder_is_not_presented_as_source(self):
        with self.assertRaisesRegex(ValueError, "opaque"):
            self.check_config(features=["vcodec"])
        with self.assertRaisesRegex(ValueError, "opaque"):
            self.check_config(image_features=["media-runtime"], allow_proprietary="1")

    def test_npu_runtime_requires_explicit_permission(self):
        with self.assertRaisesRegex(ValueError, "Proprietary"):
            self.check_config(image_features=["npu-runtime"])
        self.check_config(image_features=["npu-runtime"], allow_proprietary="1")

    def test_runtime_requires_abi_and_driver(self):
        for changes in (dict(libc="musl"), dict(features=[]), dict(kernel="mainline")):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.check_config(image_features=["npu-runtime"],
                                  allow_proprietary="1", **changes)

    def test_wifi_does_not_replace_sd_boot_bus(self):
        with self.assertRaisesRegex(ValueError, "SD boot bus"):
            self.check_config(features=["rtl8723bs"], kernel="mainline")

    def test_mainline_rga_is_not_claimed_to_support_rv110x(self):
        with self.assertRaisesRegex(ValueError, "RGA2"):
            self.check_config(kernel="mainline")

    def test_nand_requires_actual_geometry(self):
        with self.assertRaisesRegex(ValueError, "verified"):
            self.check_config(machine="luckfox-pico-plus",
                              features=["spi-nand"])

    def test_nand_budget_with_reserved_blocks(self):
        self.check_config(machine="luckfox-pico-plus", features=["spi-nand"],
                          page_size="2048",
                          erase_size="131072", nand_size="134217728")
        self.assertEqual(nand_capacity(134217728, 131072, 1179648, 24), 129892352)

    def test_nand_bad_block_headroom_scales_with_capacity(self):
        with self.assertRaisesRegex(ValueError, "44 blocks"):
            self.check_config(machine="luckfox-pico-max", features=["spi-nand"],
                              page_size="2048",
                              erase_size="131072", nand_size="268435456")
        self.check_config(machine="luckfox-pico-max", features=["spi-nand"],
                          page_size="2048",
                          erase_size="131072", nand_size="268435456",
                          reserved_blocks="44")

    def test_unsubstantiated_nand_boards_are_rejected(self):
        for machine in ("luckfox-pico", "luckfox-pico-pi"):
            with self.subTest(machine=machine), self.assertRaises(ValueError):
                self.check_config(machine=machine, features=["spi-nand"],
                                  page_size="2048",
                                  erase_size="131072", nand_size="134217728")

    def test_pi_image_cannot_reuse_pico_bootloader_silently(self):
        with self.assertRaisesRegex(ValueError, "bootloader"):
            self.check_config(machine="luckfox-pico-pi")

    def test_invalid_nand_geometry_and_partition_alignment(self):
        for changes in (dict(page_size="0"), dict(page_size="abc"),
                        dict(erase_size="262144"), dict(nand_size="1024"),
                        dict(reserved_blocks="0"), dict(erase_size="131073")):
            args = dict(machine="luckfox-pico-plus", features=["spi-nand"],
                        page_size="2048",
                        erase_size="131072", nand_size="134217728")
            args.update(changes)
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                self.check_config(**args)

    def test_kernel_dependencies_cannot_silently_drop_features(self):
        validate_kernel_config("# CONFIG_OFF is not set\nCONFIG_ON=m\n",
                               ["CONFIG_OFF=n\nCONFIG_ON=m\n"])
        with self.assertRaisesRegex(ValueError, "resolved"):
            validate_kernel_config("# CONFIG_ON is not set\n", ["CONFIG_ON=m\n"])


@unittest.skipUnless((ROOT / "bitbake/lib/bb").is_dir(), "Initialize pinned BitBake")
class MetadataTests(unittest.TestCase):
    """Read-only BitBake parsing; no cooker, tasks or host-policy bypass."""

    def parse_config(self, machine, kernel="vendor", features="camera npu rga",
                     **settings):
        sys.path.insert(0, str(ROOT / "bitbake/lib"))
        import bb.data
        import bb.parse

        data = bb.data.init()
        data.setVar("BBPATH", ":".join(str(ROOT / layer) for layer in
                                     ("meta-luckfox", "meta-rv110x")))
        data.setVar("MACHINE", machine)
        data.setVar("LUCKFOX_KERNEL", kernel)
        data.setVar("LUCKFOX_FEATURES", features)
        data.setVar("KERNEL_DEVICETREE", "rockchip/original.dtb")
        data.setVar("MACHINEOVERRIDES", machine)
        data.setVar("OVERRIDES", "${MACHINEOVERRIDES}")
        data.setVar("MACHINE_ESSENTIAL_EXTRA_RDEPENDS",
                    "kernel-image v4l-utils i2c-tools resize-rootfs")
        data.setVar("WIC_COMPRESSION_EXTENSION", "")
        data.setVar("IMAGE_FSTYPES", " wic${WIC_COMPRESSION_EXTENSION} wic.bmap")
        data.setVar("UBOOT_CONFIG", "sdcard")
        for key, value in settings.items():
            data.setVar(key, value)
        bb.parse.handle(str(ROOT / "meta-rv110x/conf/machine/include/luckfox-features.inc"),
                        data, include=True)
        bb.parse.handle(str(ROOT / "meta-rv110x/conf/machine/include/rv-ubifs.inc"),
                        data, include=True)
        bb.parse.handle(str(ROOT / "meta-luckfox/conf/distro/luckfox-project.conf"), data)
        return data

    def test_spi_nand_feature_selects_nand_boot_and_ubi_only(self):
        data = self.parse_config("luckfox-pico-plus", features="camera spi-nand")
        self.assertEqual(data.getVar("RV_SPI_NAND_STORAGE"), "1")
        self.assertEqual(data.getVar("UBOOT_CONFIG"), "spi-nand")
        self.assertEqual(data.getVar("IMAGE_FSTYPES").split(), ["ubi"])
        self.assertNotIn("resize-rootfs",
                         data.getVar("MACHINE_ESSENTIAL_EXTRA_RDEPENDS").split())

        data = self.parse_config("luckfox-pico-plus", features="camera")
        self.assertEqual(data.getVar("RV_SPI_NAND_STORAGE"), "0")
        self.assertEqual(data.getVar("UBOOT_CONFIG"), "sdcard")
        self.assertEqual(data.getVar("IMAGE_FSTYPES").split(), ["wic", "wic.bmap"])
        self.assertIn("resize-rootfs",
                      data.getVar("MACHINE_ESSENTIAL_EXTRA_RDEPENDS").split())

    def test_feature_overrides_do_not_collide_with_package_names(self):
        features = "camera npu rga vcodec rtl8723bs nand-mtd"
        data = self.parse_config("luckfox-pico-plus", features=features)
        overrides = set(data.getVar("OVERRIDES").split(":"))
        for feature in features.split():
            with self.subTest(feature=feature):
                self.assertNotIn(feature, overrides)
                self.assertIn("luckfox-" + feature, overrides)
        self.assertTrue(set(features.split()) <= set(data.getVar("MACHINE_FEATURES").split()))
        data.setVar("PN", "rga")
        data.setVar("FILES:rga", "/usr/lib/librga.so.*")
        self.assertIsNone(data.getVar("FILES"))
        self.assertEqual(data.getVar("FILES:rga"), "/usr/lib/librga.so.*")

    def test_namespaced_wifi_and_vcodec_overrides_keep_dependencies(self):
        for feature, expected in (
            ("rtl8723bs", {"kernel-module-rtw-8723bs", "rtl8723bs-firmware",
                          "rtl8723bs-init", "wpa-supplicant"}),
            ("vcodec", {"kernel-module-rockchip-rga", "kernel-module-rockchip-vdec"}),
        ):
            with self.subTest(feature=feature):
                data = self.parse_config("luckfox-pico-plus",
                                         kernel="mainline", features=feature)
                deps = set(data.getVar("MACHINE_ESSENTIAL_EXTRA_RDEPENDS").split())
                self.assertTrue(expected <= deps)

    def test_vendor_dependencies_keep_shared_sensor_and_phy_modules(self):
        data = self.parse_config("luckfox-pico-plus")
        deps = set(data.getVar("MACHINE_ESSENTIAL_EXTRA_RDEPENDS").split())
        self.assertTrue({
            "kernel-module-sc3336", "kernel-module-phy-rockchip-csi2-dphy",
            "kernel-module-phy-rockchip-csi2-dphy-hw", "kernel-module-video-rkcif",
            "kernel-module-video-rkisp", "kernel-module-rknpu", "kernel-module-rga3",
        } <= deps)
        self.assertFalse({
            "librknnmrt", "kernel-module-rockchip-isp1", "kernel-module-rockchip-cif-vendor",
            "v4l-utils", "i2c-tools",
        } & deps)

    def test_minimal_image_has_no_acceleration_dependencies_or_cma(self):
        data = self.parse_config("luckfox-pico-plus", features="")
        self.assertEqual(data.getVar("MACHINE_ESSENTIAL_EXTRA_RDEPENDS").split(),
                         ["kernel-image", "resize-rootfs"])
        self.assertEqual(data.getVar("LUCKFOX_CMA_SIZE"), "0M")

    def test_machine_soc_and_extlinux_dt_basename(self):
        for board, soc, dt in (
            ("pico", "rv1103", "rv1103g-luckfox-pico"),
            ("pico-plus", "rv1103", "rv1103g-luckfox-pico-plus"),
            ("pico-mini", "rv1103", "rv1103g-luckfox-pico-mini"),
            ("pico-max", "rv1106", "rv1106g-luckfox-pico-pro-max"),
            ("pico-pi", "rv1106", "rv1106g-luckfox-pico-pi"),
        ):
            with self.subTest(board=board):
                data = self.parse_config("luckfox-" + board)
                self.assertEqual(data.getVar("SOC_FAMILY"), soc)
                self.assertEqual(data.getVar("KERNEL_DEVICETREE"), dt + ".dtb")
                self.assertEqual(data.getVar("NONFITDT"), dt + ".dtb")

    def test_mainline_keeps_its_dt_and_source_dependencies(self):
        data = self.parse_config("luckfox-pico-plus", kernel="mainline",
                                 features="camera npu")
        self.assertEqual(data.getVar("KERNEL_DEVICETREE"), "rockchip/original.dtb")
        self.assertEqual(data.getVar("NONFITDT"), "original.dtb")
        deps = data.getVar("MACHINE_ESSENTIAL_EXTRA_RDEPENDS").split()
        self.assertIn("kernel-module-rockchip-cif-vendor", deps)
        self.assertNotIn("librknnmrt", deps)

    def test_libc_minimum_kernel_matches_selected_provider(self):
        for kernel, minimum in (("vendor", "5.10"), ("mainline", "5.15")):
            with self.subTest(kernel=kernel):
                data = self.parse_config("luckfox-pico-mini", kernel=kernel)
                self.assertEqual(data.getVar("OLDEST_KERNEL"), minimum)

    def test_sensor_provider_matches_selected_kernel(self):
        for kernel, provider in (("vendor", "linux-luckfox"),
                                 ("mainline", "sc3336-driver")):
            with self.subTest(kernel=kernel):
                data = self.parse_config("luckfox-pico-mini", kernel=kernel)
                self.assertEqual(data.getVar("PREFERRED_RPROVIDER_kernel-module-sc3336"),
                                 provider)

    def test_measured_nand_geometry_drives_ubi_arguments(self):
        for size, reserved, count in (("134217728", "24", "991"),
                                      ("268435456", "44", "1995")):
            with self.subTest(size=size):
                data = self.parse_config(
                    "luckfox-pico-plus", features="spi-nand",
                    LUCKFOX_NAND_PAGE_SIZE="2048",
                    LUCKFOX_NAND_ERASE_SIZE="131072", LUCKFOX_NAND_SIZE=size)
                self.assertEqual(data.getVar("LUCKFOX_NAND_RESERVED_BLOCKS"), reserved)
                self.assertEqual(data.getVar("MKUBIFS_ARGS"),
                                 "-F -m 2048 -e 126976 -c " + count)
                self.assertEqual(data.getVar("UBINIZE_ARGS"), "-m 2048 -p 131072 -O 2048")

    def test_proprietary_license_flag_is_explicit(self):
        data = self.parse_config("luckfox-pico-plus")
        self.assertNotIn("luckfox-proprietary", data.getVar("LICENSE_FLAGS_ACCEPTED").split())
        data = self.parse_config("luckfox-pico-plus",
                                 LUCKFOX_ALLOW_PROPRIETARY_USERSPACE="1")
        self.assertIn("luckfox-proprietary", data.getVar("LICENSE_FLAGS_ACCEPTED").split())


@unittest.skipUnless(os.environ.get("LUCKFOX_KERNEL_SOURCE"),
                     "Set LUCKFOX_KERNEL_SOURCE to the pinned vendor kernel source")
class VendorSourceTests(unittest.TestCase):
    source = Path(os.environ.get("LUCKFOX_KERNEL_SOURCE", ".")).resolve()

    def test_all_source_feature_combinations_resolve(self):
        fragments = ROOT / "meta-luckfox/recipes-kernel/linux/linux-luckfox"
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp)
            for enabled in itertools.product((False, True), repeat=3):
                names = ["base.cfg"] + [
                    feature + ("-on.cfg" if state else "-off.cfg")
                    for feature, state in zip(("camera", "npu", "rga"), enabled)
                ]
                with self.subTest(enabled=enabled):
                    shutil.copyfile(self.source / "arch/arm/configs/luckfox_rv1106_linux_defconfig",
                                    output / ".config")
                    subprocess.run(
                        [str(self.source / "scripts/kconfig/merge_config.sh"),
                         "-m", "-O", tmp, str(output / ".config")] +
                        [str(fragments / name) for name in names],
                        check=True, stdout=subprocess.DEVNULL)
                    subprocess.run(
                        ["make", "-s", "-C", str(self.source), "O=" + tmp,
                         "ARCH=arm", "HOSTCC=gcc", "olddefconfig"],
                        check=True, stdout=subprocess.DEVNULL)
                    validate_kernel_config((output / ".config").read_text(),
                                           [(fragments / name).read_text() for name in names])

    def test_board_feature_device_trees_compile(self):
        boards = ("rv1103g-luckfox-pico", "rv1103g-luckfox-pico-plus",
                  "rv1103g-luckfox-pico-mini", "rv1106g-luckfox-pico-pro-max",
                  "rv1106g-luckfox-pico-pi")
        for board, enabled in itertools.product(boards, (False, True)):
            with self.subTest(board=board, enabled=enabled), tempfile.TemporaryDirectory() as tmp:
                fixture = Path(tmp)
                dtsdir = fixture / "arch/arm/boot/dts"
                dtsdir.mkdir(parents=True)
                dts = dtsdir / (board + ".dts")
                shutil.copyfile(self.source / "arch/arm/boot/dts" / dts.name, dts)
                configure_vendor_dts(fixture, board + ".dtb",
                                     ["camera", "npu", "rga"] if enabled else [])
                preprocessed = subprocess.run(
                    ["gcc", "-E", "-nostdinc", "-undef", "-D__DTS__",
                     "-x", "assembler-with-cpp", "-I", str(self.source / "include"),
                     "-I", str(self.source / "arch/arm/boot/dts"), str(dts)],
                    check=True, stdout=subprocess.PIPE)
                subprocess.run(["dtc", "-q", "-I", "dts", "-O", "dtb",
                                "-o", str(fixture / "board.dtb")],
                               input=preprocessed.stdout, check=True)
                decoded = subprocess.run(
                    ["dtc", "-q", "-I", "dtb", "-O", "dts",
                     str(fixture / "board.dtb")],
                    check=True, stdout=subprocess.PIPE).stdout.decode()
                status = 'status = "okay";' if enabled else 'status = "disabled";'
                for node in ("npu@ff660000", "rga@ff980000"):
                    block = decoded.split(node + " {", 1)[1].split("};", 1)[0]
                    self.assertIn(status, block)
                for node in ("rkcif@ffa10000", "rkisp@ffa00000"):
                    block = decoded.split(node + " {", 1)[1].split("};", 1)[0]
                    self.assertIn(status, block)
                uart = decoded.split("serial@ff4c0000 {", 1)[1].split("};", 1)[0]
                self.assertIn('status = "okay";', uart)
                fiq = decoded.split("fiq-debugger {", 1)[1].split("};", 1)[0]
                self.assertIn('status = "disabled";', fiq)
                chosen = decoded.split("chosen {", 1)[1].split("};", 1)[0]
                self.assertNotIn("bootargs", chosen)
                self.assertIn('stdout-path = "serial2:115200n8";', chosen)
                if "pico-pi" not in board:
                    sd = decoded.split("mmc@ffaa0000 {", 1)[1].split("};", 1)[0]
                    self.assertNotIn("non-removable", sd)
                    self.assertIn("no-sdio", sd)


if __name__ == "__main__":
    unittest.main()
