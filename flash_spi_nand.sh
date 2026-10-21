#!/bin/bash
#
# Flash the Luckfox Pico Mini (RV1103) SPI NAND from the host over USB
# (RockChip MaskROM / Loader mode) using RockChip's `upgrade_tool`.
#
# This is the host-side alternative to the on-target procedure documented in
# flash_spi_nand.md (which requires booting from an SD card first).
#
# Layout written (matches U-Boot's mtdparts=spi0.0:128k(spl),1m(uboot),-(rootfs)):
#
#   0x000000  spl     idbloader.img-spi-nand-*.img   (128 KiB)
#   0x020000  uboot   u-boot-spi-nand-*.img          (1 MiB)
#   0x120000  rootfs  core-image-*.rootfs-*.ubi      (rest of the NAND)
#
# The whole flash is erased before anything is written. A .ubi is normally
# smaller than its partition, and UBI refuses to attach if any PEB still holds
# another image's sequence number, so writing over an existing image without
# erasing leaves a stale tail that only shows up much later, as
# "bad image sequence number" during boot.
#
# Usage: sudo ./flash_spi_nand.sh [OPTIONS]
#
# Run with --help for the full option list.

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# RockChip upgrade_tool must be invoked from its own directory so that it finds
# its config.ini.
TOOL_DIR="${TOOL_DIR:-/home/rene/repos/luckfox-pico/tools/linux/Linux_Upgrade_Tool}"
TOOL_BIN="upgrade_tool"

# The loader (DDR init + usbplug) shipped with the Luckfox SDK. The loaders in
# rkbin/ are rejected by this chip ("wrong hash of loader").
LOADER="${LOADER:-/home/rene/repos/luckfox-pico/output/image/download.bin}"

# NAND images come from the "-spi-nand" machines; the suffix is added if omitted.
MACHINE="${MACHINE:-luckfox-pico-mini-spi-nand}"
DEPLOY_DIR="${DEPLOY_DIR:-$SCRIPT_DIR/build/tmp/deploy/images/${MACHINE}}"

IDBLOADER_FILE=""
UBOOT_FILE=""
ROOTFS_FILE=""

# Partition offsets. U-Boot's mtdparts is byte-based
# (mtdparts=spi0.0:128k(spl),1m(uboot),-(rootfs)), but upgrade_tool's WL/EL
# take 512-byte sector numbers, so convert.
SPL_OFFSET=$((0x000000 / 512))     # byte 0x000000
UBOOT_OFFSET=$((0x020000 / 512))   # byte 0x020000
ROOTFS_OFFSET=$((0x120000 / 512))  # byte 0x120000

ERASE_FIRST=true
ASSUME_YES=false
DRY_RUN=false

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

if [[ -t 1 ]]; then
    C_RED=$'\033[31;1m'; C_GREEN=$'\033[32;1m'; C_YELLOW=$'\033[33;1m'
    C_BLUE=$'\033[34;1m'; C_NORMAL=$'\033[0m'
else
    C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_NORMAL=""
fi

log_info()  { echo "${C_BLUE}[INFO]${C_NORMAL}  $*"; }
log_ok()    { echo "${C_GREEN}[ OK ]${C_NORMAL}  $*"; }
log_warn()  { echo "${C_YELLOW}[WARN]${C_NORMAL}  $*" >&2; }
log_error() { echo "${C_RED}[FAIL]${C_NORMAL}  $*" >&2; }

die() { log_error "$*"; exit 1; }

usage() {
    cat <<EOF
Usage: sudo $0 [OPTIONS]

Flash the SPI NAND of a Luckfox Pico Mini (RV1103) over USB.

Options:
  -m, --machine NAME     Machine whose image to flash
                         (default: $MACHINE)
  -d, --deploy-dir DIR   Yocto deploy directory
                         (default: <repo>/build/tmp/deploy/images/<machine>)
  -t, --tool-dir DIR     Directory containing upgrade_tool + config.ini
                         (default: $TOOL_DIR)
  -l, --loader FILE      Loader used for DownloadBoot
                         (default: $LOADER)
  -i, --idbloader FILE   SPL image (default: auto-detected in deploy dir)
  -u, --uboot FILE       U-Boot image (default: auto-detected in deploy dir)
  -r, --rootfs FILE      Root filesystem .ubi (default: auto-detected)
  -e, --erase            Erase the whole flash before writing (default)
      --no-erase         Skip the erase; only safe when the .ubi fills the
                         whole rootfs partition
  -y, --yes              Do not ask for confirmation
  -n, --dry-run          Print the commands without executing them
  -h, --help             Show this help

Examples:
  sudo $0
  sudo $0 --no-erase
  sudo $0 -m luckfox-pico-max-spi-nand
  sudo $0 --deploy-dir build/tmp/deploy/images/luckfox-pico-mini-spi-nand
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--machine)    MACHINE="$2"; shift 2 ;;
            -d|--deploy-dir) DEPLOY_DIR="$2"; DEPLOY_DIR_SET=true; shift 2 ;;
            -t|--tool-dir)   TOOL_DIR="$2";   shift 2 ;;
            -l|--loader)     LOADER="$2";     shift 2 ;;
            -i|--idbloader)  IDBLOADER_FILE="$2"; shift 2 ;;
            -u|--uboot)      UBOOT_FILE="$2"; shift 2 ;;
            -r|--rootfs)     ROOTFS_FILE="$2"; shift 2 ;;
            -e|--erase)      ERASE_FIRST=true; shift ;;
            --no-erase)      ERASE_FIRST=false; shift ;;
            -y|--yes)        ASSUME_YES=true; shift ;;
            -n|--dry-run)    DRY_RUN=true; shift ;;
            -h|--help)       usage; exit 0 ;;
            *) die "Unknown option: $1 (try --help)" ;;
        esac
    done
    
    [[ "$MACHINE" == *-spi-nand ]] || MACHINE="${MACHINE}-spi-nand"

    # Recompute DEPLOY_DIR if not explicitly set and MACHINE changed
    if [[ -z "${DEPLOY_DIR_SET:-}" ]]; then
        DEPLOY_DIR="$SCRIPT_DIR/build/tmp/deploy/images/${MACHINE}"
    fi
}

