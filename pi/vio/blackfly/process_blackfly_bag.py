#!/usr/bin/env python3
"""Trim tail from a rosbag2 bag and write a 1-in-N subsampled copy."""
from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

from rosbag2_py import (
  ConverterOptions,
  SequentialReader,
  SequentialWriter,
  StorageOptions,
  TopicMetadata,
)


def open_reader(uri: str) -> SequentialReader:
  reader = SequentialReader()
  reader.open(
    StorageOptions(uri=uri, storage_id='sqlite3'),
    ConverterOptions('', ''),
  )
  return reader


def open_writer(uri: str, topics) -> SequentialWriter:
  out = Path(uri)
  if out.exists():
    shutil.rmtree(out)

  writer = SequentialWriter()
  writer.open(
    StorageOptions(uri=uri, storage_id='sqlite3'),
    ConverterOptions('', ''),
  )
  for topic in topics:
    writer.create_topic(
      TopicMetadata(
        name=topic.name,
        type=topic.type,
        serialization_format=topic.serialization_format,
        offered_qos_profiles=getattr(topic, 'offered_qos_profiles', ''),
      )
    )
  return writer


def bag_time_bounds(reader: SequentialReader) -> tuple[int, int]:
  meta = reader.get_metadata()
  start = meta.starting_time.nanoseconds
  duration = meta.duration.nanoseconds
  return start, start + duration


def process_bag(
  src: str,
  trim_tail_s: float,
  subsample_every: int,
  trimmed_uri: str | None,
  subsampled_uri: str | None,
) -> None:
  reader = open_reader(src)
  topics = reader.get_all_topics_and_types()
  start_ns, end_ns = bag_time_bounds(reader)
  cutoff_ns = end_ns - int(trim_tail_s * 1e9)

  trimmed_writer = (
    open_writer(trimmed_uri, topics) if trimmed_uri else None
  )
  subsampled_writer = (
    open_writer(subsampled_uri, topics) if subsampled_uri else None
  )

  kept = 0
  written_sub = 0
  total = 0
  while reader.has_next():
    topic, data, timestamp = reader.read_next()
    total += 1
    if timestamp >= cutoff_ns:
      continue

    kept += 1
    if trimmed_writer is not None:
      trimmed_writer.write(topic, data, timestamp)

    if subsampled_writer is not None and (kept - 1) % subsample_every == 0:
      subsampled_writer.write(topic, data, timestamp)
      written_sub += 1

    if total % 200 == 0:
      print(
        f'  read {total}, kept {kept}, subsampled {written_sub}',
        flush=True,
      )

  if trimmed_writer is not None:
    trimmed_writer.close()
  if subsampled_writer is not None:
    subsampled_writer.close()

  trim_min = trim_tail_s / 60.0
  print(f'Source messages:     {total}')
  print(f'After trim ({trim_min:.1f} min tail removed): {kept}')
  if subsampled_writer is not None:
    print(f'Subsampled (1/{subsample_every}): {written_sub}')
  if trimmed_uri:
    print(f'Trimmed bag:     {trimmed_uri}')
  if subsampled_uri:
    print(f'Subsampled bag:  {subsampled_uri}')


def main() -> int:
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument('bag_dir', help='Input rosbag2 directory')
  parser.add_argument(
    '--trim-tail-s',
    type=float,
    default=120.0,
    help='Seconds to remove from end of bag (default: 120)',
  )
  parser.add_argument(
    '--subsample-every',
    type=int,
    default=5,
    help='Keep 1 message every N from trimmed bag (default: 5)',
  )
  parser.add_argument(
    '--trimmed-out',
    help='Output directory for trimmed bag (default: <bag>_trimmed)',
  )
  parser.add_argument(
    '--subsampled-out',
    help='Output directory for subsampled bag (default: <bag>_sub1of5)',
  )
  parser.add_argument('--trim-only', action='store_true')
  parser.add_argument('--subsample-only', action='store_true')
  args = parser.parse_args()

  src = str(Path(args.bag_dir).expanduser().resolve())
  if not Path(src).is_dir():
    print(f'Not a directory: {src}', file=sys.stderr)
    return 1

  trimmed_uri = None
  subsampled_uri = None
  if not args.subsample_only:
    trimmed_uri = args.trimmed_out or f'{src}_trimmed'
  if not args.trim_only:
    subsampled_uri = args.subsampled_out or (
      f'{src}_sub1of{args.subsample_every}'
    )

  print(f'Processing: {src}')
  print(f'  trim tail: {args.trim_tail_s}s')
  print(f'  subsample: 1/{args.subsample_every}')
  process_bag(
    src,
    args.trim_tail_s,
    args.subsample_every,
    trimmed_uri,
    subsampled_uri,
  )
  return 0


if __name__ == '__main__':
  sys.exit(main())
