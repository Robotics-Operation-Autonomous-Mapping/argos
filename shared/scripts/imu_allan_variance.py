#!/usr/bin/env python3
"""Compute IMU noise densities and random walks (Kalibr format) from a static bag.

Reads a rosbag2 (.db3 sqlite3 or .mcap) of a long, perfectly still IMU recording
and estimates the overlapping Allan deviation for each gyro/accel axis. From the
curve it extracts:

  * noise_density  = white-noise coefficient N  (Allan dev at tau = 1 s, -1/2 slope)
  * random_walk    = bias random-walk coeff  K  (+1/2 slope line, evaluated at tau = 3 s)

These map directly onto Kalibr's `*_noise_density` / `*_random_walk` fields used by
OpenVINS (shared/config/openvins/kalibr_imu_chain.yaml.template).

Usage:
  python3 imu_allan_variance.py <bag_dir> [--topic /imu/data] [--out imu_allan.yaml]

<bag_dir> is the directory that contains metadata.yaml + the .db3/.mcap files.

Requires: pip install rosbags numpy   (no ROS installation needed)
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np

try:
    from rosbags.highlevel import AnyReader
except Exception as exc:  # pragma: no cover
    sys.exit(f"Need the 'rosbags' package (pip install rosbags): {exc}")


def read_imu(bag_dir: Path, topic: str):
    """Return (t, gyro[N,3], accel[N,3]) from the given IMU topic."""
    t, gyro, accel = [], [], []
    with AnyReader([bag_dir]) as reader:
        conns = [c for c in reader.connections if c.topic == topic]
        if not conns:
            avail = sorted({c.topic for c in reader.connections})
            sys.exit(f"Topic '{topic}' not found. Available: {avail}")
        for conn, timestamp, raw in reader.messages(connections=conns):
            m = reader.deserialize(raw, conn.msgtype)
            t.append(timestamp * 1e-9)
            g = m.angular_velocity
            a = m.linear_acceleration
            gyro.append((g.x, g.y, g.z))
            accel.append((a.x, a.y, a.z))
    return np.asarray(t), np.asarray(gyro), np.asarray(accel)


def overlapping_adev(x: np.ndarray, fs: float, num_taus: int = 60):
    """Overlapping Allan deviation of rate data x sampled at fs (Hz).

    Returns (taus[s], adev). Uses the cumulative-angle formulation:
      sigma^2(tau) = 1 / (2 tau^2 (N-2m)) * sum (theta[k+2m] - 2 theta[k+m] + theta[k])^2
    """
    n = x.size
    dt = 1.0 / fs
    theta = np.concatenate(([0.0], np.cumsum(x) * dt))  # angle, length n+1
    max_m = (n - 1) // 2
    ms = np.unique(np.floor(np.logspace(0, np.log10(max_m), num_taus)).astype(int))
    ms = ms[ms >= 1]
    taus, adev = [], []
    for m in ms:
        # theta indices 0..n; need k in [0, n-2m)
        d = theta[2 * m:] - 2.0 * theta[m:-m] + theta[:-2 * m]
        tau = m * dt
        var = np.sum(d * d) / (2.0 * tau * tau * d.size)
        taus.append(tau)
        adev.append(np.sqrt(var))
    return np.asarray(taus), np.asarray(adev)


def fixed_slope_intercept(taus, adev, slope, tau_lo, tau_hi):
    """Fit y = c + slope*x in log10 space over [tau_lo, tau_hi]; return c (log10 intercept)."""
    mask = (taus >= tau_lo) & (taus <= tau_hi)
    if mask.sum() < 2:
        return None
    x = np.log10(taus[mask])
    y = np.log10(adev[mask])
    c = np.mean(y - slope * x)
    return c


def coeffs_from_adev(taus, adev):
    """Extract noise density (N @ tau=1, slope -1/2) and random walk (K @ tau=3, slope +1/2)."""
    tau_max = taus[-1]
    # White noise: short-tau region, slope -1/2.
    c_wn = fixed_slope_intercept(taus, adev, -0.5, 0.02, 0.5)
    if c_wn is None:
        c_wn = fixed_slope_intercept(taus, adev, -0.5, taus[0], taus[0] * 10)
    N = 10 ** (c_wn + (-0.5) * np.log10(1.0))  # value of the -1/2 line at tau = 1 s

    # Random walk: long-tau region, slope +1/2.
    lo = max(0.1 * tau_max, 50.0)
    c_rw = fixed_slope_intercept(taus, adev, 0.5, lo, tau_max)
    if c_rw is None:
        c_rw = fixed_slope_intercept(taus, adev, 0.5, 0.3 * tau_max, tau_max)
    K = 10 ** (c_rw + 0.5 * np.log10(3.0))  # +1/2 line evaluated at tau = 3 s
    return float(N), float(K)


def analyse(name, data, fs):
    dens, rw = [], []
    for axis in range(3):
        taus, adev = overlapping_adev(data[:, axis], fs)
        N, K = coeffs_from_adev(taus, adev)
        dens.append(N)
        rw.append(K)
        print(f"  {name}[{'xyz'[axis]}]  noise_density={N:.6e}  random_walk={K:.6e}")
    return float(np.mean(dens)), float(np.mean(rw))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bag_dir", type=Path, help="dir with metadata.yaml + .db3/.mcap")
    ap.add_argument("--topic", default="/imu/data", help="raw IMU topic")
    ap.add_argument("--out", type=Path, default=None, help="write Kalibr imu yaml snippet")
    args = ap.parse_args()

    print(f"Reading {args.topic} from {args.bag_dir} ...")
    t, gyro, accel = read_imu(args.bag_dir, args.topic)
    dur = t[-1] - t[0]
    fs = (len(t) - 1) / dur
    print(f"samples={len(t)}  duration={dur:.1f}s ({dur/3600:.2f}h)  rate={fs:.2f} Hz\n")

    print("Gyroscope [rad/s]:")
    g_nd, g_rw = analyse("gyro", gyro, fs)
    print("Accelerometer [m/s^2]:")
    a_nd, a_rw = analyse("accel", accel, fs)

    print("\n--- Kalibr imu0 values (axis-averaged) ---")
    print(f"gyroscope_noise_density:     {g_nd:.6e}")
    print(f"gyroscope_random_walk:       {g_rw:.6e}")
    print(f"accelerometer_noise_density: {a_nd:.6e}")
    print(f"accelerometer_random_walk:   {a_rw:.6e}")
    print(f"update_rate:                 {fs:.1f}")

    if args.out:
        args.out.write_text(
            "%YAML:1.0\n"
            "imu0:\n"
            f"  accelerometer_noise_density: {a_nd:.6e}\n"
            f"  accelerometer_random_walk: {a_rw:.6e}\n"
            f"  gyroscope_noise_density: {g_nd:.6e}\n"
            f"  gyroscope_random_walk: {g_rw:.6e}\n"
            f"  rostopic: {args.topic}\n"
            f"  update_rate: {fs:.1f}\n"
        )
        print(f"\nWrote {args.out}")


if __name__ == "__main__":
    main()
