#!/usr/bin/env python3
"""Keep every Nth message from a ROS1 bag (for lighter Kalibr runs)."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from rosbags.rosbag1 import Reader, Writer
from rosbags.typesys import Stores, get_typestore


def main() -> int:
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument('src_bag', help='Input .bag (ROS1)')
  parser.add_argument('dst_bag', help='Output .bag (ROS1)')
  parser.add_argument('--every', type=int, default=10, help='Keep 1 of every N frames')
  parser.add_argument('--topic', default='/cam_0/image_raw')
  args = parser.parse_args()

  src = Path(args.src_bag).expanduser().resolve()
  dst = Path(args.dst_bag).expanduser().resolve()
  if not src.is_file():
    print(f'Not found: {src}', file=sys.stderr)
    return 1
  if dst.exists():
    dst.unlink()

  typestore = get_typestore(Stores.ROS1_NOETIC)
  kept = 0
  total = 0
  with Reader(src) as reader, Writer(dst) as writer:
    connmap = {}
    for conn in reader.connections:
      ext = conn.ext
      wconn = writer.add_connection(
        conn.topic,
        conn.msgtype,
        latching=ext.latching if ext else 0,
        callerid=ext.callerid if ext else None,
        msgdef=conn.msgdef,
      )
      connmap[conn.id] = wconn
    for conn, timestamp, raw in reader.messages():
      if conn.topic != args.topic:
        writer.write(connmap[conn.id], timestamp, raw)
        continue
      total += 1
      if (total - 1) % args.every != 0:
        continue
      writer.write(connmap[conn.id], timestamp, raw)
      kept += 1

  print(f'Wrote {kept} / {total} frames -> {dst}')
  return 0


if __name__ == '__main__':
  sys.exit(main())
