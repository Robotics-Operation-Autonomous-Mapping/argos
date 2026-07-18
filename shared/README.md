# Shared ARGOS assets

Pulled by **every** host (lidar Pi, VIO Pi, laptop). Contains CycloneDDS
templates, topic/env conventions, RTABMAP YAML, OpenVINS Kalibr-style configs,
time-sync helpers, and calibration drop folder.

## Contents

| Path | Role |
|------|------|
| `.env.example` | Canonical env keys (copy to `pi/vio/.env`, `pi/lidar/.env`, `laptop/.env`) |
| `config/cyclonedds.xml.template` | Peers: `PI_LIDAR_IP`, `PI_VIO_IP`, `LAPTOP_IP` |
| `config/rtabmap.yaml` | External-odom RTABMAP (no `rgbd_odometry`) |
| `config/openvins/` | Estimator + Kalibr IMU/cam templates |
| `config/foxglove_bridge.yaml` | Foxglove Studio bridge (dev; all topics) |
| `config/foxglove_bridge_map.yaml` | Live showcase whitelist (odom/map/scan — not raw cams) |
| `docs/topology.md` | Multi-Pi + laptop data flow (preferred RTABMAP on lidar Pi) |
| `docs/time_sync.md` | chrony (default) / optional PTP |
| `scripts/setup_chrony.sh` | Host chrony client setup |
| `scripts/render_cyclonedds.sh` | Render DDS XML for native ROS |
| `calib/` | Measured Kalibr artifacts |

## Topic naming (defaults)

| Topic env | Default | Publisher / notes |
|-----------|---------|-------------------|
| `BLACKFLY_IMAGE_TOPIC` / `CAMERA_IMAGE_TOPIC` | `/blackfly/image_raw` | Pi B — **VIO only** |
| `BLACKFLY_INFO_TOPIC` / `CAMERA_INFO_TOPIC` | `/blackfly/camera_info` | Pi B |
| `VIVOTEK_LEFT_TOPIC` | `/vivotek/left/image_raw` | Pi B — **COLMAP only** |
| `VIVOTEK_RIGHT_TOPIC` | `/vivotek/right/image_raw` | Pi B — **COLMAP only** |
| `IMU_TOPIC` | `/imu/data` | Pi B (raw only; `/imu/data` is this driver's raw topic) |
| `OV_ODOM_TOPIC` | `/ov_msckf/odomimu` | OpenVINS on Pi B |
| `LIDAR_SCAN_TOPIC` | `/scan` | Lidar Pi |
| `LIDAR_CLOUD_TOPIC` | `/points` | Lidar Pi (optional) |

Same `ROS_DOMAIN_ID` (default `42`) and RMW CycloneDDS on all machines. Laptop
**subscribes** on the domain — no forward hop; bandwidth is the constraint.
