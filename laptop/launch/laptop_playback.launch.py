"""Laptop playback / reprocess: RTABMAP + RViz2 + Foxglove (+ optional OpenVINS).

Bag playback is started separately (scripts/run.sh playback BAG). This launch
expects image + camera_info + OV odometry on the graph — from ros2 bag play or
the live multi-Pi domain.

Does not start Madgwick or rgbd_odometry. Live monitoring should use
use_sim_time=false (monitor profile); playback compose sets USE_SIM_TIME=true.
"""

from __future__ import annotations

import os

from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, OpaqueFunction
from launch_ros.actions import Node


def env(name: str, default: str = "") -> str:
    return os.environ.get(name, default)


def _launch_setup(context, *args, **kwargs):
    image_topic = env("CAMERA_IMAGE_TOPIC", env("BLACKFLY_IMAGE_TOPIC", "/blackfly/image_raw"))
    camera_info_topic = env("CAMERA_INFO_TOPIC", env("BLACKFLY_INFO_TOPIC", "/blackfly/camera_info"))
    ov_odom_topic = env("OV_ODOM_TOPIC", "/ov_msckf/odomimu")
    ov_odom_frame = env("OV_ODOM_FRAME_ID", "global")
    camera_frame = env("CAMERA_FRAME_ID", "blackfly_link")
    scan_topic = env("LIDAR_SCAN_TOPIC", "/scan")
    db_path = env("RTABMAP_DATABASE_PATH", "/data/rtabmap.db")
    foxglove_port = int(env("FOXGLOVE_PORT", "8765"))
    use_sim_time = env("USE_SIM_TIME", "true").lower() in ("1", "true", "yes")
    run_ov = env("PLAYBACK_RUN_OPENVINS", "false").lower() in ("1", "true", "yes")
    ov_config = env("OV_ESTIMATOR_CONFIG", "/tmp/openvins/estimator_config.yaml")
    use_lidar = env("RTABMAP_USE_LIDAR", "false").lower() in ("1", "true", "yes")
    delete_db = env("RTABMAP_DELETE_DB_ON_START", "false").lower() in (
        "1",
        "true",
        "yes",
    )

    rtabmap_args = ["-d"] if delete_db else []
    nodes = []

    if run_ov:
        nodes.append(
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
                        "use_sim_time": use_sim_time,
                    }
                ],
            )
        )

    remappings = [
        ("odom", ov_odom_topic),
        ("rgb/image", image_topic),
        ("rgb/camera_info", camera_info_topic),
    ]
    if use_lidar:
        remappings.append(("scan", scan_topic))

    nodes.extend(
        [
            Node(
                package="rtabmap_slam",
                executable="rtabmap",
                name="rtabmap",
                output="screen",
                parameters=[
                    "/workspace/config/rtabmap.yaml",
                    {
                        "database_path": db_path,
                        "frame_id": camera_frame,
                        "odom_frame_id": ov_odom_frame,
                        "subscribe_depth": False,
                        "subscribe_stereo": False,
                        "subscribe_rgbd": False,
                        "subscribe_imu": False,
                        "subscribe_scan": use_lidar,
                        "approx_sync": True,
                        "queue_size": 30,
                        "use_sim_time": use_sim_time,
                    },
                ],
                remappings=remappings,
                arguments=rtabmap_args,
            ),
            Node(
                package="rviz2",
                executable="rviz2",
                name="rviz2",
                output="screen",
                parameters=[{"use_sim_time": use_sim_time}],
            ),
            Node(
                package="foxglove_bridge",
                executable="foxglove_bridge",
                name="foxglove_bridge",
                output="screen",
                parameters=[
                    "/workspace/config/foxglove_bridge.yaml",
                    {
                        "port": foxglove_port,
                        "use_sim_time": use_sim_time,
                    },
                ],
            ),
        ]
    )
    return nodes


def generate_launch_description() -> LaunchDescription:
    return LaunchDescription(
        [
            DeclareLaunchArgument(
                "use_sim_time",
                default_value="true",
                description="Prefer sim time when playing bags",
            ),
            OpaqueFunction(function=_launch_setup),
        ]
    )
