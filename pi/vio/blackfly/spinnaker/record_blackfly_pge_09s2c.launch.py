# Launch BFLY-PGE-09S2C-CS driver and record image topics to a rosbag2 bag.
#
# Usage:
#   ros2 launch spinnaker_camera_driver record_blackfly_pge_09s2c.launch.py \
#     serial:="'YOUR_SERIAL'" bag_name:=/tmp/blackfly_recording

from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument as LaunchArg
from launch.actions import ExecuteProcess
from launch.actions import IncludeLaunchDescription
from launch.actions import OpaqueFunction
from launch.actions import TimerAction
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration as LaunchConfig
from launch.substitutions import PathJoinSubstitution
from launch_ros.substitutions import FindPackageShare


def launch_setup(context, *args, **kwargs):
  camera_name = LaunchConfig('camera_name').perform(context)
  bag_name = LaunchConfig('bag_name').perform(context)
  startup_delay = float(LaunchConfig('startup_delay').perform(context))

  camera_launch = IncludeLaunchDescription(
    PythonLaunchDescriptionSource(
      PathJoinSubstitution(
        [
          FindPackageShare('spinnaker_camera_driver'),
          'launch',
          'blackfly_pge_09s2c_launch.py',
        ]
      )
    ),
    launch_arguments={
      'camera_name': camera_name,
      'serial': LaunchConfig('serial').perform(context),
      'frame_id': LaunchConfig('frame_id').perform(context),
    }.items(),
  )

  bag_record = TimerAction(
    period=startup_delay,
    actions=[
      ExecuteProcess(
        cmd=[
          'ros2',
          'bag',
          'record',
          '-o',
          bag_name,
          f'/{camera_name}/image_raw',
          f'/{camera_name}/image_raw/camera_info',
          f'/{camera_name}/meta',
        ],
        output='screen',
      )
    ],
  )

  return [camera_launch, bag_record]


def generate_launch_description():
  return LaunchDescription(
    [
      LaunchArg(
        'camera_name',
        default_value='blackfly_pge',
        description='ROS node name (must match topic prefix)',
      ),
      LaunchArg(
        'serial',
        default_value="'13125051'",
        description='Camera serial number from SpinView (must be in quotes!)',
      ),
      LaunchArg(
        'frame_id',
        default_value='blackfly_pge_optical_frame',
        description='frame_id in published image headers',
      ),
      LaunchArg(
        'bag_name',
        default_value='/tmp/blackfly_pge_09s2c',
        description='Output path for rosbag2 (directory will be created)',
      ),
      LaunchArg(
        'startup_delay',
        default_value='5.0',
        description='Seconds to wait for camera before starting bag record',
      ),
      OpaqueFunction(function=launch_setup),
    ]
  )
