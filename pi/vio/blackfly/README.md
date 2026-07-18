# Blackfly GigE access (Pi B / laptop)

Scripts copied from `~/used for ROAM/scripts/` for the FLIR **BFLY-PGE-09S2C** (color) and **BFLY-PGE-09S2M** (mono).  
**ROS distro: ROS 2 Humble.** Day-to-day path does **not** require Spinnaker or Arena.

| Stack | Role | Keep in repo? |
|-------|------|----------------|
| **`camera_aravis2`** (`ros2 launch`) | **Proper ROS 2 driver for OpenVINS on the Pi** (`blackfly_vio.launch.py`) | Yes (launch + camera_info) |
| **Aravis + GStreamer** (these scripts) | Preview + `sensor_msgs/Image` + rosbag2 (recording) | Yes |
| **Spinnaker SDK** + `spinnaker_camera_driver` | FLIR ROS 2 driver — **laptop** option | Launch wrappers only (`spinnaker/`); SDK external |
| **Arena SDK** / `arena_camera_ros2` | Lucid Triton / event cams — **not** Blackfly | Stay external (GB-scale binaries) |

> **For live VIO the recommended path is `ros2 launch ./blackfly_vio.launch.py`** (see
> [Proper ROS 2 way](#proper-ros-2-way-ros2-launch-for-openvins-recommended-on-the-pi)).
> The `*.sh` Aravis scripts remain for quick preview and rosbag recording.

---

## Proper ROS 2 way: `ros2 launch` for OpenVINS (recommended on the Pi)

Runs the Blackfly through a real ROS 2 driver (**`camera_aravis2`**, not the raw
`aravis_ros2_publisher.py` script), publishing straight to the topics OpenVINS expects
(`/blackfly/image_raw` + `/blackfly/camera_info`) at **10 Hz**. No recording.

**Why `camera_aravis2` on the Pi (arm64):** open-source, lightweight, apt/source
installable on arm64 Humble, built on the same **Aravis** backend already proven with
these BFLY-PGE GigE cameras, and it exposes exposure/gain as **dynamic parameters** for
`rqt_reconfigure`. Spinnaker stays the laptop-only option (already built in
`flir_ros2_ws`; heavy proprietary SDK is a poor fit for a 32 GB arm64 Pi) — see
[`spinnaker/README.md`](./spinnaker/README.md).

### 0. Install prerequisites (once)

```bash
# ROS 2 driver + rqt tools (arm64 Humble). Try binaries first:
sudo apt update
sudo apt install ros-humble-camera-aravis2 \
                 ros-humble-rqt-image-view ros-humble-rqt-reconfigure ros-humble-rqt-gui

# If ros-humble-camera-aravis2 has no arm64 binary, build from source:
#   sudo apt install libaravis-0.8-dev
#   mkdir -p ~/aravis_ws/src && cd ~/aravis_ws/src
#   git clone https://github.com/FraunhoferIOSB/camera_aravis2.git
#   cd ~/aravis_ws && rosdep install --from-paths src -y --ignore-src
#   colcon build && source install/setup.bash
```

### 1. Launch the driver (cam0 color, 10 Hz)

```bash
source /opt/ros/humble/setup.bash
# (if built from source) source ~/aravis_ws/install/setup.bash

cd "$(dirname "$0")"   # this directory (argos/pi/vio/blackfly)

# List cameras / confirm the serial is seen:
ros2 run camera_aravis2 camera_finder

# cam0 (color, serial 13125051) -> /blackfly/image_raw @ 10 Hz
ros2 launch ./blackfly_vio.launch.py

# cam1 (mono, serial 13294999):
ros2 launch ./blackfly_vio.launch.py serial:=13294999 pixel_format:=Mono8
```

Tunable launch args (all optional): `serial`, `frame_rate`, `camera_name`, `frame_id`,
`pixel_format`, `packet_size`, `image_topic`, `info_topic`, `camera_info_url`,
`image_width`, `image_height`, `exposure_auto`, `gain_auto`. Example:

```bash
ros2 launch ./blackfly_vio.launch.py frame_rate:=15.0 exposure_auto:=Off pixel_format:=Mono8
```

Verify topics/rate:

```bash
ros2 topic list | grep blackfly            # expect /blackfly/image_raw, /blackfly/camera_info
ros2 topic hz /blackfly/image_raw          # expect ~10 Hz
```

> If your `camera_aravis2` version publishes under a stream-index suffix
> (e.g. `/blackfly/0/image_raw`), the launch already remaps `~/image_raw` →
> `/blackfly/image_raw`; if a build ignores the remap, pass
> `image_topic:=/blackfly/0/image_raw` to check, or set `stream_names` in the launch.

### 2. View / debug with rqt

```bash
# Dedicated image viewer (pick /blackfly/image_raw in the dropdown):
ros2 run rqt_image_view rqt_image_view

# Full rqt (Plugins > Visualization > Image View; Plugins > Topics > Topic Monitor):
rqt

# Live-tune exposure/gain/frame rate without relaunching (dynamic params):
ros2 run rqt_reconfigure rqt_reconfigure
#   -> select the `blackfly` node -> AcquisitionControl.* / AnalogControl.*
```

### 3. How OpenVINS consumes it

OpenVINS reads `CAMERA_IMAGE_TOPIC=/blackfly/image_raw` (see `shared/.env.example`) plus
raw IMU `/imu/data`. With the driver publishing those topics, start VIO from the VIO
tree (no recording involved):

```bash
cd ..                                   # argos/pi/vio
./scripts/render_openvins_config.sh     # renders /tmp/openvins/*.yaml from .env
ros2 launch ./launch/openvins.launch.py
```

Keep `image_width`/`image_height`, the CameraInfo yaml, and
`shared/config/openvins/kalibr_imucam_chain.yaml` intrinsics consistent (replace the
placeholders in `blackfly_pge_09s2c_camera_info.yaml` with real Kalibr output).

---

## Quick start (recommended: Aravis)

```bash
# deps: sudo apt install aravis-tools-cli gstreamer1.0-plugins-good …
# edit ETH / CAM_* in blackfly_camera.conf
source /opt/ros/humble/setup.bash

cd "$(dirname "$0")"   # this directory

# Live preview (no ROS)
./launch_blackfly_preview.sh cam0

# Publish + record mcap (ROS 2 Humble)
RECORD_CAMS=cam0 ./record_blackfly_ros2_bag.sh
# both cams:  ./record_blackfly_ros2_bag.sh
# + window:   PREVIEW=1 RECORD_CAMS=cam0 ./record_blackfly_ros2_bag.sh
```

Default topics from `blackfly_camera.conf`:

| Cam | Topic | Notes |
|-----|-------|--------|
| cam0 (color) | `/cam_0/image_raw` | OpenVINS / argos expect `/blackfly/image_raw` — remap or edit conf |
| cam1 (mono) | `/cam_1/image_raw` | |

For argos VIO, set in `blackfly_camera.conf`:

```bash
CAM_0_TOPIC="/blackfly/image_raw"
CAM_0_FRAME_ID="blackfly_link"
```

Or remaps when launching OpenVINS (`BLACKFLY_IMAGE_TOPIC` in `shared/.env.example`).

Network one-time (static GigE IPs; needs Spinnaker `GigEConfig` binary):

```bash
sudo ./setup_blackfly_static_ips.sh
```

Pi wiring / Wi‑Fi stream: see `BLACKFLY_PI_SETUP_GUIDE.md`.

---

## Optional: Spinnaker ROS 2 driver

Built workspace (external): `~/inml_ros2_ws/flir_ros2_ws`  
Upstream fork: https://github.com/sauravuprety21/flir_camera_driver  
Packages: `spinnaker_camera_driver`, `spinnaker_synchronized_camera_driver` (ROS 2 Humble).

```bash
source /opt/ros/humble/setup.bash
source ~/inml_ros2_ws/flir_ros2_ws/install/setup.bash

ros2 launch spinnaker_camera_driver driver_node.launch.py \
  camera_type:=blackfly serial:="'13125051'" camera_name:=blackfly_pge

# Or local launch (uses package share blackfly.yaml):
# ros2 launch ./spinnaker/blackfly_pge_09s2c_launch.py
```

Spinnaker SDK install: Teledyne FLIR Spinnaker (system packages already used on this laptop: `libspinnaker` 4.3.x under `/opt/spinnaker`).  
Do **not** vendor Spinnaker debs into argos.

---

## Do not vendor: Arena SDK (Lucid)

Arena is for **Lucid** cameras (Triton / metavision), not Blackfly.

| Path | What |
|------|------|
| `~/ArenaSDK_Linux_x64` (~1.2G) | Host SDK |
| `~/ArenaSDK_Linux_ARM64` | Pi/ARM SDK |
| `~/frame_cameras_official/arena_camera_ros2` | Lucid ROS 2 Humble driver (`arena_camera_node`) |
| `~/roam/blackfly_scripts_gnss/tmp_arena_inspect/` | leftover inspect stub only |

Install Arena from https://thinklucid.com/downloads-hub/ if needed for Tritons; keep out of git.

---

## Other paths on this machine (reference)

| Path | Notes |
|------|--------|
| `/home/vyapak/roam/blackfly_scripts_gnss/scripts/` | Older single-cam Aravis subset + GNSS STM32 |
| `/home/vyapak/used for ROAM/scripts/` | Source of this tree (canonical laptop scripts) |
| `/home/vyapak/Downloads/Spinnaker/` | Spinnaker installer leftovers |
| `/home/vyapak/calib/blackfly_sub1of5_ros1/` | ROS 1 Kalibr bag outputs (data, not driver) |
