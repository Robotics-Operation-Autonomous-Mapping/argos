# Calibration artifacts

Drop real Kalibr / cam-IMU results here (YAML, camchain, imu.yaml, etc.).
Config templates live under `shared/config/openvins/`; this folder is for
**measured** calibration artifacts copied onto both Pis and the laptop.

VIO path: Kalibr **Blackfly + IMU** only (not Vivotek).
Vivotek intrinsics/extrinsics are separate (COLMAP / CloudCompare alignment).

Everything here except this README and `.gitkeep` is git-ignored (see `.gitignore`).

## Status

| Calibration | What it gives | Status | Artifact |
|---|---|---|---|
| Camera intrinsics (Blackfly) | fu,fv,cu,cv + fisheye/equidistant distortion | DONE | `roam_cam0_filtered-camchain.yaml` (+ `-results-cam.txt`, `-report-cam.pdf`) |
| IMU noise (Allan variance) | accel/gyro noise density + random walk | DONE | `imu_allan_20260717_1411-imu.yaml` |
| **Camera–IMU extrinsic + time offset** | `T_imu_cam`, `time_offset` | **TODO — required for VIO** | — |
| IMU intrinsics (scale/misalignment, g-sensitivity) | `Tw/Ta/Tg`, `R_IMUto*` | optional (disabled in estimator) | — |
| LiDAR → IMU/base extrinsic | static TF for RTABMAP lidar fusion | TODO if `RTABMAP_USE_LIDAR=true` | — |
| Vivotek intrinsics ×2 | COLMAP camera models | TODO (photogrammetry) | — |
| (optional) Camera ↔ LiDAR extrinsic | color/lidar projection, alignment aid | optional | — |

Values from the two DONE items are already baked into
`shared/config/openvins/kalibr_imucam_chain.yaml.template` (intrinsics) and
`shared/config/openvins/kalibr_imu_chain.yaml.template` (noise). The
`T_imu_cam` in the imucam template is still an identity placeholder until the
cam–IMU calibration below is run.

## Priority order (highest impact first)

| # | Item | Why / when | Status |
|---|---|---|---|
| 1 | Cam–IMU **extrinsic + time offset** (`T_imu_cam`, `timeshift`) | Missing piece; VIO is untrustworthy without it | TODO |
| 2 | **2D lidar extrinsic TF** (`laser_link` → base/IMU) | Needed only if `RTABMAP_USE_LIDAR=true`; measure/CAD it + keep scan plane level. NO intrinsic calib for a 2D lidar | TODO (if using lidar) |
| 3 | IMU **noise** (Allan: noise density / random walk) | Feeds OpenVINS IMU model | DONE |
| 4 | Camera **intrinsics** (Blackfly) | fu,fv,cu,cv + distortion | DONE |
| 5 | IMU **intrinsics** (scale / misalignment `Tw/Ta/Tg`) | Second-order; skip unless chasing accuracy | skip (disabled) |
| 6 | IMU **g-sensitivity** | Usually negligible | skip (disabled) |
| — | Vivotek intrinsics ×2 | Offline COLMAP photogrammetry only | TODO |

## How to (re)produce these

### IMU noise (Allan variance)
Long (≥ ~3 h ideally) **perfectly static** recording of the RAW IMU topic:
```
ros2 bag record -o imu_allan_$(date +%Y%m%d_%H%M) /imu/data
python3 shared/scripts/imu_allan_variance.py <bag_dir> --topic /imu/data \
    --out shared/calib/<name>-imu.yaml
```
Then copy the four `*_noise_density` / `*_random_walk` values into
`shared/config/openvins/kalibr_imu_chain.yaml.template`.

### Camera–IMU extrinsic + time offset (the missing piece)
Record a bag while gently exciting all 6 DoF in front of an April/checkerboard
target, then:
```
kalibr_calibrate_imu_camera \
    --cam roam_cam0_filtered-camchain.yaml \
    --imu <name>-imu.yaml \
    --target target.yaml --bag cam_imu.bag
```
Copy the resulting `T_imu_cam` (4x4) and `timeshift_cam_imu` into
`shared/config/openvins/kalibr_imucam_chain.yaml.template`.
