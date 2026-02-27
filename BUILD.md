# Fiber Kiosk Image — Armbian Build Guide
# =========================================
# Builds a ready-to-flash Armbian image for OPi 3B with:
#   - Armbian current 6.12, Bookworm minimal
#   - All kernel/sysctl tuning baked in
#   - DSI overlay (Waveshare 5" / RPi 7" clone) active
#   - fnn (Fiber Network Node) v0.7.0 pre-installed
#   - fiber-bridge Node.js service
#   - fiber-kiosk LVGL touchscreen app
#   - First-boot wizard (PIN setup, key generation, NVMe detection)
#
# Prerequisites (build machine — needs x86_64 Linux, 20GB+ free):
#   sudo apt install git curl
#   git clone https://github.com/armbian/build
#
# Usage:
#   cp -r userpatches/ build/userpatches/
#   cd build
#   ./compile.sh \
#       BOARD=orangepi3b \
#       BRANCH=current \
#       RELEASE=bookworm \
#       BUILD_DESKTOP=no \
#       BUILD_MINIMAL=yes \
#       KERNEL_CONFIGURE=no \
#       COMPRESS_OUTPUTIMAGE=sha,img
#
# Output: output/images/Armbian_*_Orangepi3b_bookworm_current_*.img
# Flash:  xz -dc image.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
#
# First boot:
#   1. Insert SD (or eMMC via adapter)
#   2. Connect display + USB keyboard (or SSH in)
#   3. First-boot wizard runs automatically
#   4. Generates fresh keys, sets PIN, starts Fiber node
#   5. Kiosk UI starts on DSI display
#
# eMMC note:
#   OS + binaries on eMMC is fine.
#   Fiber RocksDB (channel state) should go on NVMe for longevity.
#   First-boot wizard auto-detects NVMe and offers to use it for DB.
#   Without NVMe: DB stays on eMMC (fine for testing/light use).
