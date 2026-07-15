# ARGOS on Raspberry Pi

Two physical Pis, one checkout of `argos/pi` + `argos/shared`:

| Dir | Hardware | Role |
|-----|----------|------|
| `vio/` | **Blackfly** + **IMU** + **2× Vivotek** (**Pi B**) | OpenVINS on Blackfly+IMU; Vivotek COLMAP bags; optional recorder |
| `lidar/` | **LiDAR** (**Pi A**) | Publish `/scan`; **preferred native RTABMAP** |

## Storage

| Host | Disk | Policy |
|------|------|--------|
| **Pi A** (`lidar/`) | **256 GB** | Stage maps, RTABMAP DBs, bags → **rsync to laptop** |
| **Pi B** (`vio/`) | **32 GB** | Lean: short buffers; dump COLMAP / Vivotek recordings to Pi A or laptop often |

COLMAP compute stays on the **laptop**.

CycloneDDS: peers **subscribe** — nothing “forwards” to the laptop. Do not stream
all three cameras live; bandwidth is the limit.

## Sparse-checkout (either Pi)

```bash
git sparse-checkout init --cone
git sparse-checkout set argos/README.md argos/LICENSE argos/shared argos/pi
```

On **Pi A** only run `pi/lidar/`. On **Pi B** only run `pi/vio/`.

## Shared prerequisites

```bash
cp shared/.env.example pi/vio/.env    # or pi/lidar/.env
# Edit PI_LIDAR_IP, PI_VIO_IP, LAPTOP_IP, CHRONY_NTP_SERVER, topics
sudo ./shared/scripts/setup_chrony.sh
```

See `shared/docs/topology.md` and `shared/docs/time_sync.md`.

## Preferred run order

1. **Pi B** — OpenVINS (and optionally COLMAP record).
2. **Pi A** — lidar driver + `run_rtabmap_host.sh`.
3. **Laptop** — Foxglove/RViz on whitelisted map topics.

## Pi B — VIO (OpenVINS + COLMAP record)

```bash
cd pi/vio
./scripts/build.sh && ./scripts/run.sh
./scripts/record_colmap.sh              # 2× Vivotek mcap @ COLMAP_IMAGE_RATE_HZ
# See pi/vio/README.md for COLMAP bag details.
```

Cameras: Blackfly = VIO only; Vivoteks = photogrammetry/COLMAP only (not OpenVINS).

## Pi A — lidar + RTABMAP (preferred mapper)

```bash
cd pi/lidar
./scripts/run.sh                        # stub / vendor driver → /scan
RTABMAP_USE_LIDAR=true ./scripts/run_rtabmap_host.sh
# optional: ./scripts/run.sh foxglove
```

RTABMAP consumes `/ov_msckf/odomimu` from Pi B over DDS + **local** `/scan`.
That saves VIO Pi CPU and avoids shipping full lidar streams to Pi B.

## Mapping host policy

| Path | Script | Notes |
|------|--------|-------|
| **Preferred** | `pi/lidar/scripts/run_rtabmap_host.sh` | Odom over DDS + local lidar |
| Alternative | `pi/vio/scripts/run_rtabmap_host.sh` | Simpler if already on VIO Pi; pulls `/scan` via DDS |
| Laptop live | see `laptop/README.md` | Max Pi headroom; needs good Wi‑Fi |

Enable `RTABMAP_USE_LIDAR=true` only after chrony sync and extrinsics are trusted.
