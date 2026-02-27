#!/bin/bash
# userpatches/customize-image.sh
# Runs inside Armbian image chroot during build.
# Installs and configures everything for the Fiber Kiosk image.

set -e

RELEASE=$1
LINUXFAMILY=$2
BOARD=$3
BUILD_DESKTOP=$4

[ "$BOARD" = "orangepi3b" ] || exit 0

FNN_VERSION="v0.7.0"
FNN_URL="https://github.com/nervosnetwork/fiber/releases/download/${FNN_VERSION}/fnn-${FNN_VERSION}-aarch64-linux-gnu.tar.gz"

echo ">>> [fiber-kiosk-image] Starting customisation for $BOARD $RELEASE"

# ── Kernel boot args ──────────────────────────────────────────────
ENVFILE=/boot/armbianEnv.txt
grep -q "cma=256M" "$ENVFILE" 2>/dev/null || \
    sed -i '/^extraargs/d' "$ENVFILE"; echo "extraargs=cma=256M" >> "$ENVFILE"

# ── DSI overlay ───────────────────────────────────────────────────
mkdir -p /boot/overlay-user
if [ -f /tmp/overlay/opi3b-waveshare5-dsi-mainline.dts ]; then
    dtc -I dts -O dtb \
        -o /boot/overlay-user/opi3b-waveshare5-dsi-mainline.dtbo \
        /tmp/overlay/opi3b-waveshare5-dsi-mainline.dts
    grep -q "opi3b-waveshare5" "$ENVFILE" 2>/dev/null || \
        echo "user_overlays=opi3b-waveshare5-dsi-mainline" >> "$ENVFILE"
fi

# ── sysctl ────────────────────────────────────────────────────────
cat > /etc/sysctl.d/99-fiber-kiosk.conf << 'SYSCTL'
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

# ── System packages ───────────────────────────────────────────────
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
    nvme-cli \
    python3 \
    python3-pip \
    curl \
    jq \
    whiptail

# ── biscuit-python (for key generation on first boot) ─────────────
pip3 install --break-system-packages biscuit-python

# ── fnn binary ────────────────────────────────────────────────────
echo ">>> Installing fnn ${FNN_VERSION}..."
mkdir -p /opt/fiber
cd /tmp

# Try to download pre-built aarch64 binary
if curl -fsSL "$FNN_URL" -o fnn.tar.gz 2>/dev/null; then
    tar xzf fnn.tar.gz -C /opt/fiber/
    chmod +x /opt/fiber/fnn
    echo ">>> fnn installed from release binary"
else
    # No aarch64 binary available — mark for source build on first boot
    echo "NEEDS_FNN_BUILD=1" > /opt/fiber/.build-needed
    echo ">>> fnn aarch64 binary not available — will build from source on first boot"
fi

# Create fiber run directory structure
mkdir -p /opt/fiber/{run,config,data}

# ── fiber-bridge (Node.js) ────────────────────────────────────────
echo ">>> Installing fiber-bridge..."
mkdir -p /opt/fiber-bridge
cd /opt/fiber-bridge

# Copy fiber-htlc.js and bridge server from our repo
# (these are placed in userpatches/rootfs-overlay/ during build)
if [ -d /tmp/fiber-bridge ]; then
    cp -r /tmp/fiber-bridge/* /opt/fiber-bridge/
    npm install --production
fi

# ── fiber-kiosk binary ────────────────────────────────────────────
echo ">>> Installing fiber-kiosk..."
mkdir -p /opt/fiber-kiosk
if [ -f /tmp/fiber-kiosk/fiber-kiosk ]; then
    cp /tmp/fiber-kiosk/fiber-kiosk /usr/local/bin/
    chmod +x /usr/local/bin/fiber-kiosk
else
    echo "NEEDS_KIOSK_BUILD=1" > /opt/fiber-kiosk/.build-needed
    echo ">>> fiber-kiosk binary not pre-built — will compile on first boot"
fi

# ── Default config files ──────────────────────────────────────────
cat > /etc/fiber-kiosk.conf << 'CONF'
bridge_url      = http://127.0.0.1:7777
signer_port     = /dev/ttyACM0
fb_device       = /dev/fb0
touch_device    = /dev/input/event0
display_w       = 800
display_h       = 480
poll_ms         = 3000
pin_timeout_sec = 300
CONF

cat > /opt/fiber/config/config.yml << 'FIBERCONF'
fiber:
  listening_addr: "/ip4/0.0.0.0/tcp/8228"

ckb:
  rpc_url: "http://127.0.0.1:8114/"

rpc:
  listening_addr: "127.0.0.1:8227"
  # biscuit_public_key set by first-boot wizard

store:
  path: "/opt/fiber/data/store"
FIBERCONF

# ── Systemd services ──────────────────────────────────────────────
# (copied from rootfs-overlay during build, but also write defaults here)

cat > /etc/systemd/system/fiber-node.service << 'SVC'
[Unit]
Description=Fiber Network Node
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=fiber
Group=fiber
WorkingDirectory=/opt/fiber
EnvironmentFile=/etc/fiber-node.env
ExecStartPre=/bin/bash -c 'pkill -9 fnn || true; rm -f /opt/fiber/data/store/LOCK'
ExecStart=/opt/fiber/fnn --dir /opt/fiber/run --config /opt/fiber/config/config.yml
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVC

cat > /etc/systemd/system/fiber-bridge.service << 'SVC'
[Unit]
Description=Fiber Bridge API
After=fiber-node.service
Requires=fiber-node.service

[Service]
Type=simple
User=fiber
WorkingDirectory=/opt/fiber-bridge
EnvironmentFile=/etc/fiber-node.env
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SVC

cat > /etc/systemd/system/fiber-kiosk.service << 'SVC'
[Unit]
Description=Fiber Kiosk UI
After=fiber-bridge.service
Wants=fiber-bridge.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/fiber-kiosk --fb /dev/fb0 --touch /dev/input/event0
Restart=always
RestartSec=3
Environment=DISPLAY=

[Install]
WantedBy=multi-user.target
SVC

cat > /etc/systemd/system/fiber-firstboot.service << 'SVC'
[Unit]
Description=Fiber Kiosk First Boot Wizard
ConditionPathExists=!/etc/fiber-node.env
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/fiber-firstboot.sh
RemainAfterExit=yes
StandardInput=tty
TTYPath=/dev/tty1
StandardOutput=tty
StandardError=tty

[Install]
WantedBy=multi-user.target
SVC

# Enable services
systemctl enable fiber-firstboot
systemctl enable fiber-node
systemctl enable fiber-bridge
systemctl enable fiber-kiosk
# node/bridge/kiosk won't actually start until firstboot creates /etc/fiber-node.env

# ── fiber user ────────────────────────────────────────────────────
useradd -r -s /bin/false -d /opt/fiber fiber 2>/dev/null || true
chown -R fiber:fiber /opt/fiber /opt/fiber-bridge

# ── First-boot wizard script ──────────────────────────────────────
cp /tmp/fiber-firstboot.sh /usr/local/bin/fiber-firstboot.sh 2>/dev/null || \
cat > /usr/local/bin/fiber-firstboot.sh << 'WIZARD'
#!/bin/bash
# Written inline — see userpatches/rootfs-overlay for the full version
echo "Fiber Kiosk first boot wizard not found."
echo "Download from: https://github.com/toastmanAu/opi3b-dsi"
WIZARD
chmod +x /usr/local/bin/fiber-firstboot.sh

echo ">>> [fiber-kiosk-image] Customisation complete"
