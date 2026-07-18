#!/usr/bin/env python3
"""Publish GigE Blackfly stream (Aravis + GStreamer) to ROS 2."""
from __future__ import annotations

import argparse
import queue
import sys

import gi

gi.require_version('Gst', '1.0')
from gi.repository import Gst, GLib  # noqa: E402

import rclpy
from rclpy.node import Node
from sensor_msgs.msg import Image


class AravisRos2Publisher(Node):
  def __init__(self, topic: str, frame_id: str, node_name: str):
    super().__init__(node_name)
    self.publisher = self.create_publisher(Image, topic, 10)
    self.frame_id = frame_id
    self.frame_count = 0
    self.pending: queue.Queue[Image] = queue.Queue(maxsize=4)

  def enqueue_sample(self, sample) -> int:
    buffer = sample.get_buffer()
    caps = sample.get_caps().get_structure(0)
    width = int(caps.get_value('width'))
    height = int(caps.get_value('height'))
    ok, map_info = buffer.map(Gst.MapFlags.READ)
    if not ok:
      self.get_logger().warn('failed to map GStreamer buffer')
      return Gst.FlowReturn.ERROR

    msg = Image()
    msg.header.stamp = self.get_clock().now().to_msg()
    msg.header.frame_id = self.frame_id
    msg.height = height
    msg.width = width
    msg.encoding = 'rgb8'
    msg.is_bigendian = 0
    msg.step = width * 3
    msg.data = bytes(map_info.data)
    buffer.unmap(map_info)

    try:
      self.pending.put_nowait(msg)
    except queue.Full:
      pass
    return Gst.FlowReturn.OK

  def flush_pending(self) -> None:
    while not self.pending.empty():
      msg = self.pending.get_nowait()
      self.publisher.publish(msg)
      self.frame_count += 1
    if self.frame_count and self.frame_count % 30 == 0:
      self.get_logger().info(f'published {self.frame_count} frames')


def on_new_sample(sink, node: AravisRos2Publisher):
  sample = sink.emit('pull-sample')
  if sample is None:
    return Gst.FlowReturn.ERROR
  return node.enqueue_sample(sample)


def main() -> int:
  parser = argparse.ArgumentParser()
  parser.add_argument('--camera', required=True)
  parser.add_argument('--packet-size', type=int, default=1400)
  parser.add_argument('--topic', default='/blackfly/image_raw')
  parser.add_argument('--frame-id', default='blackfly_optical_frame')
  parser.add_argument('--pixel-format', default='BayerRG8', choices=['BayerRG8', 'Mono8'])
  parser.add_argument('--node-name', default='aravis_ros2_publisher')
  parser.add_argument('--saturation', type=float, default=1.0)
  parser.add_argument('--hue', type=float, default=0.0)
  parser.add_argument(
    '--preview',
    action='store_true',
    help='Open Aravis/GStreamer live preview window (same pipeline as bag)',
  )
  args = parser.parse_args()

  Gst.init(None)
  rclpy.init()
  node = AravisRos2Publisher(args.topic, args.frame_id, args.node_name)

  if args.pixel_format == 'Mono8':
    source_tail = 'videoconvert'
  else:
    source_tail = (
      f'bayer2rgb ! videoconvert ! videobalance saturation={args.saturation} '
      f'hue={args.hue}'
    )

  if args.preview:
    sink_branch = (
      'tee name=t '
      't. ! queue max-size-buffers=2 leaky=downstream ! autovideosink sync=false '
      't. ! queue max-size-buffers=2 leaky=downstream ! videoconvert ! '
      'video/x-raw,format=RGB ! appsink name=sink emit-signals=true sync=false '
      'max-buffers=2 drop=true'
    )
  else:
    sink_branch = (
      'videoconvert ! video/x-raw,format=RGB ! appsink name=sink emit-signals=true '
      'sync=false max-buffers=2 drop=true'
    )

  pipeline = Gst.parse_launch(
    f'aravissrc camera-name="{args.camera}" packet-size={args.packet_size} '
    f'auto-packet-size=false packet-resend=true ! {source_tail} ! {sink_branch}'
  )
  sink = pipeline.get_by_name('sink')
  sink.connect('new-sample', on_new_sample, node)

  loop = GLib.MainLoop()
  bus = pipeline.get_bus()
  bus.add_signal_watch()

  def on_message(_bus, message, _loop):
    if message.type == Gst.MessageType.ERROR:
      err, debug = message.parse_error()
      node.get_logger().error(f'GStreamer error: {err} ({debug})')
      _loop.quit()
    elif message.type == Gst.MessageType.EOS:
      node.get_logger().info('GStreamer EOS')
      _loop.quit()

  bus.connect('message', on_message, loop)

  pipeline.set_state(Gst.State.PLAYING)
  node.get_logger().info(
    f'streaming {args.camera} -> {args.topic} (packet-size={args.packet_size}'
    f'{", preview=on" if args.preview else ""})'
  )

  try:
    while rclpy.ok():
      node.flush_pending()
      rclpy.spin_once(node, timeout_sec=0.0)
      while GLib.main_context_default().iteration(False):
        pass
  except KeyboardInterrupt:
    pass
  finally:
    pipeline.set_state(Gst.State.NULL)
    node.destroy_node()
    if rclpy.ok():
      rclpy.shutdown()

  return 0


if __name__ == '__main__':
  sys.exit(main())
