#!/bin/bash

# winboot.sh
# sudo ./winboot.sh -i image.iso -o /dev/sdX -m uefi|legacy

set -e

print_usage() {
    echo "Usage: sudo $0 -i <iso_file> -o <target_device> -m <uefi|legacy>"
    exit 1
}

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: use sudo"
    exit 1
fi

while getopts "i:o:m:" opt; do
    case $opt in
        i) ISO_PATH="$OPTARG" ;;
        o) TARGET_DEV="$OPTARG" ;;
        m) BOOT_MODE="$OPTARG" ;;
        *) print_usage ;;
    esac
done

if [ -z "$ISO_PATH" ] || [ -z "$TARGET_DEV" ] || [ -z "$BOOT_MODE" ]; then
    print_usage
fi

if [[ "$BOOT_MODE" != "uefi" && "$BOOT_MODE" != "legacy" ]]; then
    echo "ERROR: unknown mode '$BOOT_MODE'. Use 'uefi' or 'legacy'."
    print_usage
fi

if [ ! -f "$ISO_PATH" ]; then
    echo "ERROR: ISO file '$ISO_PATH' not found."
    exit 1
fi

if [ ! -b "$TARGET_DEV" ]; then
    echo "ERROR: Device '$TARGET_DEV' not found."
    exit 1
fi

echo "WARNING: All data on $TARGET_DEV will be erased!"
read -p "Continue? (y/N): " confirm
if [[ ! $confirm =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

DEPS="rsync parted mkfs.vfat wimsplit"
[ "$BOOT_MODE" == "legacy" ] && DEPS="$DEPS grub-install"

for cmd in $DEPS; do
    if ! command -v $cmd &> /dev/null; then
        case "$cmd" in
            wimsplit)
                echo "Installing wimtools..."
                apt-get update && apt-get install -y wimtools
                ;;
            grub-install)
                echo "Installing grub-pc-bin..."
                apt-get update && apt-get install -y grub-pc-bin
                ;;
            *)
                echo "ERROR: '$cmd' not found."
                exit 1
                ;;
        esac
    fi
done

MNT_ISO=$(mktemp -d)
MNT_USB=$(mktemp -d)

cleanup() {
    echo "Uklízím..."
    umount -l "$MNT_ISO" 2>/dev/null || true
    umount -l "$MNT_USB" 2>/dev/null || true
    rmdir "$MNT_ISO" "$MNT_USB"
}
trap cleanup EXIT

echo "Formátuji $TARGET_DEV (režim: $BOOT_MODE)..."
wipefs -a "$TARGET_DEV"
if [ "$BOOT_MODE" == "uefi" ]; then
    parted "$TARGET_DEV" --script mklabel gpt \
        mkpart primary fat32 1MiB 100% \
        set 1 msftdata on
else
    parted "$TARGET_DEV" --script mklabel msdos \
        mkpart primary fat32 1MiB 100% \
        set 1 boot on
fi

sleep 2
partprobe "$TARGET_DEV" 2>/dev/null || true
sleep 1

if [[ "$TARGET_DEV" == *"nvme"* ]] || [[ "$TARGET_DEV" == *"mmcblk"* ]]; then
    PART="${TARGET_DEV}p1"
else
    PART="${TARGET_DEV}1"
fi

LABEL="WINDOWS"
mkfs.vfat -F 32 -n "$LABEL" "$PART"

# 2. Připojení
echo "Mount ISO and USB..."
mount -o loop "$ISO_PATH" "$MNT_ISO"
mount "$PART" "$MNT_USB"

echo "Copy files..."
rsync -rv --exclude='sources/install.wim' "$MNT_ISO/" "$MNT_USB/"

# 4. Rozdělení install.wim
if [ -f "$MNT_ISO/sources/install.wim" ]; then
    echo "Splitting install.wim (SWM)..."
    wimsplit "$MNT_ISO/sources/install.wim" "$MNT_USB/sources/install.swm" 3800
else
    echo "Warning: sources/install.wim not found. (maybe ESD?) Copying files..."
    if [ -f "$MNT_ISO/sources/install.esd" ]; then
        cp "$MNT_ISO/sources/install.esd" "$MNT_USB/sources/"
    fi
fi

if [ "$BOOT_MODE" == "legacy" ]; then
    echo "Installing GRUB2 MBR bootloader..."
    grub-install \
        --target=i386-pc \
        --boot-directory="$MNT_USB/boot" \
        --removable \
        "$TARGET_DEV"

    cat > "$MNT_USB/boot/grub/grub.cfg" << 'EOF'
set timeout=0
set default=0
menuentry "Windows 10" {
    search --set=root --file /bootmgr
    ntldr /bootmgr
}
EOF
fi

sync
echo "Done, $BOOT_MODE USB installer ready."
