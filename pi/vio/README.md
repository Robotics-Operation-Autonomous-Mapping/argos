# Pi B — VIO + COLMAP recording

**Hardware:** Blackfly (live VIO) + IMU + **2× Vivotek** (photogrammetry / COLMAP only).

OpenVINS runs on **Blackfly + IMU only**. Do not feed Vivotek topics into OpenVINS.

**Blackfly drivers / preview / bag scripts:** see [`blackfly/README.md`](./blackfly/README.md) (Aravis ROS 2 Humble; optional Spinnaker wrappers).

**Live VIO camera feed (proper `ros2 launch`, no recording):** run the Blackfly through
`camera_aravis2` — `ros2 launch ./blackfly/blackfly_vio.launch.py` publishes
`/blackfly/image_raw` @ 10 Hz for OpenVINS. Debug with `ros2 run rqt_image_view
rqt_image_view` and tune exposure/gain with `ros2 run rqt_reconfigure rqt_reconfigure`.
See [`blackfly/README.md`](./blackfly/README.md#proper-ros-2-way-ros2-launch-for-openvins-recommended-on-the-pi).

**Storage (32 GB):** keep this Pi lean — short buffers only. Dump COLMAP / Vivotek
recordings to the **256 GB Pi A** (RTABMAP staging) or the laptop often. COLMAP
runs on the laptop, not here.

## Quick start

```bash
cp ../../shared/.env.example .env
# Set PI_*_IP, BLACKFLY_*, VIVOTEK_*, IMU_TOPIC, OV_*
./scripts/build.sh && ./scripts/run.sh
```

Native RTABMAP is **preferred on Pi A** (`../lidar/scripts/run_rtabmap_host.sh`).
This tree keeps `./scripts/run_rtabmap_host.sh` as an alternative (VIO-host mapper).

## COLMAP recording profile

Records the two Vivotek image topics (and `camera_info` if published), plus `/tf`,
`/tf_static`, and OpenVINS odom for later alignment to the RTABMAP/lidar map.

```bash
# Host-side recorder (recommended while OpenVINS compose is up)
./scripts/record_colmap.sh

# Or compose profile (same bag contents inside the VIO container volume)
./scripts/run.sh colmap
```

Env (see `shared/.env.example`):

| Variable | Purpose |
|----------|---------|
| `VIVOTEK_LEFT_TOPIC` / `VIVOTEK_RIGHT_TOPIC` | Image topics to bag |
| `VIVOTEK_LEFT_INFO_TOPIC` / `VIVOTEK_RIGHT_INFO_TOPIC` | Optional CameraInfo |
| `COLMAP_IMAGE_RATE_HZ` | Target rate (default `2`); throttles when `topic_tools` is available |
| `COLMAP_INCLUDE_BLACKFLY` | `true` to also bag Blackfly (default `false`) |
| `OV_ODOM_TOPIC` | Included for pose alignment |
| `BAG_OUTPUT_DIR` / `BAG_STORAGE_ID` | Output path / `mcap` |

If throttling is unavailable, record full rate and subsample offline (e.g. extract
every Nth frame before COLMAP).

Bags land under `$BAG_OUTPUT_DIR` (Docker volume: `/data/bags`).

## General session recording

```bash
./scripts/run.sh recording    # Blackfly + IMU + odom + scan + map topics
```

## Offline on the laptop

1. Offload COLMAP mcaps from this 32 GB Pi to **Pi A (256 GB)** and/or the laptop.
2. Run COLMAP on the Vivotek frames **on the laptop**.
3. Align the COLMAP model to the RTABMAP/lidar cloud in CloudCompare using
   shared time / `/tf` / odom from the bag.
4. Review bags in Foxglove Studio.

See [`../../laptop/README.md`](../../laptop/README.md).
