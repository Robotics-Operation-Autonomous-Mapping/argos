# Blackfly GigE + Raspberry Pi — Setup from Scratch

**Camera:** Point Grey / FLIR **Blackfly BFLY-PGE-09S2C-CS** (Sony IMX273 color, GigE PoE, C-mount)  
**Host:** Raspberry Pi with **Ubuntu 22.04** (ARM64)  
**Viewer:** Linux laptop on the same Wi‑Fi / network as the Pi  
**Stack:** Aravis + GStreamer (no Spinnaker required for basic streaming)

This guide covers wiring, SSH access, GigE networking, live streaming to a laptop, and enabling **color** output.

---

## Quick launch (laptop + camera on same machine)

Use this when the camera is plugged into your laptop via USB Ethernet (`enx...`, not `eth0`).

**Edit settings in one file, then run it:**

```bash
~/summer_research/scripts/launch_blackfly_preview.sh
```

Open [`scripts/launch_blackfly_preview.sh`](./scripts/launch_blackfly_preview.sh) and edit the **USER CONFIG** block at the top (`ETH`, `CAM`, `BALANCE_BLUE`, `GST_HUE`, etc.). No paste blocks needed.

| Setting | What it does |
|---------|----------------|
| `ETH` | Your USB Ethernet name (`ip -br link`) |
| `BALANCE_BLUE` | Raise (2.0–3.5) if too yellow |
| `GST_HUE` | More negative = cooler / less yellow |
| `LOW_BANDWIDTH=1` | Drop to 640×480 if stream dies after ~2 s |

**The ~2 s crash** is handled automatically via `PACKET_SIZE=1440` in the script — do not remove it.

| Symptom | Fix |
|---------|-----|
| Dies after ~2 s | Re-run `GevSCPSPacketSize=1440` + sysctl lines above; kill stale `gst-launch` |
| `access-denied` | `pkill -9 -f gst-launch`; wait 5 s; power-cycle camera |
| `No device found` | Add `169.254.0.2/16`; same PoE switch as camera; `nmcli radio wifi off` |
| Too yellow | Raise `BalanceRatio` Blue (try 2.0–3.5); add `videobalance hue=-0.06` in pipeline |
| Still dies after ~2 s | Lower bandwidth: `arv-tool-0.8 -n "$CAM" control Width=640` and `Height=480` |

Ignore `arv_camera_uv_set_usb_mode` CRITICAL in GStreamer — harmless on GigE.

