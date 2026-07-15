# ARGOS

**OpenVINS mono+IMU VIO → RTABMAP mapping / loop closure** across two Raspberry
Pis and an amd64 laptop. ROS 2 Humble, CycloneDDS multi-host, Foxglove, chrony
time sync. Offline **COLMAP** on the two Vivotek streams.

Standalone — does **not** depend on ORB-SLAM3 or `orbslam3_docker/`.
**VINS-Fusion has been removed** in favor of OpenVINS.

## Why this architecture

RTABMAP’s `rgbd_odometry` expects RGB-D (or is a weak mono VO substitute). For
calibrated **mono + IMU**:

1. **OpenVINS** estimates visual-inertial odometry from Blackfly images + raw IMU.
2. **RTABMAP** consumes that external odometry plus lidar (preferred) and/or mono
   `camera_info` for mapping and **loop closure**.
3. OpenVINS does not own LC — RTABMAP does.
4. **No Madgwick into OpenVINS** — raw `sensor_msgs/Imu` only.
5. **2× Vivotek** are photogrammetry cameras only (COLMAP bags) — not the VIO FE.

```text
Pi B Blackfly+IMU ──► OpenVINS ──/ov_msckf/odomimu──┐  (DDS)
Pi B 2× Vivotek ────► COLMAP bags (offline)         │
Pi A LiDAR ──/scan (local)──────────────────────────┼──► RTABMAP on Pi A (preferred)
                                                    ├──► Foxglove / laptop (subscribe)
                                                    └──► rosbag2 (optional)
```

CycloneDDS: the laptop **subscribes** — no Pi “forward” hop. Bandwidth is the
real constraint (do not stream three raw cameras live to the laptop).

## Hardware topology (3 roles)

| Host | Hardware | Sparse paths | Runs |
|------|----------|--------------|------|
| **Pi B (VIO)** | Blackfly + IMU + **2× Vivotek** | `shared` + `pi` → `pi/vio` | OpenVINS on Blackfly+IMU; COLMAP record for Vivoteks |
| **Pi A (lidar)** | LiDAR | `shared` + `pi` → `pi/lidar` | `/scan` + **native RTABMAP** (preferred) |
| **Laptop** | amd64 | `shared` + `laptop` | Live map showcase; offline COLMAP / CloudCompare |

Details: [`shared/docs/topology.md`](shared/docs/topology.md).  
Time sync: [`shared/docs/time_sync.md`](shared/docs/time_sync.md) (chrony default).

## Storage

| Host | Disk | Policy |
|------|------|--------|
| **Pi A (lidar / RTABMAP)** | **256 GB** | Staging for maps, RTABMAP DBs, bags — then **rsync to laptop** |
| **Pi B (VIO)** | **32 GB** | Lean only: short buffers; dump COLMAP / Vivotek recordings to the **256 GB Pi** or laptop often |
| **Laptop** | — | **COLMAP compute** + long-term archive of rsynced data |

CycloneDDS peers (same `ROS_DOMAIN_ID` everywhere):

```bash
PI_LIDAR_IP=…   # Pi A
PI_VIO_IP=…     # Pi B
LAPTOP_IP=…
```

## Recommended realtime load split

1. **Pi B:** OpenVINS only (Blackfly+IMU); record/subsample Vivoteks for COLMAP;
   optional lightweight Foxglove.
2. **Pi A:** LiDAR driver + native RTABMAP on `/ov_msckf/odomimu` from Pi B +
   local `/scan` — saves VIO CPU and keeps lidar local to the mapper.
3. **Laptop:** Join domain for Foxglove/RViz (**whitelist**: odom, map,
   cloud/scan compressed — **not** raw 3-camera live).

Alternatives: RTABMAP on VIO Pi (simpler if already set up); RTABMAP live on
laptop (max Pi headroom, needs good Wi‑Fi).

## Repository layout

```text
argos/
  README.md
  LICENSE
  shared/                 # pull on every machine
    .env.example          # IPs + Blackfly / Vivotek / IMU / lidar / OV odom
    config/               # CycloneDDS, RTABMAP, OpenVINS, Foxglove
    docs/                 # topology + time_sync
    scripts/              # chrony, DDS render, install_openvins.sh
    calib/
  pi/
    README.md
    vio/                  # Pi B — OpenVINS + COLMAP recording
    lidar/                # Pi A — lidar + preferred RTABMAP entrypoint
  laptop/                 # amd64: showcase + offline COLMAP / analysis
```

## Sparse-checkout

**Either Pi** (then use only `vio/` or `lidar/`):

