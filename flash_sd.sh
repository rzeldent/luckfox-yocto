#!/bin/bash
#
# Flash an SD card with a built Yocto image using `bmaptool`.
#
# The image is copied to a raw block device, so make sure DEVICE points at the
# card and not at one of your disks - this will destroy its contents.
#
# Usage: sudo ./flash_sd.sh [OPTIONS]
#
# Run with --help for the full option list.

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# SD card images come from the "-sd-card" machines; the suffix is added if omitted.
MACHINE="${MACHINE:-luckfox-pico-max-sd-card}"
DEPLOY_DIR=""
DEPLOY_DIR_SET=false

IMAGE=""
DEVICE=""

ERASE_FIRST=false
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

Flash an SD card with a built Yocto image.

Options:
  -m, --machine NAME     Machine whose image to flash (-sd-card suffix optional)
                         (default: $MACHINE)
  -d, --deploy-dir DIR   Yocto deploy directory
                         (default: <repo>/build/tmp/deploy/images/<machine>)
  -i, --image FILE       .wic image to write (default: auto-detected)
  -D, --device DEV       Target block device, e.g. /dev/sdb (required)
  -e, --erase            Zero the start of the card before writing
  -y, --yes              Do not ask for confirmation
  -n, --dry-run          Print the commands without executing them
  -h, --help             Show this help

Examples:
  sudo $0 -D /dev/sdb
  sudo $0 -m luckfox-pico-plus-sd-card -D /dev/sdb
  sudo $0 -D /dev/sdb -e -y
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
            -i|--image)      IMAGE="$2"; shift 2 ;;
            -D|--device)     DEVICE="$2"; shift 2 ;;
            -e|--erase)      ERASE_FIRST=true; shift ;;
            -y|--yes)        ASSUME_YES=true; shift ;;
            -n|--dry-run)    DRY_RUN=true; shift ;;
            -h|--help)       usage; exit 0 ;;
            *) die "Unknown option: $1 (try --help)" ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Discovery / validation
# ---------------------------------------------------------------------------

# newest_match <glob> -> prints the most recently modified match
newest_match() {
    local pattern="$1"
    # shellcheck disable=SC2086
    ls -1t $pattern 2>/dev/null | head -n 1
}

discover_image() {
    [[ "$MACHINE" == *-sd-card ]] || MACHINE="${MACHINE}-sd-card"

    # Derive the deploy dir from the machine unless it was set explicitly.
    if [[ "$DEPLOY_DIR_SET" != true ]]; then
        DEPLOY_DIR="$SCRIPT_DIR/build/tmp/deploy/images/${MACHINE}"
    fi

    [[ -d "$DEPLOY_DIR" ]] || die "Deploy directory not found: $DEPLOY_DIR"

    if [[ -z "$IMAGE" ]]; then
        # Prefer the stable symlink, fall back to the newest timestamped file.
        IMAGE="$DEPLOY_DIR/core-image-base-${MACHINE}.rootfs.wic"
        if [[ ! -e "$IMAGE" ]]; then
            IMAGE="$(newest_match "$DEPLOY_DIR/*.rootfs-*.wic")"
        fi
    fi

    [[ -n "$IMAGE" ]] || die "No .wic image found in $DEPLOY_DIR (use -i)"
    [[ -f "$IMAGE" ]] || die "File not found: $IMAGE"

    [[ -n "$DEVICE" ]] || die "No target device given (use -D /dev/sdX)"
    [[ -b "$DEVICE" ]] || die "Not a block device: $DEVICE"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    parse_args "$@"

    if [[ "$DRY_RUN" != true && "$(id -u)" -ne 0 ]]; then
        log_info "Writing to a block device needs root; re-running with sudo..."
        exec sudo "$0" "$@"
    fi

    discover_image

    local image_size
    image_size=$(stat -L -c %s "$IMAGE")

    echo
    log_info "Machine    : $MACHINE"
    log_info "Deploy dir : $DEPLOY_DIR"
    log_info "Image      : $IMAGE ($image_size bytes)"
    log_info "Device     : $DEVICE"
    echo

    # Show what the device currently is, so the user can sanity-check it.
    if command -v lsblk >/dev/null 2>&1; then
        lsblk -o NAME,SIZE,MODEL,MOUNTPOINT "$DEVICE" || true
        echo
    fi

    if [[ "$ASSUME_YES" != true && "$DRY_RUN" != true ]]; then
        log_warn "This will overwrite all data on $DEVICE."
        read -r -p "Continue? (y/N) " reply
        [[ "$reply" =~ ^[Yy]$ ]] || { log_info "Aborted."; exit 0; }
    fi

    # --- optional erase ------------------------------------------------------
    if [[ "$ERASE_FIRST" == true ]]; then
        log_info "Zeroing the start of $DEVICE..."
        if [[ "$DRY_RUN" == true ]]; then
            echo "    dd if=/dev/zero of=$DEVICE bs=1M count=32 conv=fsync"
        else
            dd if=/dev/zero of="$DEVICE" bs=1M count=32 conv=fsync
        fi
        log_ok "Card erased"
    fi

    # --- write ---------------------------------------------------------------
    log_info "Writing image with bmaptool..."
    if [[ "$DRY_RUN" == true ]]; then
        echo "    bmaptool copy $IMAGE $DEVICE"
        echo
        log_ok "Dry run complete."
        return 0
    fi

    bmaptool copy "$IMAGE" "$DEVICE"

    sync
    log_ok "Image written to $DEVICE"

    echo
    log_ok "Done. Insert the card into the board and power it on."
}

main "$@"
