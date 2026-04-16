#!/bin/bash
set -e

# ============================================================
# DROP OS — Installer ISO Builder
# ============================================================
# Produces a bootable USB that INSTALLS DROP OS to disk.
#
# Build:  sudo bash build-installer-iso.sh
# Flash:  sudo dd if=drop-os-installer.iso of=/dev/sdX bs=4M status=progress
# Boot:   USB → auto-installs DROP OS to disk → remove USB → reboot
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

ROOTFS="/tmp/drop-rootfs"
INSTALLER_ROOT="/tmp/drop-installer"
ISO_DIR="/tmp/drop-iso"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="$(pwd)/drop-os-installer.iso"

log() { echo -e "${CYAN}[DROP]${NC} $1"; }
ok()  { echo -e "${GREEN}[DONE]${NC} $1"; }
die() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

[ "$(id -u)" -ne 0 ] && die "Must run as root: sudo bash build-installer-iso.sh"
[ "$(uname -m)" != "x86_64" ] && die "Must run on x86_64 machine"

log "DROP OS Installer ISO Builder"

# Install build deps
apt-get update -qq
apt-get install -y -qq debootstrap grub-pc-bin grub-efi-amd64-bin grub-common \
    xorriso squashfs-tools mtools live-build syslinux syslinux-common isolinux 2>/dev/null || true

rm -rf "$ROOTFS" "$INSTALLER_ROOT" "$ISO_DIR"

# -------------------------------------------------------
# PHASE 1: Build the target rootfs (what gets installed to disk)
# -------------------------------------------------------
log "[1/6] Building DROP OS rootfs..."
debootstrap stable "$ROOTFS" http://deb.debian.org/debian

mount --bind /dev "$ROOTFS/dev"
mount --bind /dev/pts "$ROOTFS/dev/pts"
mount -t proc proc "$ROOTFS/proc"
mount -t sysfs sys "$ROOTFS/sys"

cleanup_rootfs() {
    umount -lf "$ROOTFS/dev/pts" 2>/dev/null || true
    umount -lf "$ROOTFS/dev" 2>/dev/null || true
    umount -lf "$ROOTFS/proc" 2>/dev/null || true
    umount -lf "$ROOTFS/sys" 2>/dev/null || true
}
trap cleanup_rootfs EXIT

chroot "$ROOTFS" /bin/bash -c '
    apt-get update
    apt-get install -y --no-install-recommends \
        linux-image-amd64 \
        grub-pc \
        python3 \
        python3-pip \
        python3-venv \
        docker.io \
        alsa-utils \
        curl \
        git \
        iproute2 \
        dhcpcd5 \
        patch \
        ca-certificates \
        firmware-linux-free \
        pciutils \
        usbutils
    apt-get clean
'

# Copy DROP OS
mkdir -p "$ROOTFS/opt/drop-os"
for dir in ai_core audio memory exec_engine webintel hitl bin; do
    cp -r "$SCRIPT_DIR/$dir" "$ROOTFS/opt/drop-os/"
done
cp "$SCRIPT_DIR/requirements.txt" "$ROOTFS/opt/drop-os/"
chmod +x "$ROOTFS"/opt/drop-os/bin/init-drop
chmod +x "$ROOTFS"/opt/drop-os/bin/drop-*

mkdir -p "$ROOTFS/var/drop-os/memory"
mkdir -p "$ROOTFS/var/drop-os/audio"
touch "$ROOTFS/var/drop-os/webintel_tasks.txt"
touch "$ROOTFS/var/drop-os/hitl_queue.diff"

# Install Python deps
chroot "$ROOTFS" /bin/bash -c 'pip3 install --break-system-packages -r /opt/drop-os/requirements.txt'

# Install Ollama + pull llama3
chroot "$ROOTFS" /bin/bash -c 'curl -fsSL https://ollama.com/install.sh | sh'
chroot "$ROOTFS" /bin/bash -c '
    /usr/local/bin/ollama serve &
    OPID=$!
    for i in $(seq 1 30); do
        curl -s http://localhost:11434/api/tags >/dev/null 2>&1 && break
        sleep 1
    done
    ollama pull llama3
    kill $OPID 2>/dev/null; wait $OPID 2>/dev/null || true
'

# Set hostname
echo "drop-os" > "$ROOTFS/etc/hostname"

# Set fstab (installer will fix UUID later)
cat > "$ROOTFS/etc/fstab" << 'FSTAB'
# <device>  <mount>  <type>  <options>        <dump> <pass>
UUID=XXXX   /        ext4    errors=remount-ro 0      1
FSTAB

ok "Target rootfs built"

cleanup_rootfs