# ---------------------------------------------------------------------------
# Discovery / validation
# ---------------------------------------------------------------------------

# newest_match <glob> -> prints the most recently modified match, or nothing
newest_match() {
    local pattern="$1"
    # shellcheck disable=SC2086
    ls -1t $pattern 2>/dev/null | head -n 1 || true
}

# has_magic <file> <magic> -- true when the file starts with the given magic
has_magic() {
    [[ "$(head -c ${#2} "$1" 2>/dev/null)" == "$2" ]]
}

discover_images() {
    [[ -d "$DEPLOY_DIR" ]] || die "Deploy directory not found: $DEPLOY_DIR"

    if [[ -z "$IDBLOADER_FILE" ]]; then
        IDBLOADER_FILE="$(newest_match "$DEPLOY_DIR/idbloader.img-spi-nand-*")"
        [[ -n "$IDBLOADER_FILE" ]] || IDBLOADER_FILE="$(newest_match "$DEPLOY_DIR/idbloader.img*")"
    fi
    if [[ -z "$UBOOT_FILE" ]]; then
        UBOOT_FILE="$(newest_match "$DEPLOY_DIR/u-boot-spi-nand-*.img")"
        [[ -n "$UBOOT_FILE" ]] || UBOOT_FILE="$(newest_match "$DEPLOY_DIR/u-boot*.img")"
    fi
    if [[ -z "$ROOTFS_FILE" ]]; then
        ROOTFS_FILE="$(newest_match "$DEPLOY_DIR/*.rootfs-*.ubi")"
        [[ -n "$ROOTFS_FILE" ]] || ROOTFS_FILE="$(newest_match "$DEPLOY_DIR/*.ubi")"
    fi

    [[ -n "$IDBLOADER_FILE" ]] || die "No idbloader image found in $DEPLOY_DIR (use -i)"
    [[ -n "$UBOOT_FILE" ]]     || die "No u-boot image found in $DEPLOY_DIR (use -u)"
    [[ -n "$ROOTFS_FILE" ]]    || die "No rootfs .ubi found in $DEPLOY_DIR (use -r)"

    for f in "$IDBLOADER_FILE" "$UBOOT_FILE" "$ROOTFS_FILE" "$LOADER"; do
        [[ -f "$f" ]] || die "File not found: $f"
    done

    # A wrong file here produces a board that neither boots nor explains why:
    # a non-IDB at offset 0 is not bootable, and a non-UBI image in the rootfs
    # partition makes UBI fail to attach.
    has_magic "$IDBLOADER_FILE" "RKNS" \
        || die "$(basename "$IDBLOADER_FILE") is not a RockChip IDB (no RKNS magic)"
    has_magic "$ROOTFS_FILE" "UBI#" \
        || die "$(basename "$ROOTFS_FILE") is not a UBI image (no UBI# magic)"

    [[ -x "$TOOL_DIR/$TOOL_BIN" ]] || die "$TOOL_DIR/$TOOL_BIN not found or not executable"
}

# ---------------------------------------------------------------------------
# upgrade_tool wrapper
# ---------------------------------------------------------------------------

# run_tool <args...>  -- always executes from TOOL_DIR so config.ini is found
run_tool() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "    (cd $TOOL_DIR && ./$TOOL_BIN $*)"
        return 0
    fi
    ( cd "$TOOL_DIR" && "./$TOOL_BIN" "$@" )
}

# device_present -- true when a RockChip USB device is in MaskROM/Loader mode
device_present() {
    lsusb 2>/dev/null | grep -q '2207:110c'
}

# wait_for_device <timeout-seconds>
wait_for_device() {
    local timeout="${1:-30}" waited=0
    while (( waited < timeout )); do
        device_present && return 0
        sleep 1
        waited=$((waited + 1))
    done
    return 1
}

# enter_loader_mode -- DownloadBoot the loader so the device accepts WL commands
enter_loader_mode() {
    local attempt
    for attempt in 1 2 3; do
        log_info "DownloadBoot loader (attempt $attempt): $(basename "$LOADER")"
        if run_tool DB "$LOADER"; then
            log_ok "Device is in Loader mode"
            return 0
        fi
        log_warn "DownloadBoot failed."
        if [[ "$DRY_RUN" == true ]]; then
            return 0
        fi
        if [[ "$ASSUME_YES" != true ]]; then
            read -r -p "Unplug/replug the board (or press its RESET button), then press Enter to retry..." _
        else
            sleep 3
        fi
    done
    die "Could not put the device into Loader mode. Reset the board and try again."
}

# write_image <offset> <file> [size-in-sectors]
write_image() {
    local offset="$1" file="$2" size="${3:-}"
    log_info "Writing $(basename "$file") at $offset"
    if [[ -n "$size" ]]; then
        run_tool WL "$offset" "$size" "$file"
    else
        run_tool WL "$offset" "$file"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    parse_args "$@"

    if [[ "$DRY_RUN" != true && "$(id -u)" -ne 0 ]]; then
        # Claiming the USB interface needs write access to the device node.
        # The 88-rockusb.rules shipped with upgrade_tool grants that, but it is
        # not installed by default, so fall back to sudo.
        if ! ( cd "$TOOL_DIR" && "./$TOOL_BIN" LD ) &>/dev/null; then
            log_info "Cannot access the RockChip USB device; re-running with sudo..."
            exec sudo "$0" "$@"
        fi
    fi

    discover_images

    local rootfs_size rootfs_sectors
    rootfs_size=$(stat -c %s "$ROOTFS_FILE")
    rootfs_sectors=$(( (rootfs_size + 511) / 512 ))

    echo
    log_info "Machine    : $MACHINE"
    log_info "Deploy dir : $DEPLOY_DIR"
    log_info "Tool dir   : $TOOL_DIR"
    log_info "Loader     : $LOADER"
    log_info "SPL        : $IDBLOADER_FILE"
    log_info "U-Boot     : $UBOOT_FILE"
    log_info "Rootfs     : $ROOTFS_FILE ($rootfs_size bytes = $rootfs_sectors sectors)"
    echo

    if ! device_present; then
        log_warn "No RockChip USB device (2207:110c) detected."
        log_warn "Put the board into MaskROM mode: hold BOOT, plug USB, release BOOT."
        if [[ "$ASSUME_YES" != true && "$DRY_RUN" != true ]]; then
            read -r -p "Press Enter once the board is connected, or Ctrl-C to abort..." _
        fi
        wait_for_device 30 || die "Device did not appear."
    fi

    if [[ "$ASSUME_YES" != true && "$DRY_RUN" != true ]]; then
        echo
        log_warn "This erases and rewrites the SPI NAND of the connected board."
        read -r -p "Continue? (y/N) " reply
        [[ "$reply" =~ ^[Yy]$ ]] || { log_info "Aborted."; exit 0; }
    fi

    # --- DownloadBoot once ---------------------------------------------------
    # The device stays in loader mode for the whole session, so all three writes
    # belong here: the vendor's own rkdownload.sh does a single `db` followed by
    # every `wl`. Re-issuing DB per write fails, because as soon as a valid IDB
    # is in the flash the BROM boots it instead of waiting in MaskROM, and DB
    # can only attach to a device still sitting in MaskROM.
    enter_loader_mode

    # --- Erase ---------------------------------------------------------------
    # The vendor's rkdownload.sh erases the same way: `db` then `el 0 -1`.
    # Doing it in-session avoids a second DB, which cannot attach once a
    # bootable IDB is present.
    if [[ "$ERASE_FIRST" == true ]]; then
        log_info "Erasing the whole flash..."
        run_tool EL 0 -1
        log_ok "Flash erased"
    else
        log_warn "Skipping the erase; the .ubi must fill its partition or UBI" \
                 "will fail to attach at boot (bad image sequence number)."
    fi

    # --- Root filesystem -----------------------------------------------------
    # The IDB/SPL goes last on purpose: it is the thing that makes the BROM boot
    # from the flash, so if an earlier write fails the board still comes up in
    # MaskROM rather than looping on an incomplete image.
    write_image "$ROOTFS_OFFSET" "$ROOTFS_FILE" "$rootfs_sectors"
    log_ok "Root filesystem written"

    # --- U-Boot --------------------------------------------------------------
    write_image "$UBOOT_OFFSET" "$UBOOT_FILE"
    log_ok "U-Boot written"

    # --- SPL / IDB -----------------------------------------------------------
    write_image "$SPL_OFFSET" "$IDBLOADER_FILE"
    log_ok "SPL written"

    # --- Reset ---------------------------------------------------------------
    log_info "Resetting the device..."
    run_tool RD || log_warn "Reset command failed; power-cycle the board manually."

    echo
    log_ok "Done. The board should now boot from SPI NAND."
}

main "$@"
