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

## Bringup: Blackfly + ICM-20948 IMU (validated on Pi B)

The exact sequence that produced a live `/blackfly/image_raw` @ 10 Hz and raw
`/imu/data_raw` @ a **locked 200 Hz** feeding OpenVINS. Run each block in its own
terminal after `source /opt/ros/humble/setup.bash`.

### 1. Blackfly camera (`camera_aravis2`)

Install (arm64 Humble binaries; build from source only if no binary):

```bash
sudo apt install -y ros-humble-camera-aravis2 ros-humble-rqt-image-view ros-humble-rqt-reconfigure
# Fallback (no arm64 binary): build camera_aravis2 from source with libaravis-0.8-dev.
```

**GigE network.** The Blackfly holds a **persistent static IP `192.168.1.1`** on its
GigE port. Put the host on that subnet each boot (before launching):

```bash
sudo ip addr add 192.168.1.100/24 dev eth0
# If discovery still fails ("No device found") with the link up, disable reverse-path
# filtering (asymmetric camera subnet):
sudo sysctl -w net.ipv4.conf.all.rp_filter=0
sudo sysctl -w net.ipv4.conf.eth0.rp_filter=0
```

Confirm the camera is discoverable (found as
`Point Grey Research-Blackfly BFLY-PGE-09S2C-13125051`):

```bash
arv-tool-0.8 list
```

Serials: **cam0 color = `13125051`**, **cam1 mono = `13294999`**. The launch already
sets `GevSCPSPacketSize=1440` (required — larger packets crash the stream on the Pi NIC
after ~2 s).

**Launch.** A bare serial fails `camera_aravis2` discovery — pass the **full GUID**
(or leave `serial` empty to grab the first camera):

```bash
cd blackfly
ros2 launch ./blackfly_vio.launch.py \
    serial:="Point Grey Research-Blackfly BFLY-PGE-09S2C-13125051"
```

Publishes `/blackfly/image_raw` + `/blackfly/camera_info` at **10 Hz**
(`frame_rate:=10` holds because the launch sets `AcquisitionFrameRateAuto=Off` +
`AcquisitionFrameRateEnabled=True` + `AcquisitionFrameRate`).

View / tune / verify:

```bash
ros2 run rqt_image_view rqt_image_view        # select /blackfly/image_raw
ros2 run rqt_reconfigure rqt_reconfigure      # exposure / gain live
ros2 topic hz /blackfly/image_raw             # expect ~10 Hz
```