```bash
git sparse-checkout init --cone
git sparse-checkout set argos/README.md argos/LICENSE argos/shared argos/pi
```

**Laptop:**

```bash
git sparse-checkout init --cone
git sparse-checkout set argos/README.md argos/LICENSE argos/shared argos/laptop
```

## Quick start (preferred order)

### 1. Env + clocks (all hosts)

```bash
cp shared/.env.example pi/vio/.env      # or pi/lidar/.env or laptop/.env
# Edit peer IPs, CHRONY_NTP_SERVER, Blackfly / Vivotek / IMU / lidar topics
sudo ./shared/scripts/setup_chrony.sh   # on both Pis (and laptop if needed)
```

### 2. Pi B — OpenVINS (+ optional COLMAP record)

```bash
cd pi/vio
./scripts/build.sh && ./scripts/run.sh           # Docker OpenVINS (no RTABMAP in image)
./scripts/record_colmap.sh                       # Vivotek mcap for offline COLMAP
# optional: ./scripts/run.sh recording           # general session bag
```

### 3. Pi A — lidar + native RTABMAP (preferred mapper)

```bash
cd pi/lidar
./scripts/run.sh                                 # vendor driver → /scan
RTABMAP_USE_LIDAR=true ./scripts/run_rtabmap_host.sh
```

### 4. Laptop — live map showcase / offline

```bash
cd laptop
./scripts/build.sh
./scripts/run.sh monitor                         # subscribe: odom / map / scan
# Offline: COLMAP on Vivotek bags; CloudCompare align to RTABMAP/lidar cloud
# Foxglove: bag review or ws://<PI_LIDAR_IP|PI_VIO_IP>:8765
```

## Mapping host policy

**Preferred:** native RTABMAP on **Pi A** consumes OV odom over DDS + local
`/scan`. Set `RTABMAP_USE_LIDAR=true` after chrony sync and extrinsics are solid.

Legacy path: `pi/vio/scripts/run_rtabmap_host.sh` (RTABMAP on VIO Pi). Laptop can
map offline from bags with `use_sim_time` + `--clock`.

## Compose profiles

| Location | Service | Profile | Role |
|----------|---------|---------|------|
| `pi/vio` | `openvins` | default | OpenVINS + Foxglove |
| `pi/vio` | `recorder` | `recording` | general rosbag2 mcap |
| `pi/vio` | `colmap_recorder` | `colmap` | Vivotek (+ optional Blackfly) COLMAP bag |
| `pi/lidar` | `foxglove` | `foxglove` | optional bridge |
| `laptop` | `playback` / `monitor` / `analysis` | matching | UI / reprocess |

## Frame / topic defaults

| Item | Default |
|------|---------|
| Blackfly image | `/blackfly/image_raw` (`CAMERA_IMAGE_TOPIC`) |
| Vivotek L/R | `/vivotek/left|right/image_raw` |
| OpenVINS odom | `/ov_msckf/odomimu` |
| Odom `frame_id` | `global` (`OV_ODOM_FRAME_ID`) |
| Lidar scan | `/scan` |
| Live clocks | synchronized system time; `use_sim_time=false` |
| Bag playback | `use_sim_time=true` + `--clock` |

## Calibration

1. Kalibr cam–IMU on **Blackfly + IMU** (VIO path).
2. Fill `shared/config/openvins/kalibr_*.yaml` templates (or drop files in `shared/calib/`).
3. Publish real `CameraInfo` for Blackfly (RTABMAP RGB if used).
4. Vivotek intrinsics/extrinsics separately for COLMAP / CloudCompare alignment.

## Migration notes (from VINS-Fusion ARGOS)

- Front-end is **OpenVINS** (`ov_msckf` / `run_subscribe_msckf`), not `vins_node`.
- Pi image no longer builds Ceres-from-source or VINS-Fusion; RTABMAP is **not**
  baked into the VIO Pi image (native host install on the mapping Pi).
- Preferred mapper moved to **Pi A (lidar)**; VIO path kept as alternative.
- Env: `VINS_*` → `OV_*`; odom default `/ov_msckf/odomimu`; peers split into
  `PI_LIDAR_IP` + `PI_VIO_IP`.
- Layout split for sparse-checkout: `shared/` + `pi/{vio,lidar}/` + `laptop/`.

## Offline tools (host laptop)

```bash
sudo apt install colmap cloudcompare   # availability varies
```

See [`laptop/README.md`](laptop/README.md) for COLMAP + CloudCompare workflow.

## License

MIT for ARGOS wrappers and configs. OpenVINS is GPLv3 — see `LICENSE`.
