# Launch file for Teledyne FLIR Blackfly BFLY-PGE-09S2C-CS (GigE, color, 1288x728)
#
# Uses blackfly.yaml (NOT blackfly_s). Loads UserSet0 so SpinView network settings
# (packet size, resolution, etc.) are preserved — do not add format/GigE overrides here.

from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument as LaunchArg
from launch.actions import OpaqueFunction
from launch.substitutions import LaunchConfiguration as LaunchConfig
from launch.substitutions import PathJoinSubstitution
from launch_ros.actions import Node
from launch_ros.substitutions import FindPackageShare

# Only load the camera's saved SpinView config. No pixel_format / gev_scps / chunk overrides.
blackfly_pge_09s2c_parameters = {
    'debug': False,
    'dump_node_map': False,
    'buffer_queue_size': 10,
    'user_set_selector': 'UserSet0',
    'user_set_load': 'Yes',
}


def launch_setup(context, *args, **kwargs):
  parameter_file = LaunchConfig('parameter_file').perform(context)
  if not parameter_file:
    parameter_file = PathJoinSubstitution(
      [FindPackageShare('spinnaker_camera_driver'), 'config', 'blackfly.yaml']
    )

  node = Node(
    package='spinnaker_camera_driver',
    executable='camera_driver_node',
    output='screen',
    name=[LaunchConfig('camera_name')],
    parameters=[
      blackfly_pge_09s2c_parameters,
      {
        'parameter_file': parameter_file,
        'serial_number': [LaunchConfig('serial')],
        'frame_id': [LaunchConfig('frame_id')],
      },
    ],
    remappings=[
      ('~/control', '/exposure_control/control'),
    ],
  )

  return [node]


def generate_launch_description():
  return LaunchDescription(
    [
      LaunchArg(
        'camera_name',
        default_value='blackfly_pge',
        description='ROS node name (topics are /<camera_name>/image_raw, etc.)',
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
        'parameter_file',
        default_value='',
        description='Override path to GenICam parameter YAML (default: blackfly.yaml)',
      ),
      OpaqueFunction(function=launch_setup),
    ]
  )