# -------------------------------------------------------
# PHASE 2: Compress rootfs into squashfs
# -------------------------------------------------------
log "[2/6] Compressing rootfs..."
mkdir -p "$ISO_DIR/live"
mksquashfs "$ROOTFS" "$ISO_DIR/live/filesystem.squashfs" -comp xz -quiet
ok "Squashfs created"

# -------------------------------------------------------
# PHASE 3: Build minimal installer environment
# -------------------------------------------------------
log "[3/6] Building installer environment..."
debootstrap --variant=minbase stable "$INSTALLER_ROOT" http://deb.debian.org/debian

mount --bind /dev "$INSTALLER_ROOT/dev"
mount --bind /dev/pts "$INSTALLER_ROOT/dev/pts"
mount -t proc proc "$INSTALLER_ROOT/proc"
mount -t sysfs sys "$INSTALLER_ROOT/sys"

cleanup_installer() {
    umount -lf "$INSTALLER_ROOT/dev/pts" 2>/dev/null || true
    umount -lf "$INSTALLER_ROOT/dev" 2>/dev/null || true
    umount -lf "$INSTALLER_ROOT/proc" 2>/dev/null || true
    umount -lf "$INSTALLER_ROOT/sys" 2>/dev/null || true
}
trap cleanup_installer EXIT

chroot "$INSTALLER_ROOT" /bin/bash -c '
    apt-get update
    apt-get install -y --no-install-recommends \
        linux-image-amd64 \
        grub-pc-bin \
        grub-efi-amd64-bin \
        grub-common \
        grub2-common \
        parted \
        e2fsprogs \
        dosfstools \
        squashfs-tools \
        pciutils \
        util-linux \
        iproute2
    apt-get clean
'

ok "Installer env built"

# -------------------------------------------------------
# PHASE 4: Create the installer script (runs on boot from USB)
# -------------------------------------------------------
log "[4/6] Writing installer script..."

cat > "$INSTALLER_ROOT/usr/local/bin/drop-install" << 'INSTALLER'
#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

clear
echo -e "${BOLD}============================================${NC}"
echo -e "${BOLD}     DROP OS INSTALLER${NC}"
echo -e "${BOLD}============================================${NC}"
echo ""

# List available disks (exclude USB boot device and loop devices)
echo -e "${CYAN}Available disks:${NC}"
echo ""
lsblk -d -n -o NAME,SIZE,MODEL | grep -v "loop\|sr\|ram" | while read line; do
    echo "  /dev/$line"
done
echo ""

# Find the boot device (the USB we booted from)
BOOT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null | sed 's/[0-9]*$//' || echo "")

echo -e "${RED}WARNING: This will ERASE the selected disk entirely.${NC}"
echo ""
read -p "Enter target disk (e.g. /dev/sda): " TARGET

if [ -z "$TARGET" ]; then
    echo "No disk selected. Aborting."
    exit 1
fi

if [ ! -b "$TARGET" ]; then
    echo "ERROR: $TARGET is not a valid block device."
    exit 1
fi

# Safety check
if [ "$TARGET" = "$BOOT_DEV" ]; then
    echo "ERROR: Cannot install to the USB boot device."
    exit 1
fi

echo ""
echo -e "${RED}ALL DATA ON ${TARGET} WILL BE DESTROYED.${NC}"
read -p "Type 'YES' to confirm: " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo -e "${CYAN}[1/5] Partitioning ${TARGET}...${NC}"
# Wipe and create single ext4 partition
wipefs -a "$TARGET"
parted -s "$TARGET" mklabel msdos
parted -s "$TARGET" mkpart primary ext4 1MiB 100%
parted -s "$TARGET" set 1 boot on
sleep 2

# Determine partition name
if echo "$TARGET" | grep -q "nvme\|mmcblk"; then
    PART="${TARGET}p1"
else
    PART="${TARGET}1"
fi

echo -e "${CYAN}[2/5] Formatting ${PART}...${NC}"
mkfs.ext4 -F -L "DROP-OS" "$PART"

echo -e "${CYAN}[3/5] Extracting DROP OS (this takes several minutes)...${NC}"
mkdir -p /mnt/target
mount "$PART" /mnt/target
unsquashfs -f -d /mnt/target /live/filesystem.squashfs

# Fix fstab with actual UUID
UUID=$(blkid -s UUID -o value "$PART")
sed -i "s/UUID=XXXX/UUID=$UUID/" /mnt/target/etc/fstab

echo -e "${CYAN}[4/5] Installing GRUB bootloader...${NC}"
mount --bind /dev /mnt/target/dev
mount --bind /dev/pts /mnt/target/dev/pts
mount -t proc proc /mnt/target/proc
mount -t sysfs sys /mnt/target/sys

