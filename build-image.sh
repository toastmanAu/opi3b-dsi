#!/bin/bash
# build-image.sh
# Builds the complete Fiber Kiosk image for OPi 3B.
# Run on an x86_64 Linux machine with Docker or native.
#
# Requirements:
#   - x86_64 Linux (Ubuntu 22.04 recommended)
#   - 20GB+ free disk space
#   - Internet access
#   - sudo access

set -e

ARMBIAN_DIR="${1:-./armbian-build}"
REPO_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Fiber Kiosk Image Builder ==="
echo "Armbian build dir: $ARMBIAN_DIR"
echo "Repo dir: $REPO_DIR"
echo ""

# ── Clone Armbian build system ─────────────────────────────────────
if [ ! -d "$ARMBIAN_DIR" ]; then
    echo "► Cloning Armbian build system..."
    git clone --depth 1 https://github.com/armbian/build "$ARMBIAN_DIR"
fi

# ── Copy userpatches ───────────────────────────────────────────────
echo "► Copying userpatches..."
mkdir -p "$ARMBIAN_DIR/userpatches/overlay"
mkdir -p "$ARMBIAN_DIR/userpatches/rootfs-overlay/usr/local/bin"
mkdir -p "$ARMBIAN_DIR/userpatches/rootfs-overlay/opt/fiber-bridge"

cp "$REPO_DIR/userpatches/customize-image.sh" \
    "$ARMBIAN_DIR/userpatches/"

cp "$REPO_DIR/opi3b-waveshare5-dsi-mainline.dts" \
    "$ARMBIAN_DIR/userpatches/overlay/"

cp "$REPO_DIR/userpatches/rootfs-overlay/usr/local/bin/fiber-firstboot.sh" \
    "$ARMBIAN_DIR/userpatches/rootfs-overlay/usr/local/bin/"

chmod +x "$ARMBIAN_DIR/userpatches/customize-image.sh"
chmod +x "$ARMBIAN_DIR/userpatches/rootfs-overlay/usr/local/bin/fiber-firstboot.sh"

# Copy fiber-bridge files if built locally
if [ -d "$REPO_DIR/../fiber-kiosk/fiber-bridge" ]; then
    cp -r "$REPO_DIR/../fiber-kiosk/fiber-bridge/"* \
        "$ARMBIAN_DIR/userpatches/rootfs-overlay/opt/fiber-bridge/"
    echo "► fiber-bridge included"
fi

# Copy pre-built fiber-kiosk binary if available
if [ -f "$REPO_DIR/../fiber-kiosk/fiber-kiosk" ]; then
    mkdir -p "$ARMBIAN_DIR/userpatches/rootfs-overlay/usr/local/bin"
    cp "$REPO_DIR/../fiber-kiosk/fiber-kiosk" \
        "$ARMBIAN_DIR/userpatches/rootfs-overlay/usr/local/bin/"
    echo "► fiber-kiosk binary included"
else
    echo "► fiber-kiosk binary not found — will compile on first boot"
fi

# ── Build ──────────────────────────────────────────────────────────
echo ""
echo "► Starting Armbian build (this takes 30-60 minutes)..."
echo ""

cd "$ARMBIAN_DIR"
./compile.sh \
    BOARD=orangepi3b \
    BRANCH=current \
    RELEASE=bookworm \
    BUILD_DESKTOP=no \
    BUILD_MINIMAL=yes \
    KERNEL_CONFIGURE=no \
    COMPRESS_OUTPUTIMAGE=sha,img \
    "$@"

echo ""
echo "=== Build complete ==="
echo "Image: $ARMBIAN_DIR/output/images/"
ls "$ARMBIAN_DIR/output/images/"*.img* 2>/dev/null || true
echo ""
echo "Flash with:"
echo "  xz -dc <image.img.xz> | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync"
