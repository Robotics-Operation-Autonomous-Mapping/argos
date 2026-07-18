"""Pi B (Blackfly+IMU): OpenVINS mono+IMU VIO + Foxglove.

Does NOT start RTABMAP — preferred mapper is Pi A
(pi/lidar/scripts/run_rtabmap_host.sh). VIO-Pi alternative remains under
scripts/run_rtabmap_host.sh. 2× Vivotek are COLMAP-only (not this launch).

Architecture
------------
* NO rtabmap_odom/rgbd_odometry
* NO Madgwick into OpenVINS — raw sensor_msgs/Imu only
* RTABMAP owns loop closure (preferred on lidar Pi)
* OV odom is published for Pi A / laptop CycloneDDS subscribers
"""

from __future__ import annotations

import os

from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, OpaqueFunction
from launch_ros.actions import Node


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def shared_dir() -> str:
    """Resolve the argos shared/ dir for both native and docker runs.

    Order: ARGOS_SHARED override → docker mount (/workspace when present) →
    repo shared/ computed relative to this launch file (<repo>/argos/shared).
    """
    override = os.environ.get("ARGOS_SHARED")
    if override:
        return override
    if os.path.isdir("/workspace/config"):
        return "/workspace"
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(here, "..", "..", "..", "shared"))


def _launch_setup(context, *args, **kwargs):
    camera_frame = env("CAMERA_FRAME_ID", "blackfly_link")
    imu_frame = env("IMU_FRAME_ID", "imu_link")
    foxglove_port = int(env("FOXGLOVE_PORT", "8765"))
    ov_config = env("OV_ESTIMATOR_CONFIG", "/tmp/openvins/estimator_config.yaml")
    foxglove_config = f"{shared_dir()}/config/foxglove_bridge.yaml"

    nodes = [
        # Placeholder camera←IMU extrinsic TF. Replace with Kalibr / URDF.
        Node(
            package="tf2_ros",
            executable="static_transform_publisher",
            name="tf_camera_to_imu",
            arguments=[
                "--x", "0", "--y", "0", "--z", "0",
                "--qx", "0", "--qy", "0", "--qz", "0", "--qw", "1",
                "--frame-id", camera_frame,
                "--child-frame-id", imu_frame,
            ],
        ),
        Node(
            package="ov_msckf",
            executable="run_subscribe_msckf",
            name="ov_msckf",
            output="screen",
            parameters=[
                {
                    "verbosity": "INFO",
                    "use_stereo": False,
                    "max_cameras": 1,
                    "config_path": ov_config,
                }
            ],
        ),
        Node(
            package="foxglove_bridge",
            executable="foxglove_bridge",
            name="foxglove_bridge",
            output="screen",
            parameters=[
                foxglove_config,
                {"port": foxglove_port},
            ],
        ),
    ]
    return nodes


def generate_launch_description() -> LaunchDescription:
    return LaunchDescription(
        [
            DeclareLaunchArgument(
                "use_sim_time",
                default_value="false",
                description="Live multi-host: false. Bag playback: true + --clock.",
            ),
            OpaqueFunction(function=_launch_setup),
        ]
    )
