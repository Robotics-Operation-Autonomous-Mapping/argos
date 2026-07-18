# Proper ROS 2 launch for a single Blackfly (GigE) into OpenVINS via camera_aravis2.
#
# Recommended driver on the Pi (arm64): camera_aravis2 (open-source, Aravis backend,
# already proven with these BFLY-PGE cameras). Publishes sensor_msgs/Image +
# CameraInfo natively and exposes exposure/gain as dynamic params for rqt_reconfigure.
#
# Default wiring matches OpenVINS: node name "blackfly" -> /blackfly/image_raw and
# /blackfly/camera_info (see argos shared .env CAMERA_IMAGE_TOPIC=/blackfly/image_raw).
#
# Usage:
#   ros2 launch blackfly_vio.launch.py                       # cam0 color 13125051 @ 10 Hz
#   ros2 launch blackfly_vio.launch.py serial:=13294999 pixel_format:=Mono8   # cam1 mono
#   ros2 launch blackfly_vio.launch.py frame_rate:=15.0 camera_name:=blackfly
#
# No recording here — the driver only. OpenVINS consumes /blackfly/image_raw directly.

import os

from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument as LaunchArg
from launch.actions import OpaqueFunction
from launch.substitutions import LaunchConfiguration as LaunchConfig
from launch_ros.actions import Node


def launch_setup(context, *args, **kwargs):
    camera_name = LaunchConfig('camera_name').perform(context)
    serial = LaunchConfig('serial').perform(context)
    stream_name = LaunchConfig('stream_name').perform(context)
    frame_id = LaunchConfig('frame_id').perform(context)
    frame_rate = float(LaunchConfig('frame_rate').perform(context))
    pixel_format = LaunchConfig('pixel_format').perform(context)
    packet_size = int(LaunchConfig('packet_size').perform(context))
    image_topic = LaunchConfig('image_topic').perform(context)
    info_topic = LaunchConfig('info_topic').perform(context)
    camera_info_url = LaunchConfig('camera_info_url').perform(context)
    width = int(LaunchConfig('image_width').perform(context))
    height = int(LaunchConfig('image_height').perform(context))
    exposure_auto = LaunchConfig('exposure_auto').perform(context)
    gain_auto = LaunchConfig('gain_auto').perform(context)

    if not camera_info_url:
        camera_info_url = 'file://' + os.path.join(
            os.path.dirname(os.path.realpath(__file__)),
            'blackfly_pge_09s2c_camera_info.yaml',
        )

    image_format = {'PixelFormat': pixel_format}
    if width > 0:
        image_format['Width'] = width
    if height > 0:
        image_format['Height'] = height

    params = {
        # ---- driver-specific ----
        'guid': serial,                 # FLIR serial (camera_aravis2 accepts serial or IP)
        'frame_id': frame_id,
        # camera_aravis2 always builds ~/<stream_name>/image_raw; an empty name
        # yields the illegal "/blackfly//image_raw". Use a concrete name and
        # remap it below to the OpenVINS-expected /blackfly/image_raw.
        'stream_names': [stream_name],
        'camera_info_urls': [camera_info_url],
        'verbose': False,
        # ---- GenICam: transport layer (GigE) ----
        # 1440 avoids the ~2 s stream crash seen on this sensor NIC (see blackfly_camera.conf).
        'TransportLayerControl': {
            'GevSCPSPacketSize': packet_size,
        },
        # ---- GenICam: image format ----
        'ImageFormatControl': image_format,
        # ---- GenICam: acquisition (frame rate + exposure) ----
        # These Point Grey BFLY-PGE cams use the legacy FLIR node names, not the
        # SFNC 'AcquisitionFrameRateEnable'. Order matters: disable auto, enable
        # manual, then set the rate — otherwise the cam free-runs at ~30 Hz.
        'AcquisitionControl': {
            'AcquisitionMode': 'Continuous',
            'AcquisitionFrameRateAuto': 'Off',
            'AcquisitionFrameRateEnabled': True,
            'AcquisitionFrameRate': frame_rate,
            'ExposureMode': 'Timed',
            'ExposureAuto': exposure_auto,
        },
        # ---- GenICam: analog (gain) ----
        'AnalogControl': {
            'GainAuto': gain_auto,
        },
    }

    node = Node(
        package='camera_aravis2',
        executable='camera_driver_gv',
        name=camera_name,
        namespace='',
        output='screen',
        emulate_tty=True,
        parameters=[params],
        # camera_aravis2 publishes under the stream name (~/<stream_name>/...).
        # Force the OpenVINS-expected topics regardless of driver defaults.
        remappings=[
            ('~/' + stream_name + '/image_raw', image_topic),
            ('~/' + stream_name + '/camera_info', info_topic),
        ],
    )

    return [node]


def generate_launch_description():
    return LaunchDescription(
        [
            LaunchArg(
                'camera_name',
                default_value='blackfly',
                description='ROS node name; also the default topic prefix (/blackfly/...)',
            ),
            LaunchArg(
                'serial',
                default_value='13125051',
                description='FLIR serial (guid). cam0 color=13125051, cam1 mono=13294999',
            ),
            LaunchArg(
                'frame_id',
                default_value='blackfly_link',
                description='frame_id stamped in image/camera_info headers (OpenVINS CAMERA_FRAME_ID)',
            ),
            LaunchArg(
                'stream_name',
                default_value='cam',
                description='camera_aravis2 stream name; driver publishes ~/<stream_name>/image_raw '
                            '(remapped to image_topic). Must be non-empty to avoid a "//" topic.',
            ),
            LaunchArg(
                'frame_rate',
                default_value='10.0',
                description='acquisition frame rate in Hz (target for OpenVINS)',
            ),
            LaunchArg(
                'pixel_format',
                default_value='BayerRG8',
                description='PixelFormat: BayerRG8 (color cam0) or Mono8 (mono cam1)',
            ),
            LaunchArg(
                'packet_size',
                default_value='1440',
                description='GevSCPSPacketSize; 1440 is the stable value for this NIC',
            ),
            LaunchArg(
                'image_topic',
                default_value='/blackfly/image_raw',
                description='published image topic (OpenVINS CAMERA_IMAGE_TOPIC)',
            ),
            LaunchArg(
                'info_topic',
                default_value='/blackfly/camera_info',
                description='published CameraInfo topic',
            ),
            LaunchArg(
                'camera_info_url',
                default_value='',
                description='file:// or package:// URL to CameraInfo yaml; empty = bundled placeholder',
            ),
            LaunchArg(
                'image_width',
                default_value='0',
                description='ImageFormatControl/Width; 0 = keep camera default',
            ),
            LaunchArg(
                'image_height',
                default_value='0',
                description='ImageFormatControl/Height; 0 = keep camera default',
            ),
            LaunchArg(
                'exposure_auto',
                default_value='Continuous',
                description='ExposureAuto: Continuous, Once or Off',
            ),
            LaunchArg(
                'gain_auto',
                default_value='Continuous',
                description='GainAuto: Continuous, Once or Off',
            ),
            OpaqueFunction(function=launch_setup),
        ]
    )