# Find kernel version
KVER=$(ls /mnt/target/boot/vmlinuz-* | head -1 | sed 's/.*vmlinuz-//')

chroot /mnt/target /bin/bash -c "
    grub-install --target=i386-pc $TARGET
    cat > /boot/grub/grub.cfg << GRUBCFG
set timeout=3
set default=0

menuentry 'DROP OS — AI Core' {
    linux /boot/vmlinuz-$KVER root=UUID=$UUID ro quiet init=/opt/drop-os/bin/init-drop
    initrd /boot/initrd.img-$KVER
}

menuentry 'DROP OS — Recovery (bash)' {
    linux /boot/vmlinuz-$KVER root=UUID=$UUID ro init=/bin/bash
    initrd /boot/initrd.img-$KVER
}
GRUBCFG
"

umount -lf /mnt/target/dev/pts
umount -lf /mnt/target/dev
umount -lf /mnt/target/proc
umount -lf /mnt/target/sys

echo -e "${CYAN}[5/5] Syncing...${NC}"
sync
umount /mnt/target

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  DROP OS installed successfully!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo "Remove the USB drive and reboot."
echo "You will boot directly into DROP OS AI Core."
echo ""
read -p "Press ENTER to reboot..." _
reboot -f
INSTALLER

chmod +x "$INSTALLER_ROOT/usr/local/bin/drop-install"

# Create init that auto-launches installer
cat > "$INSTALLER_ROOT/usr/local/bin/drop-installer-init" << 'INITSCRIPT'
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev
mkdir -p /dev/pts
mount -t devpts devpts /dev/pts

# Bring up console
export TERM=linux
export HOME=/root
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Mount the squashfs from the ISO
mkdir -p /live
mount -t squashfs /boot/live/filesystem.squashfs /live 2>/dev/null || true

# Clear and launch installer
clear
exec /usr/local/bin/drop-install
INITSCRIPT

chmod +x "$INSTALLER_ROOT/usr/local/bin/drop-installer-init"

# Copy squashfs into installer so it's accessible
mkdir -p "$INSTALLER_ROOT/live"
cp "$ISO_DIR/live/filesystem.squashfs" "$INSTALLER_ROOT/live/"

ok "Installer script created"

cleanup_installer

# -------------------------------------------------------
# PHASE 5: Build the installer ISO
# -------------------------------------------------------
log "[5/6] Assembling ISO..."

INST_ISO="/tmp/drop-inst-iso"
rm -rf "$INST_ISO"
mkdir -p "$INST_ISO/boot/grub"
mkdir -p "$INST_ISO/live"

# Copy installer kernel + initrd
KERNEL=$(ls "$INSTALLER_ROOT"/boot/vmlinuz-* | sort -V | tail -1)
INITRD=$(ls "$INSTALLER_ROOT"/boot/initrd.img-* | sort -V | tail -1)
KBASE=$(basename "$KERNEL")
IBASE=$(basename "$INITRD")

cp "$KERNEL" "$INST_ISO/boot/$KBASE"
cp "$INITRD" "$INST_ISO/boot/$IBASE"

# Squashfs the installer environment
mksquashfs "$INSTALLER_ROOT" "$INST_ISO/live/installer.squashfs" -comp xz -quiet

# Copy the DROP OS rootfs squashfs too
cp "$ISO_DIR/live/filesystem.squashfs" "$INST_ISO/live/"

# GRUB config for the installer USB
cat > "$INST_ISO/boot/grub/grub.cfg" << GRUBEOF
set timeout=5
set default=0

menuentry "INSTALL DROP OS" {
    linux /boot/$KBASE boot=live toram init=/usr/local/bin/drop-installer-init
    initrd /boot/$IBASE
}

menuentry "Boot from disk (skip installer)" {
    set root=(hd1)
    chainloader +1
}
GRUBEOF

# -------------------------------------------------------
# PHASE 6: Build ISO image
# -------------------------------------------------------
log "[6/6] Building installer ISO..."
grub-mkrescue -o "$OUTPUT" "$INST_ISO" 2>/dev/null

ok "Installer ISO built!"

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  DROP OS Installer ISO: $OUTPUT${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "USAGE:"
echo "  1. Flash to USB:"
echo "     sudo dd if=$OUTPUT of=/dev/sdX bs=4M status=progress"
echo ""
echo "  2. Boot your Thermaltake tower from USB"
echo ""
echo "  3. Installer runs automatically:"
echo "     - Shows available disks"
echo "     - You pick the target disk"
echo "     - Formats, extracts DROP OS, installs GRUB"
echo ""
echo "  4. Remove USB, reboot → DROP OS AI Core"
echo "     you> _"
