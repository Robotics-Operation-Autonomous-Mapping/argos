"""Native host RTABMAP on the preferred mapping host (Pi A / lidar).

Consumes OpenVINS odometry from Pi B over CycloneDDS plus local lidar /scan
(or cloud). Optional mono RGB from Blackfly over DDS if bandwidth allows
(CAMERA_IMAGE_TOPIC). Does not start OpenVINS or rgbd_odometry.
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
    image_topic = env("CAMERA_IMAGE_TOPIC", env("BLACKFLY_IMAGE_TOPIC", "/blackfly/image_raw"))
    camera_info_topic = env("CAMERA_INFO_TOPIC", env("BLACKFLY_INFO_TOPIC", "/blackfly/camera_info"))
    ov_odom_topic = env("OV_ODOM_TOPIC", "/ov_msckf/odomimu")
    ov_odom_frame = env("OV_ODOM_FRAME_ID", "global")
    camera_frame = env("CAMERA_FRAME_ID", "blackfly_link")
    scan_topic = env("LIDAR_SCAN_TOPIC", "/scan")
    db_path = env("RTABMAP_DATABASE_PATH", os.path.expanduser("~/argos_data/rtabmap.db"))
    shared = shared_dir()
    config = env("RTABMAP_CONFIG", f"{shared}/config/rtabmap.yaml")
    use_lidar = env("RTABMAP_USE_LIDAR", "true").lower() in ("1", "true", "yes")
    delete_db = env("RTABMAP_DELETE_DB_ON_START", "true").lower() in (
        "1",
        "true",
        "yes",
    )
    use_sim_time = env("USE_SIM_TIME", "false").lower() in ("1", "true", "yes")

    params = {
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
    }

    remappings = [
        ("odom", ov_odom_topic),
        ("rgb/image", image_topic),
        ("rgb/camera_info", camera_info_topic),
    ]
    if use_lidar:
        remappings.append(("scan", scan_topic))

    rtabmap_args = ["-d"] if delete_db else []

    return [
        Node(
            package="rtabmap_slam",
            executable="rtabmap",
            name="rtabmap",
            output="screen",
            parameters=[config, params],
            remappings=remappings,
            arguments=rtabmap_args,
        ),
    ]


def generate_launch_description() -> LaunchDescription:
    return LaunchDescription(
        [
            DeclareLaunchArgument(
                "use_sim_time",
                default_value="false",
                description="false for live sync'd clocks; true for bag playback",
            ),
            OpaqueFunction(function=_launch_setup),
        ]
    )
