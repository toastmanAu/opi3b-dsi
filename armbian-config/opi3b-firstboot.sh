#!/bin/bash
# opi3b-firstboot.sh
# Run this on first boot of OPi 3B (Armbian current 6.12)
# Does everything: sysctl tuning, CPU governor, DSI overlay, node deps
#
# Usage:
#   scp opi3b-firstboot.sh opi3b-armbian:~/
#   ssh opi3b-armbian 'sudo bash ~/opi3b-firstboot.sh'

set -e
echo "=== OPi 3B first-boot setup ==="

# ── 1. sysctl tuning ──────────────────────────────────────────────
echo "[1/6] Writing sysctl config..."
cat > /etc/sysctl.d/99-opi3b-kiosk.conf << 'SYSCTL'
# Network — Fiber node tuning
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_fastopen = 3
net.core.netdev_max_backlog = 5000

# Memory — 2GB RAM + RocksDB
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.overcommit_memory = 1
vm.nr_hugepages = 64

# CPU scheduler
kernel.sched_migration_cost_ns = 5000000
kernel.sched_autogroup_enabled = 1
SYSCTL
sysctl -p /etc/sysctl.d/99-opi3b-kiosk.conf

# ── 2. CPU governor ───────────────────────────────────────────────
echo "[2/6] Setting CPU governor to schedutil..."
cat > /etc/udev/rules.d/99-cpu-governor.rules << 'UDEV'
SUBSYSTEM=="cpu", ACTION=="add", ATTR{cpufreq/scaling_governor}="schedutil"
UDEV
# Apply now without waiting for reboot
for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo schedutil > "$cpu" 2>/dev/null || true
done

# ── 3. zswap (compressed RAM-backed swap) ─────────────────────────
echo "[3/6] Enabling zswap..."
cat > /etc/modprobe.d/zswap.conf << 'ZSWAP'
options zswap enabled=1 compressor=lz4 zpool=z3fold max_pool_percent=20
ZSWAP
# Enable now
echo 1 > /sys/module/zswap/parameters/enabled 2>/dev/null || true
modprobe lz4 2>/dev/null || true
modprobe z3fold 2>/dev/null || true

# ── 4. armbianEnv.txt additions ───────────────────────────────────
echo "[4/6] Patching /boot/armbianEnv.txt..."
ENVFILE=/boot/armbianEnv.txt

# CMA for panfrost/display
grep -q "cma=" "$ENVFILE" || echo "extraargs=cma=256M" >> "$ENVFILE"

# Verify overlay dir exists
mkdir -p /boot/overlay-user

# ── 5. DSI overlay ────────────────────────────────────────────────
echo "[5/6] Installing DSI overlay..."
OVERLAY_SRC="$(dirname "$0")/opi3b-waveshare5-dsi-mainline.dts"
OVERLAY_DST=/boot/overlay-user/opi3b-waveshare5-dsi-mainline.dtbo

if [ -f "$OVERLAY_SRC" ]; then
    dtc -I dts -O dtb -o "$OVERLAY_DST" "$OVERLAY_SRC"
    # Add to armbianEnv.txt if not already there
    grep -q "opi3b-waveshare5-dsi-mainline" "$ENVFILE" || \
        echo "user_overlays=opi3b-waveshare5-dsi-mainline" >> "$ENVFILE"
    echo "    DSI overlay installed. Will activate on reboot."
else
    echo "    SKIP: overlay .dts not found alongside this script"
    echo "    Copy opi3b-waveshare5-dsi-mainline.dts next to this script and re-run [5/6]"
fi

# ── 6. Install deps ───────────────────────────────────────────────
echo "[6/6] Installing packages..."
apt-get update -qq
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

# ── Done ──────────────────────────────────────────────────────────
echo ""
echo "=== Done. Summary ==="
echo "  sysctl:    /etc/sysctl.d/99-opi3b-kiosk.conf"
echo "  governor:  schedutil (all cores)"
echo "  zswap:     lz4 + z3fold, 20% max"
echo "  CMA:       256MB (armbianEnv.txt)"
echo ""
echo "Next steps:"
echo "  1. reboot"
echo "  2. check DSI: dmesg | grep -i 'dsi\|panel\|raspberrypi'"
echo "  3. check GPU: dmesg | grep -i panfrost"
echo "  4. if display works: run fiber-kiosk setup"
echo ""
echo "Reboot now? (y/N)"
read -r ans
[ "$ans" = "y" ] && reboot