Camera-specific detail (Aravis scripts, Spinnaker option, per-arg reference):
[`blackfly/README.md`](./blackfly/README.md#proper-ros-2-way-ros2-launch-for-openvins-recommended-on-the-pi).

### 2. ICM-20948 IMU (external driver)

> **External dependency — NOT vendored in argos.** The driver lives at
> `~/ros2_icm20948_driver` (package `ros2_icm20948`). Clone/build it separately.

Hardware: ICM-20948 on **I2C bus 1, address `0x69`**. Confirm and check group
membership (the user must be in the `i2c` group):

```bash
sudo i2cdetect -y 1        # expect a device at 0x69
```

Build:

```bash
cd ~/ros2_icm20948_driver
colcon build --symlink-install
source install/setup.bash
```

**Run RAW (no Madgwick).** The driver's `raw` launch pulls in `imu_filter_madgwick`,
which we intentionally avoid — run the node directly:

```bash
# confirm the executable name first:
ros2 pkg executables ros2_icm20948
ros2 run ros2_icm20948 icm20948_node --ros-args -p raw_only:=true -p pub_rate_hz:=200
```

Publishes `/imu/data_raw` — **raw accel+gyro, `orientation_covariance[0] = -1`**
(no orientation).

> **IMPORTANT:** feed **`/imu/data_raw`** to OpenVINS. Do **NOT** feed `/imu/data`
> (that is the Madgwick-fused topic). See `IMU_TOPIC` in `shared/.env.example`.

#### Lock the raw topic to a real 200 Hz

`pub_rate_hz:=200` does **NOT** cap the raw topic — the raw path was observed
free-running at **~321 Hz** (it reads the sensor and publishes as fast as the I2C
bus allows; `pub_rate_hz` only affected the fused/`raw_only:=false` path). For
Allan variance + Kalibr + OpenVINS the IMU rate must be **stable and identical**
between the calibration bag and live VIO, so we pin the publish to a fixed 200 Hz.

**Why 200 (not exactly the sensor ODR):** the ICM-20948 accel/gyro ODR is
`1125 / (1 + SMPLRT_DIV)` Hz, so 200 Hz is not an integer divisor (div 4 → 225 Hz,
div 5 → 187.5 Hz). The robust, standard fix is to let the sensor sample a bit
faster and **publish on a fixed 200 Hz ROS timer** that reads the freshest sample
each tick (this reference driver measures `ros2 topic hz` ≈ 200.04 Hz that way).

The driver (`~/ros2_icm20948_driver`, package `ros2_icm20948`) is an **external
dependency, NOT vendored in argos and NOT under git here** — apply this small edit
to its `ros2_icm20948/icm20948_node.py` so the raw topic is locked:

1. In `__init__`, after `self.imu.begin()`, set a stable ODR (enable each DLPF so
   `SMPLRT_DIV` takes effect, then divide the 1125 Hz base to 225 Hz — one step
   above 200 for headroom) using the qwiic register API:

```python
IMU_ODR_DIV = 4  # 1125 / (1 + 4) = 225 Hz sensor ODR (>= 200 Hz publish)
self.imu.enableDlpfGyro(True)
self.imu.enableDlpfAccel(True)
self.imu.setDLPFcfgGyro(1)     # ~152 Hz gyro bandwidth
self.imu.setDLPFcfgAccel(1)    # ~136 Hz accel bandwidth
self.imu.setBank(2)
self.imu._i2c.writeByte(self.imu.address, self.imu.AGB2_REG_GYRO_SMPLRT_DIV, IMU_ODR_DIV)
self.imu._i2c.writeByte(self.imu.address, self.imu.AGB2_REG_ACCEL_SMPLRT_DIV_1, (IMU_ODR_DIV >> 8) & 0x0F)
self.imu._i2c.writeByte(self.imu.address, self.imu.AGB2_REG_ACCEL_SMPLRT_DIV_2, IMU_ODR_DIV & 0xFF)
self.imu.setBank(0)
```

2. Make the raw path publish from a **fixed 200 Hz timer** (do not busy-loop /
   publish-on-read). Ensure the timer period comes from `pub_rate_hz` and is
   actually used for `raw_only:=true`:

```python
self.declare_parameter("pub_rate_hz", 200)
self._pub_rate_hz = self.get_parameter("pub_rate_hz").get_parameter_value().integer_value
self._timer = self.create_timer(1.0 / float(self._pub_rate_hz), self.publish_cback)
# and REMOVE any while-loop / publish-on-dataReady path used when raw_only:=true
```

After rebuilding the driver (`colcon build --symlink-install` in
`~/ros2_icm20948_driver`), the run command above produces a locked 200 Hz. Keep
`shared/.env.example` `IMU_RATE_HZ=200` in sync with this.

Verify (expect a steady **~200 Hz**):

```bash
ros2 topic hz /imu/data_raw          # average rate ~200, tiny std dev
ros2 topic echo /imu/data_raw --once   # accel ~9.8 on one axis at rest; orientation_covariance[0] = -1
```

### 3. Time sync (camera ↔ IMU)

Both sensors run on **Pi B → one system clock (single time base)**. They are
**soft-synced** (no hardware trigger); any residual constant offset is absorbed by
Kalibr `timeshift_cam_imu` / OpenVINS `calib_cam_timeoffset`. To measure the effective
offset, run simultaneously:

```bash
ros2 topic delay /imu/data_raw
ros2 topic delay /blackfly/image_raw
```

The difference between the two is the effective camera–IMU offset.

### Outstanding VIO blocker

The **cam–IMU extrinsic + time offset (Kalibr)** is still the outstanding blocker for
trustworthy VIO — see [`../../shared/calib/README.md`](../../shared/calib/README.md).
The IMU biases are also being **redone**: the old Allan bag was on the fused `/imu/data`,
so a fresh **no-Madgwick** Allan recording on `/imu/data_raw` is in progress at the
**locked 200 Hz** (see "Lock the raw topic to a real 200 Hz" above). `IMU_RATE_HZ`
(in `shared/.env.example`) is now `200` to match both the locked driver and that bag.

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

## Calibration recording (cam–IMU + Allan)

`blackfly/record_camimu_calib.sh` records the calibration bags with a **preflight
VERIFY** that both sensors are actually live (aborts if `/blackfly/image_raw` or
`/imu/data_raw` is missing/silent, and prints the measured rates — expect ~10 Hz
cam, ~200 Hz IMU). Bring the camera + IMU up first, then:

```bash
cd blackfly
./record_camimu_calib.sh          # cam+IMU calib bag (excite all 6 DoF at the target)
./record_camimu_calib.sh --allan  # long STATIC IMU-only Allan bag (ALLAN_HOURS=3)
```

Topics/paths come from `.env` (`CAMERA_IMAGE_TOPIC`/`BLACKFLY_IMAGE_TOPIC`,
`CAMERA_INFO_TOPIC`, `IMU_TOPIC`, `BAG_OUTPUT_DIR`). Process the Allan bag with
`../../shared/scripts/imu_allan_variance.py`; see
[`../../shared/calib/README.md`](../../shared/calib/README.md).

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
