"""Optional Foxglove bridge on the lidar Pi (preferred live-map showcase host).

Uses foxglove_bridge_map.yaml by default (odom/map/scan whitelist — not raw cams).
Set FOXGLOVE_CONFIG=foxglove_bridge.yaml for unrestricted lab debugging.
Lidar driver nodes are expected on the host (see scripts/run.sh).
"""

from __future__ import annotations

import os

from launch import LaunchDescription
from launch_ros.actions import Node


def generate_launch_description() -> LaunchDescription:
    port = int(os.environ.get("FOXGLOVE_PORT", "8765"))
    shared = os.environ.get("ARGOS_SHARED", "/workspace")
    cfg_name = os.environ.get("FOXGLOVE_CONFIG", "foxglove_bridge_map.yaml")
    config = f"{shared}/config/{cfg_name}"
    return LaunchDescription(
        [
            Node(
                package="foxglove_bridge",
                executable="foxglove_bridge",
                name="foxglove_bridge",
                output="screen",
                parameters=[
                    config,
                    {"port": port},
                ],
            ),
        ]
    )
