# BFLY-PGE Spinnaker / ROS 2 driver files

These files were split out from `inml_ros2_ws/flir_ros2_ws` for the **BFLY-PGE-09S2C** GigE camera when using the **Spinnaker SDK** stack. Spinnaker is the **laptop** option (SDK already built there); it is a poor fit for the 32 GB arm64 **Pi**.

**On the Pi, use `camera_aravis2` instead** — the proper `ros2 launch` route for live VIO:

- `../blackfly_vio.launch.py` — `ros2 launch ./blackfly_vio.launch.py` → `/blackfly/image_raw` @ 10 Hz for OpenVINS

For quick preview and rosbag recording, use the **Aravis** scripts in the parent folder:

- `launch_blackfly_preview.sh` — live preview
- `record_blackfly_ros2_bag.sh` — record ROS 2 bag (mcap)

## Spinnaker usage (optional)

```bash
source /opt/ros/humble/setup.bash
source ~/inml_ros2_ws/flir_ros2_ws/install/setup.bash

# Copy launch into package share or run by path:
ros2 launch spinnaker_camera_driver driver_node.launch.py \
  camera_type:=blackfly serial:="'13125051'" camera_name:=blackfly_pge
```

## Files

| File | Purpose |
|------|---------|
| `blackfly_pge_09s2c_launch.py` | Minimal Spinnaker ROS driver launch |
| `record_blackfly_pge_09s2c.launch.py` | Spinnaker driver + rosbag2 |
| `discover_cameras` | List cameras via Spinnaker Enumeration |
| `reset_sensor_network.sh` | Reset USB-GigE NIC (MTU 1500, RX ring) |
| `setup_gige_sensor_network.sh` | GigE tuning without jumbo MTU |
| `diagnose_gige.sh` | Network + stream diagnostic |

Install back into the package manually if needed:

```bash
cp launch/*.py ~/inml_ros2_ws/flir_ros2_ws/src/flir_camera_driver/spinnaker_camera_driver/launch/
cp scripts/* ~/inml_ros2_ws/flir_ros2_ws/src/flir_camera_driver/spinnaker_camera_driver/scripts/
```
