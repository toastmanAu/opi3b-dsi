# Armbian customisation script for OPi 3B
# Place this at: userpatches/customize-image.sh in Armbian build tree
#
# This runs INSIDE the image chroot during build — bakes everything in.
# Use if building Armbian from source instead of flashing pre-built image.
#
# Armbian build docs: https://docs.armbian.com/Developer-Guide_Build-Preparation/
#
# Usage:
#   git clone https://github.com/armbian/build armbian-build
#   mkdir -p armbian-build/userpatches
#   cp customize-image.sh armbian-build/userpatches/
#   cp opi3b-waveshare5-dsi-mainline.dts armbian-build/userpatches/overlay/
#   cd armbian-build
#   ./compile.sh BOARD=orangepi3b BRANCH=current RELEASE=bookworm \
#       BUILD_DESKTOP=no BUILD_MINIMAL=yes KERNEL_CONFIGURE=no

# Called with: customize-image.sh <RELEASE> <LINUXFAMILY> <BOARD> <BUILD_DESKTOP>
RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4

# Only apply to OPi 3B
[ "$BOARD" = "orangepi3b" ] || exit 0

echo ">>> OPi 3B customisation starting..."

# ── sysctl ────────────────────────────────────────────────────────
cat > /etc/sysctl.d/99-opi3b-kiosk.conf << 'SYSCTL'
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_fastopen = 3
net.core.netdev_max_backlog = 5000
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.overcommit_memory = 1
vm.nr_hugepages = 64
kernel.sched_migration_cost_ns = 5000000
kernel.sched_autogroup_enabled = 1
SYSCTL

# ── CPU governor ──────────────────────────────────────────────────
cat > /etc/udev/rules.d/99-cpu-governor.rules << 'UDEV'
SUBSYSTEM=="cpu", ACTION=="add", ATTR{cpufreq/scaling_governor}="schedutil"
UDEV

# ── zswap ─────────────────────────────────────────────────────────
cat > /etc/modprobe.d/zswap.conf << 'ZSWAP'
options zswap enabled=1 compressor=lz4 zpool=z3fold max_pool_percent=20
ZSWAP

# ── armbianEnv.txt: CMA + overlay ─────────────────────────────────
ENVFILE=/boot/armbianEnv.txt
grep -q "cma=" "$ENVFILE" 2>/dev/null || echo "extraargs=cma=256M" >> "$ENVFILE"

# ── DSI overlay ───────────────────────────────────────────────────
OVERLAY_SRC="/tmp/overlay/opi3b-waveshare5-dsi-mainline.dts"
if [ -f "$OVERLAY_SRC" ]; then
    mkdir -p /boot/overlay-user
    dtc -I dts -O dtb \
        -o /boot/overlay-user/opi3b-waveshare5-dsi-mainline.dtbo \
        "$OVERLAY_SRC"
    grep -q "opi3b-waveshare5" "$ENVFILE" 2>/dev/null || \
        echo "user_overlays=opi3b-waveshare5-dsi-mainline" >> "$ENVFILE"
fi

# ── Packages baked into image ─────────────────────────────────────
apt-get install -y --no-install-recommends \
    build-essential \
    libevdev-dev \
    libcurl4-openssl-dev \
    nodejs \
    npm \
    git \
    device-tree-compiler \
    evtest \
    htop \
    nvme-cli

echo ">>> OPi 3B customisation done."
