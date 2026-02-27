# OPi 3B DSI — Waveshare 5" Panel

## What OrangePi's BSP does (5.10 kernel)

From `linux-orangepi/orange-pi-5.10-rk35xx`:

- Base DTS has panel + touch nodes **disabled** by default
- Overlay `rk356x-raspi-7inch-touchscreen.dts` enables:
  - `&dsi1` → status okay
  - `&i2c1` → status okay
  - `&raspits_panel` → status okay (compatible = "raspberrypi,7inch-touchscreen-panel", reg 0x45)
  - `&raspits_touch_ft5426` → status okay (compatible = "raspits_ft5426", reg 0x38)
  - `&video_phy1` → status okay
  - `&dsi1_in_vp0` → status okay
  - `&hdmi` → disabled

**Key facts confirmed:**
- Panel driver: `raspberrypi,7inch-touchscreen-panel` — this IS what OrangePi uses
- Touch: ft5426 @ i2c1/0x38 — standard FocalTech cap touch
- DSI port: DSI1 (fe070000), NOT DSI0
- VOP routing: BSP uses vp0→DSI1; mainline should use vp1→DSI1 (vp0 is HDMI)
- Panel i2c address 0x45 — this is the RPi panel bridge chip (Atmel ATTINY88)

## Mainline Differences (kernel 6.11+)

| BSP (5.10) | Mainline (6.11+) |
|-----------|-----------------|
| `video_phy1` | `dsi_dphy1` |
| `dsi1_in_vp0` | `vp1` with `ROCKCHIP_VOP2_EP_MIPI1` |
| `compatible = "raspits_ft5426"` | `compatible = "focaltech,ft5426"` |
| BSP VOP driver | Mainline VOP2 driver |

## Why GPU didn't work on OrangePi's image

OrangePi's BSP uses the Rockchip vendor GPU driver (closed-source binary blob for Mali G52).
It's not mainlined and OrangePi couldn't integrate it properly.

On Armbian mainline kernel: **panfrost** driver handles Mali G52 — open source, works fine.
This is the whole point of using Armbian current/edge instead of OrangePi's image.

## The Plan

1. Boot OPi 3B with **Armbian current (6.12)** or **edge (6.19)**
2. Compile + load `opi3b-waveshare5-dsi-mainline.dts` overlay
3. Test: does panel light up?
   - If yes → working display, Mali GPU via panfrost = full kiosk stack
   - If no → check dmesg for panel driver errors, may need panel init tweak

## Files

- `opi3b-waveshare5-dsi-mainline.dts` — mainline overlay (write this to OPi 3B)
- `rk356x-raspi-7inch-touchscreen.dts` — OrangePi BSP overlay (reference only)

## Deploy to OPi 3B

```bash
scp opi3b-waveshare5-dsi-mainline.dts opi3b-armbian:~/

# On OPi 3B:
dtc -I dts -O dtb \
    -o /boot/overlay-user/opi3b-waveshare5-dsi-mainline.dtbo \
    ~/opi3b-waveshare5-dsi-mainline.dts

# Add to /boot/armbianEnv.txt:
echo "user_overlays=opi3b-waveshare5-dsi-mainline" | sudo tee -a /boot/armbianEnv.txt

sudo reboot
```

## Check After Reboot

```bash
# Did panel get recognised?
dmesg | grep -i "dsi\|raspberrypi\|panel\|mipi\|ft5"

# Is display connected?
modetest -c | grep -A5 "DSI"

# Is touch working?
evtest /dev/input/event*
```

## Unknown: INT GPIO for Touch

The ft5426 interrupt GPIO pin on the DSI connector is unknown — not in any public schematic.
Options:
1. Leave interrupt disabled → driver polls (works, slightly higher CPU)
2. Check OPi 3B v2.1 schematic PDF if published
3. Probe with oscilloscope on DSI connector pin

