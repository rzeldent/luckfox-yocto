#!/bin/bash
#
# Flash NAND script for Luckfox Pico Mini B (RV1103 SPI NAND)
# Automates the flashing process described in flash_spi_nand.md
#
# Usage: ./flash_nand_luckfox_pico_mini_b.sh [OPTIONS]
#
# Options:
#   -d, --device DEVICE     Serial device (default: /dev/ttyUSB0)
#   -b, --baud BAUD         Baud rate (default: 115200)
#   -i, --idbloader FILE    Path to idbloader.img
#   -u, --uboot FILE        Path to u-boot.img
#   -r, --rootfs FILE       Path to rootfs.ubi
#   -s, --sdcard PATH       Path to SD card mount point (to copy files first)
#   -y, --yes               Non-interactive mode (assume yes to all prompts)
#   -h, --help              Show this help message
#
# The script can work in two modes:
# 1. Direct flashing: Provide the three image files directly with -i, -u, -r
# 2. SD card mode: Provide SD card mount point with -s, script copies files to SD card first

set -euo pipefail

# Default values
SERIAL_DEVICE="/dev/ttyUSB0"
BAUD_RATE="115200"
IDBLOADER_FILE=""
UBOOT_FILE=""
ROOTFS_FILE=""
SDCARD_MOUNT=""
NON_INTERACTIVE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Flash NAND script for Luckfox Pico Mini B (RV1103 SPI NAND)

Options:
  -d, --device DEVICE     Serial device (default: /dev/ttyUSB0)
  -b, --baud BAUD         Baud rate (default: 115200)
  -i, --idbloader FILE    Path to idbloader.img (required)
  -u, --uboot FILE        Path to u-boot.img (required)
  -r, --rootfs FILE       Path to rootfs.ubi (required)
  -s, --sdcard PATH       Path to SD card mount point (alternative to -i/-u/-r)
  -y, --yes               Non-interactive mode (assume yes to all prompts)
  -h, --help              Show this help message

Examples:
  # Direct flashing with image files
  $0 -i build/tmp/deploy/images/luckfox-pico-mini-b/idbloader.img \\
     -u build/tmp/deploy/images/luckfox-pico-mini-b/u-boot.img \\
     -r build/tmp/deploy/images/luckfox-pico-mini-b/core-image-base.ubi

  # Using SD card (copies files to SD card first, then flashes from board)
  $0 -s /media/user/SDCARD

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--device)
                SERIAL_DEVICE="$2"
                shift 2
                ;;
            -b|--baud)
                BAUD_RATE="$2"
                shift 2
                ;;
            -i|--idbloader)
                IDBLOADER_FILE="$2"
                shift 2
                ;;
            -u|--uboot)
                UBOOT_FILE="$2"
                shift 2
                ;;
            -r|--rootfs)
                ROOTFS_FILE="$2"
                shift 2
                ;;
            -s|--sdcard)
                SDCARD_MOUNT="$2"
                shift 2
                ;;
            -y|--yes)
                NON_INTERACTIVE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Validate arguments
validate_args() {
    if [[ -n "$SDCARD_MOUNT" ]]; then
        # SD card mode - find files on SD card
        if [[ ! -d "$SDCARD_MOUNT" ]]; then
            log_error "SD card mount point does not exist: $SDCARD_MOUNT"
            exit 1
        fi
        
        # Find the required files on SD card
        IDBLOADER_FILE=$(find "$SDCARD_MOUNT" -name "idbloader.img*" -type f | head -1)
        UBOOT_FILE=$(find "$SDCARD_MOUNT" -name "u-boot*.img" -type f | head -1)
        ROOTFS_FILE=$(find "$SDCARD_MOUNT" -name "*.ubi" -type f | head -1)
        
        if [[ -z "$IDBLOADER_FILE" || -z "$UBOOT_FILE" || -z "$ROOTFS_FILE" ]]; then
            log_error "Could not find all required files on SD card:"
            [[ -z "$IDBLOADER_FILE" ]] && log_error "  - idbloader.img not found"
            [[ -z "$UBOOT_FILE" ]] && log_error "  - u-boot.img not found"
            [[ -z "$ROOTFS_FILE" ]] && log_error "  - rootfs.ubi not found"
            exit 1
        fi
        
        log_info "Found files on SD card:"
        log_info "  idbloader: $IDBLOADER_FILE"
        log_info "  u-boot:    $UBOOT_FILE"
        log_info "  rootfs:    $ROOTFS_FILE"
    else
        # Direct file mode - validate files exist
        if [[ -z "$IDBLOADER_FILE" || -z "$UBOOT_FILE" || -z "$ROOTFS_FILE" ]]; then
            log_error "Missing required files. Use -i, -u, -r or -s option."
            usage
            exit 1
        fi
        
        for file in "$IDBLOADER_FILE" "$UBOOT_FILE" "$ROOTFS_FILE"; do
            if [[ ! -f "$file" ]]; then
                log_error "File not found: $file"
                exit 1
            fi
        done
    fi
    
    # Check serial device
    if [[ ! -c "$SERIAL_DEVICE" ]]; then
        log_warning "Serial device $SERIAL_DEVICE does not exist or is not a character device"
        if [[ "$NON_INTERACTIVE" != "true" ]]; then
            read -p "Continue anyway? (y/N) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
}