**Pi → laptop over Wi‑Fi:** see [§7 Stream to laptop](#7-stream-to-laptop-daily-workflow).

---

## 1. What you are building

```text
PoE switch
   ├── Blackfly camera  (Ethernet + PoE)
   └── Raspberry Pi     (Ethernet to switch, Wi‑Fi to laptop)

Laptop ──SSH / TCP:8554──► Pi ──GigE──► Camera
```

| Layer | Role |
|-------|------|
| **PoE switch** | Powers camera and Pi Ethernet port |
| **Pi `eth0`** | Talks to camera on GigE (often `169.254.x.x`) |
| **Pi `wlan0`** | SSH + MJPEG stream to laptop |
| **Aravis** | Discovers and opens the GigE camera |
| **GStreamer** | Encodes JPEG and sends over TCP to laptop |

---

## 2. Hardware checklist

- [ ] Blackfly **BFLY-PGE-09S2C-CS** on PoE switch
- [ ] Pi Ethernet cable to same switch (not only Wi‑Fi)
- [ ] Pi powered (PoE hat or separate power)
- [ ] Laptop on same network as Pi Wi‑Fi (for SSH and stream)
- [ ] C-mount lens fitted (if not already)

**Note:** The **C** in `09S2C` is the **color** model. Grey video usually means `PixelFormat=Mono8`, not a missing color sensor.

---

## 3. SSH into the Pi (one-time)

### 3.1 On the Pi (keyboard + monitor, or first boot)

```bash
sudo apt update
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
hostname -I    # note Wi‑Fi IP, e.g. 10.13.68.39
whoami         # default user is often ubuntu
```

### 3.2 On the laptop — SSH key

```bash
ssh-keygen -t ed25519 -C "laptop-to-pi"
cat ~/.ssh/id_ed25519.pub
```

Paste the public key into `~/.ssh/authorized_keys` on the Pi.

### 3.3 Connect

```bash
ssh ubuntu@<PI_WIFI_IP>
```

First time: type `yes` for host key fingerprint.

### 3.4 Optional SSH shortcut (`~/.ssh/config` on laptop)

```
Host pi
    HostName 10.13.68.39
    User ubuntu
```

Then: `ssh pi`

---

## 4. Fix DNS on the Pi (if `apt` fails)

If you see `Temporary failure resolving 'ports.ubuntu.com'`:

```bash
ping -c 2 8.8.8.8
ping -c 2 google.com
```

**DNS only broken:**

```bash
sudo rm -f /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf
```

**No default route** (ping to `8.8.8.8` fails):

```bash
ip route
sudo ip route add default via <HOTSPOT_GATEWAY> dev wlan0   # often .1 on same subnet
```

**Silence `sudo: unable to resolve host ubuntu`:**

```bash
echo "127.0.1.1 ubuntu" | sudo tee -a /etc/hosts
```

---

## 5. Install software on the Pi

```bash
sudo apt update
sudo apt install -y \
  aravis-tools \
  arv-viewer \
  gstreamer1.0-tools \
  gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-bad \
  ethtool
```

On the **laptop** (viewer):

```bash
sudo apt install -y \
  gstreamer1.0-tools \
  gstreamer1.0-plugins-good \
  gstreamer1.0-plugins-bad
```

---

## 6. GigE network — camera discovery

### 6.1 Check Ethernet link

```bash
ip -br link
ip -br addr
sudo ethtool eth0 | grep -E "Link detected|Speed"
```

`eth0` must be **UP** with **Link detected: yes**.

### 6.2 Link-local addressing

Unconfigured Blackfly cameras often appear at **`169.254.x.x`**. Put the Pi on the same subnet:

```bash
sudo ip link set eth0 up
sudo ip addr add 169.254.0.2/16 dev eth0
# optional fixed subnet if you use 192.168.0.x later:
# sudo ip addr add 192.168.0.1/24 dev eth0
```

### 6.3 Discover camera

```bash
arv-tool-0.8 list
```

Example output:

```text
Point Grey Research-Blackfly BFLY-PGE-09S2C-13125051 (169.254.0.1)
```

Save the **full camera name** and **IP**. Test reachability:

```bash
ping -c 3 169.254.0.1
```

### 6.4 GigE packet size (required on Pi Ethernet)

Pi uses MTU 1500. Set a safe packet size:

```bash
CAM="Point Grey Research-Blackfly BFLY-PGE-09S2C-13125051"

arv-tool-0.8 -n "$CAM" control GevSCPSPacketSize=1440
arv-tool-0.8 -n "$CAM" control TriggerMode=Off
arv-tool-0.8 -n "$CAM" control AcquisitionMode=Continuous
```

Increase receive buffers:

```bash
sudo sysctl -w net.core.rmem_max=26214400
sudo sysctl -w net.core.rmem_default=26214400
```

---

## 7. Stream to laptop (daily workflow)

### 7.1 Free port 8554 (run if a previous stream crashed)

On the **Pi**:

```bash
pkill -9 -f gst-launch
sudo fuser -k 8554/tcp
sleep 2
sudo ss -tlnp | grep 8554    # should print nothing
```

### 7.2 Start stream on the Pi

**Grayscale (Mono8):**

```bash
CAM="Point Grey Research-Blackfly BFLY-PGE-09S2C-13125051"

gst-launch-1.0 aravissrc \
  camera-name="$CAM" \
  packet-size=1400 auto-packet-size=false \
  ! videoconvert ! video/x-raw,format=I420 ! jpegenc ! multipartmux \
  ! tcpserversink host=0.0.0.0 port=8554
```

**Color (recommended for 09S2C):**

```bash
arv-tool-0.8 -n "$CAM" control PixelFormat=BayerRG8

gst-launch-1.0 aravissrc \
  camera-name="$CAM" \
  packet-size=1400 auto-packet-size=false \
  ! bayer2rgb ! videoconvert ! video/x-raw,format=I420 ! jpegenc ! multipartmux \
  ! tcpserversink host=0.0.0.0 port=8554
```

Wait for **`Setting pipeline to PLAYING`**. Leave this terminal open.

**Lower bandwidth over Wi‑Fi (optional):**

```bash
arv-tool-0.8 -n "$CAM" control Width=640
arv-tool-0.8 -n "$CAM" control Height=480
arv-tool-0.8 -n "$CAM" control AcquisitionFrameRate=10
```

### 7.3 View on the laptop

Replace `<PI_WIFI_IP>` with the Pi address from `hostname -I` on the Pi (the `wlan0` IP, not `169.254.x.x`).

```bash
PI_IP=10.13.68.39

nc -zv $PI_IP 8554

gst-launch-1.0 tcpclientsrc host=$PI_IP port=8554 blocksize=65536 ! \
  multipartdemux ! jpegdec ! autovideosink sync=false
```

Stop with **Ctrl+C** on both Pi and laptop.

### 7.4 Verify network path (without camera)

On the **Pi**:

```bash
gst-launch-1.0 videotestsrc ! videoconvert ! jpegenc ! multipartmux \
  ! tcpserversink host=0.0.0.0 port=8554
```

Use the same laptop `tcpclientsrc` command. A test pattern confirms Wi‑Fi streaming works; then switch back to `aravissrc`.

---

## 8. Color vs grayscale

| Symptom | Cause | Fix |
|---------|--------|-----|
| Grey image | `PixelFormat=Mono8` | Set `PixelFormat=BayerRG8` (or `RGB8` if listed) |
| Pipeline fails after Bayer change | Missing plugin | `sudo apt install gstreamer1.0-plugins-bad` |
| Still grey | Wrong Bayer pattern | Try `BayerGB8`, `BayerGR8`, `BayerBG8` |

List allowed formats:

```bash
arv-tool-0.8 -n "$CAM" control PixelFormat=?
```

Color pipeline must include **`bayer2rgb`** when using a Bayer format.

---

## 9. SSH tunnel (if direct TCP to port 8554 fails)

**Terminal 1 — laptop:**

```bash
ssh -L 8554:127.0.0.1:8554 ubuntu@<PI_WIFI_IP>
```

**In that SSH session — Pi:**

```bash
gst-launch-1.0 aravissrc camera-name="$CAM" packet-size=1400 auto-packet-size=false \
  ! bayer2rgb ! videoconvert ! video/x-raw,format=I420 ! jpegenc ! multipartmux \
  ! tcpserversink host=127.0.0.1 port=8554
```

**Terminal 2 — laptop:**

```bash
gst-launch-1.0 tcpclientsrc host=127.0.0.1 port=8554 blocksize=65536 ! \
  multipartdemux ! jpegdec ! autovideosink sync=false
```

---

## 10. Troubleshooting

| Problem | Fix |
|---------|-----|
| `arv-tool-0.8 list` → No device | Check `eth0` link; add `169.254.0.2/16`; same PoE switch as camera |
| `Permission denied (publickey)` | Add laptop SSH public key to Pi `~/.ssh/authorized_keys` |
| `Address already in use` (8554) | `pkill -9 -f gst-launch` then `sudo fuser -k 8554/tcp` |
| `access-denied` on camera | Kill all `gst-launch`; wait 5 s; power-cycle camera |
| `Internal data stream error` (~2 s) | Set `GevSCPSPacketSize=1440`; lower resolution / frame rate |
| `arv_camera_uv_set_usb_mode` CRITICAL | Harmless on GigE — ignore |
| Laptop stuck at `PREROLLING` | Pi pipeline not running; use `sync=false`; try 640×480 @ 10 fps |
| `not-negotiated` on laptop | Pi stream died — check Pi terminal; restart Pi pipeline first |
| `camera-address` property error | Use `camera-name="..."` (full string from `arv-tool-0.8 list`) |
| Pi IP changed | `ssh ubuntu@<pi> "hostname -I"` — use `wlan0` IP for laptop viewer |

### Useful diagnostics

```bash
# Pi — port listening?
sudo ss -tlnp | grep 8554

# Pi — client connected?
ss -tnp | grep 8554

# Pi — traffic on 8554 while viewer runs
sudo tcpdump -i any port 8554 -c 5
```

---

## 11. Quick reference

**Laptop-only:** use [Quick launch](#quick-launch-laptop--camera-on-same-machine) at the top.

**Pi streams to laptop:**

```bash
# --- Variables (edit once per session) ---
CAM="Point Grey Research-Blackfly BFLY-PGE-09S2C-13125051"
PI_IP=10.13.68.39

# --- Pi: discover ---
arv-tool-0.8 list

# --- Pi: color + stream (GevSCPSPacketSize fixes ~2 s crash) ---
pkill -9 -f gst-launch; sudo fuser -k 8554/tcp; sleep 2
sudo sysctl -w net.core.rmem_max=26214400
sudo sysctl -w net.core.rmem_default=26214400
arv-tool-0.8 -n "$CAM" control GevSCPSPacketSize=1440
arv-tool-0.8 -n "$CAM" control PixelFormat=BayerRG8
arv-tool-0.8 -n "$CAM" control BalanceWhiteAuto=Once

gst-launch-1.0 aravissrc camera-name="$CAM" packet-size=1400 auto-packet-size=false \
  ! bayer2rgb ! videoconvert ! video/x-raw,format=I420 ! jpegenc ! multipartmux \
  ! tcpserversink host=0.0.0.0 port=8554

# --- Laptop: view ---
gst-launch-1.0 tcpclientsrc host=$PI_IP port=8554 blocksize=65536 ! \
  multipartdemux ! jpegdec ! autovideosink sync=false
```

---

## 12. Optional next steps

| Goal | Tool |
|------|------|
| Official SDK, firmware, persistent IP | [Spinnaker SDK](https://www.teledynevisionsolutions.com/products/spinnaker-sdk/) (ARM64 build for Pi) |
| Record video on Pi | Add `! filesink location=capture.mp4` or record rosbag with `usb_cam` / custom node |
| Stable camera IP | Configure persistent IP in SpinView (Windows) or Spinnaker IP Config |
| ROS integration | `gscam` or FLIR Spinnaker ROS driver (separate from this minimal stack) |

---

## Related docs in this repo

- [LINUX_INSTALL_GUIDE.md](./LINUX_INSTALL_GUIDE.md) — Triton2 EVS event camera stack (different hardware)
- [VEHICLE_DATA_COLLECTION.md](./VEHICLE_DATA_COLLECTION.md) — In-vehicle logging playbook for Triton2
