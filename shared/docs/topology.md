# Multi-host topology

ARGOS splits sensing across two Raspberry Pis plus an amd64 laptop. All three
share one ROS 2 domain over **CycloneDDS** with explicit peer IPs. With CycloneDDS,
the laptop (and any peer) **subscribes** to topics on the domain — no Pi needs to
“forward” traffic to the laptop. **Bandwidth** (especially live imagery) is the
real constraint; whitelist aggressively for Foxglove/RViz.

```text
                    ┌──────────────────────────────────┐
                    │  Laptop (amd64)                  │
                    │  live map showcase (Foxglove/RViz)│
                    │  offline COLMAP / CloudCompare   │
                    └───────────▲──────────────────────┘
                                │ CycloneDDS subscribe
            ┌───────────────────┴───────────────────┐
            │                                       │
   ┌────────┴────────┐                   ┌─────────┴──────────────┐
   │ Pi A — lidar    │                   │ Pi B — VIO             │
   │ LiDAR driver    │◄──/ov_msckf/odom──│ Blackfly + IMU         │
   │ + native RTABMAP│    (DDS)          │ OpenVINS only          │
   │ local /scan     │                   │ 2× Vivotek → COLMAP    │
   └─────────────────┘                   │ bags (not VIO FE)      │
                                         └────────────────────────┘
```

## Hardware / roles (locked)

| Host | Hardware | Role |
|------|----------|------|
| **Pi B (VIO)** | **Blackfly** (live VIO camera) + **IMU** + **2× Vivotek** | OpenVINS on Blackfly+IMU only. Vivoteks are for **photogrammetry / COLMAP** (record/subsample) — **not** the VIO front-end. |
| **Pi A (lidar)** | **LiDAR** | Driver publishes `/scan` (or cloud). **Preferred** host for **native RTABMAP**. |
| **Laptop** | amd64 | Live map showcase (Foxglove/RViz) + offline COLMAP / analysis. |

## Storage

| Host | Disk | Policy |
|------|------|--------|
| **Pi A (lidar / RTABMAP)** | **256 GB** | Stage maps, RTABMAP DBs, bags; **rsync to laptop** |
| **Pi B (VIO)** | **32 GB** | Lean: short buffers only; dump COLMAP / Vivotek bags to Pi A or laptop often |
| **Laptop** | — | COLMAP compute + long-term archive |

Time sync: [`time_sync.md`](time_sync.md) (chrony default).

## Recommended realtime load split (preferred)

Keeps VIO Pi headroom and keeps lidar data **local** to the mapper (more feasible
than streaming full lidar clouds to the VIO Pi).

1. **Pi B:** OpenVINS only on Blackfly + IMU; record/subsample both Vivoteks for
   COLMAP; optional lightweight Foxglove (odom / status — not three raw cameras).
2. **Pi A:** LiDAR driver + **native RTABMAP** consuming `/ov_msckf/odomimu`
   (or remapped `/odom`) from Pi B over DDS + local `/scan` or cloud.
3. **Laptop:** Join the same domain for Foxglove/RViz on a **whitelist**: odom,
   map, compressed cloud/scan — **not** live raw Blackfly + 2× Vivotek streams.

Entrypoint: `pi/lidar/scripts/run_rtabmap_host.sh`.

### Alternatives (brief)

| Alternative | When |
|-------------|------|
| **RTABMAP on VIO Pi** (`pi/vio/scripts/run_rtabmap_host.sh`) | Simpler if already set up; pulls `/scan` over DDS; uses more VIO CPU. |
| **RTABMAP on laptop (live)** | Max Pi headroom; needs good Wi‑Fi and still avoid raw multi-cam live. |

## Env peers

```bash
PI_LIDAR_IP=192.168.1.51   # Pi A
PI_VIO_IP=192.168.1.52     # Pi B
LAPTOP_IP=192.168.1.60
ROS_DOMAIN_ID=42
```

Firewall: allow UDP DDS between hosts and TCP `FOXGLOVE_PORT` for Studio.

## Cameras (topic policy)

| Camera | Env | Live use |
|--------|-----|----------|
| Blackfly | `BLACKFLY_IMAGE_TOPIC` / `CAMERA_IMAGE_TOPIC` | OpenVINS (+ optional RTABMAP RGB if bandwidth allows) |
| Vivotek left | `VIVOTEK_LEFT_TOPIC` | COLMAP bags only |
| Vivotek right | `VIVOTEK_RIGHT_TOPIC` | COLMAP bags only |

Do **not** run `rgbd_odometry` for mono. Do **not** feed Madgwick into OpenVINS.
Lidar→RTABMAP fusion: enable `RTABMAP_USE_LIDAR=true` after chrony sync and
extrinsics are trusted (`subscribe_scan` in `shared/config/rtabmap.yaml`).
