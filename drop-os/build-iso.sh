#!/bin/bash
set -e

# ============================================================
# DROP OS — One-Command ISO Builder
# ============================================================
# Run on any x86_64 Debian/Ubuntu machine as root:
#
#   sudo bash build-iso.sh
#
# Produces: ./drop-os.iso
# Flash:    sudo dd if=drop-os.iso of=/dev/sdX bs=4M status=progress
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

ROOTFS="/tmp/drop-root"
ISO_DIR="/tmp/drop-iso"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT="$(pwd)/drop-os.iso"

log() { echo -e "${CYAN}[DROP]${NC} $1"; }
ok()  { echo -e "${GREEN}[DONE]${NC} $1"; }
die() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }

# -----------------------------------------------------------
# Preflight checks
# -----------------------------------------------------------
[ "$(id -u)" -ne 0 ] && die "Must run as root: sudo bash build-iso.sh"
[ "$(uname -m)" != "x86_64" ] && die "Must run on x86_64 machine (your Thermaltake tower)"

log "DROP OS ISO Builder starting..."
log "Output will be: $OUTPUT"

# -----------------------------------------------------------
# Install build tools if missing
# -----------------------------------------------------------
log "Checking build dependencies..."
DEPS="debootstrap grub-pc-bin grub-efi-amd64-bin grub-common xorriso squashfs-tools mtools"
apt-get update -qq
apt-get install -y -qq $DEPS
ok "Build tools ready"

# -----------------------------------------------------------
# Clean previous builds
# -----------------------------------------------------------
rm -rf "$ROOTFS" "$ISO_DIR"

# -----------------------------------------------------------
# STEP 1: Debootstrap — create Debian rootfs
# -----------------------------------------------------------
log "[1/8] Creating Debian stable rootfs (this takes a few minutes)..."
debootstrap stable "$ROOTFS" http://deb.debian.org/debian
ok "Rootfs created"

# -----------------------------------------------------------
# STEP 2: Mount for chroot
# -----------------------------------------------------------
log "[2/8] Mounting virtual filesystems..."
mount --bind /dev "$ROOTFS/dev"
mount --bind /dev/pts "$ROOTFS/dev/pts"
mount -t proc proc "$ROOTFS/proc"
mount -t sysfs sys "$ROOTFS/sys"

cleanup() {
    log "Cleaning up mounts..."
    umount -lf "$ROOTFS/dev/pts" 2>/dev/null || true
    umount -lf "$ROOTFS/dev" 2>/dev/null || true
    umount -lf "$ROOTFS/proc" 2>/dev/null || true
    umount -lf "$ROOTFS/sys" 2>/dev/null || true
}
trap cleanup EXIT
ok "Mounts ready"

# -----------------------------------------------------------
# STEP 3: Install system packages inside chroot
# -----------------------------------------------------------
log "[3/8] Installing system packages in chroot..."
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
        patch \
        ca-certificates \
        firmware-linux-free
    apt-get clean
'
ok "System packages installed"

# -----------------------------------------------------------
# STEP 4: Copy DROP OS source tree
# -----------------------------------------------------------
log "[4/8] Copying DROP OS into rootfs..."
mkdir -p "$ROOTFS/opt/drop-os"
for dir in ai_core audio memory exec_engine webintel hitl bin; do
    cp -r "$SCRIPT_DIR/$dir" "$ROOTFS/opt/drop-os/"
done
cp "$SCRIPT_DIR/requirements.txt" "$ROOTFS/opt/drop-os/"

chmod +x "$ROOTFS"/opt/drop-os/bin/init-drop
chmod +x "$ROOTFS"/opt/drop-os/bin/drop-*

# Create runtime directories
mkdir -p "$ROOTFS/var/drop-os/memory"
mkdir -p "$ROOTFS/var/drop-os/audio"
touch "$ROOTFS/var/drop-os/webintel_tasks.txt"
touch "$ROOTFS/var/drop-os/hitl_queue.diff"
ok "DROP OS tree copied"

# -----------------------------------------------------------
# STEP 5: Install Python dependencies
# -----------------------------------------------------------
log "[5/8] Installing Python dependencies..."
chroot "$ROOTFS" /bin/bash -c '
    pip3 install --break-system-packages -r /opt/drop-os/requirements.txt
'
ok "Python deps installed"

# -----------------------------------------------------------
# STEP 6: Install Ollama + pull llama3
# -----------------------------------------------------------
log "[6/8] Installing Ollama and pulling llama3 model..."
chroot "$ROOTFS" /bin/bash -c '
    curl -fsSL https://ollama.com/install.sh | sh
'

# Start ollama temporarily inside chroot to pull model
chroot "$ROOTFS" /bin/bash -c '
    /usr/local/bin/ollama serve &
    OPID=$!
    # Wait for ollama to be ready
    for i in $(seq 1 30); do
        curl -s http://localhost:11434/api/tags >/dev/null 2>&1 && break
        sleep 1
    done
    ollama pull llama3
    kill $OPID 2>/dev/null
    wait $OPID 2>/dev/null || true
'

# Patch init-drop to start ollama on boot
sed -i '/^# Start DROP subsystems in background$/a \
# Start Ollama LLM server\n/usr/local/bin/ollama serve &\nsleep 3' \
    "$ROOTFS/opt/drop-os/bin/init-drop"

ok "Ollama + llama3 ready"

# -----------------------------------------------------------
# STEP 7: Configure GRUB
# -----------------------------------------------------------
log "[7/8] Configuring GRUB..."

KERNEL=$(ls "$ROOTFS"/boot/vmlinuz-* 2>/dev/null | sort -V | tail -1)
INITRD=$(ls "$ROOTFS"/boot/initrd.img-* 2>/dev/null | sort -V | tail -1)

[ -z "$KERNEL" ] && die "No kernel found in rootfs"
[ -z "$INITRD" ] && die "No initrd found in rootfs"

KBASE=$(basename "$KERNEL")
IBASE=$(basename "$INITRD")

mkdir -p "$ISO_DIR/boot/grub"
mkdir -p "$ISO_DIR/live"

cp "$KERNEL" "$ISO_DIR/boot/$KBASE"
cp "$INITRD" "$ISO_DIR/boot/$IBASE"

log "    Creating squashfs (this takes several minutes)..."
mksquashfs "$ROOTFS" "$ISO_DIR/live/filesystem.squashfs" -comp xz -quiet

cat > "$ISO_DIR/boot/grub/grub.cfg" << GRUBEOF
set timeout=3
set default=0

menuentry "DROP OS — AI Core" {
    linux /boot/$KBASE boot=live toram quiet init=/opt/drop-os/bin/init-drop
    initrd /boot/$IBASE
}

menuentry "DROP OS — Recovery (bash)" {
    linux /boot/$KBASE boot=live toram init=/bin/bash
    initrd /boot/$IBASE
}
GRUBEOF

ok "GRUB configured"

# -----------------------------------------------------------
# STEP 8: Build ISO
# -----------------------------------------------------------
log "[8/8] Building ISO image..."
grub-mkrescue -o "$OUTPUT" "$ISO_DIR" 2>/dev/null

ok "ISO built successfully!"
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN} DROP OS ISO: $OUTPUT${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo "Flash to USB:"
echo "  sudo dd if=$OUTPUT of=/dev/sdX bs=4M status=progress"
echo ""
echo "Test in VM:"
echo "  qemu-system-x86_64 -cdrom $OUTPUT -m 4G -enable-kvm"
echo ""
echo "On boot you will see:"
echo "  DROP OS — AI Core"
echo "  you> _"
