"""Stub / documentation launch for lidar bringup on Pi A.

Replace the placeholder static TF + commented driver with your vendor package.
Publishes onto the shared domain so the VIO Pi / laptop can subscribe to
LIDAR_SCAN_TOPIC (/scan by default).
"""

from __future__ import annotations

import os

from launch import LaunchDescription
from launch.actions import LogInfo, OpaqueFunction
from launch_ros.actions import Node


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def _launch_setup(context, *args, **kwargs):
    lidar_frame = env("LIDAR_FRAME_ID", "laser_link")
    # Base / body frame on the lidar Pi — adjust to your robot frames.
    parent = env("LIDAR_PARENT_FRAME", "base_link")

    return [
        LogInfo(
            msg=(
                "ARGOS lidar stub: start your vendor driver so it publishes "
                f"{env('LIDAR_SCAN_TOPIC', '/scan')} (and optional "
                f"{env('LIDAR_CLOUD_TOPIC', '/points')}). "
                "Example: ros2 launch <vendor> <file>.py"
            )
        ),
        Node(
            package="tf2_ros",
            executable="static_transform_publisher",
            name="tf_base_to_laser",
            arguments=[
                "--x", "0", "--y", "0", "--z", "0",
                "--qx", "0", "--qy", "0", "--qz", "0", "--qw", "1",
                "--frame-id", parent,
                "--child-frame-id", lidar_frame,
            ],
        ),
        # Example (uncomment / replace):
        # Node(
        #     package="rplidar_ros",
        #     executable="rplidar_composition",
        #     name="rplidar",
        #     parameters=[{"serial_port": "/dev/ttyUSB0", "frame_id": lidar_frame}],
        #     remappings=[("scan", env("LIDAR_SCAN_TOPIC", "/scan"))],
        # ),
    ]


def generate_launch_description() -> LaunchDescription:
    return LaunchDescription([OpaqueFunction(function=_launch_setup)])