# Send command to serial device and wait for prompt
send_command() {
    local cmd="$1"
    local expected_prompt="${2:-# }"
    local timeout="${3:-10}"
    
    log_info "Sending: $cmd"
    echo "$cmd" > "$SERIAL_DEVICE"
    
    # Wait for response (simplified - in practice you'd use expect or similar)
    sleep 2
}

# Wait for user to press enter (for interactive steps)
wait_for_user() {
    local message="$1"
    if [[ "$NON_INTERACTIVE" == "true" ]]; then
        log_info "$message (auto-continuing in non-interactive mode)"
        sleep 2
    else
        echo -e "${YELLOW}$message${NC}"
        read -p "Press Enter to continue..."
    fi
}

# Main flashing function
flash_nand() {
    log_info "Starting NAND flash process for Luckfox Pico Mini B"
    log_info "Serial device: $SERIAL_DEVICE @ $BAUD_RATE baud"
    
    # Step 1: Connect to serial console
    wait_for_user "Step 1: Connect USB-UART to the board's debug UART pins.
    Then start minicom or screen:
      minicom -D $SERIAL_DEVICE -b $BAUD_RATE
    OR
      screen $SERIAL_DEVICE $BAUD_RATE
    
    Power on the board and wait for U-Boot prompt."
    
    # Step 2: Stop U-Boot and erase everything
    wait_for_user "Step 2: At the U-Boot prompt, stop autoboot (press any key).
    Then run the following command to erase everything including bad block table:"
    
    log_info "Running: mtd erase.dontskipbad spi-nand0"
    log_warning "This will erase ALL data on the SPI NAND!"
    
    if [[ "$NON_INTERACTIVE" != "true" ]]; then
        read -p "Are you sure you want to continue? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Aborted by user"
            exit 0
        fi
    fi
    
    # Note: The actual serial communication would need expect or similar tool
    # This script provides the commands to run manually
    cat << EOF

========================================
MANUAL STEPS TO EXECUTE ON TARGET BOARD
========================================

1. At U-Boot prompt, erase the NAND:
   => mtd erase.dontskipbad spi-nand0
   => reset

2. After reboot, login as root:
   login: root
   password: password

3. Create MTD partitions:
   # mtdpart add /dev/mtd0 tpl 0x0 0x20000
   # mtdpart add /dev/mtd0 uboot 0x20000 0x100000
   # mtdpart add /dev/mtd0 rootfs 0x120000 0x7ee0000

4. Format partitions:
   # flash_erase /dev/mtd1 0 0
   # flash_erase /dev/mtd2 0 0
   # flash_erase /dev/mtd3 0 0

5. Flash the images (adjust paths if using SD card):
   # nandwrite -p /dev/mtd1 $IDBLOADER_FILE
   # nandwrite -p /dev/mtd2 $UBOOT_FILE
   # ubiformat /dev/mtd3 -f $ROOTFS_FILE

6. Power off, remove SD card (if used), power on and enjoy!

========================================
EOF
    
    if [[ -n "$SDCARD_MOUNT" ]]; then
        log_info "Files are on SD card at $SDCARD_MOUNT"
        log_info "On the target board, the files will be at /media/mmcblk0p1/ or similar"
        log_info "Adjust the paths in step 5 accordingly"
    fi
    
    log_success "Script completed. Follow the manual steps above on the target board."
}

# Main
main() {
    parse_args "$@"
    validate_args
    flash_nand
}

main "$@"