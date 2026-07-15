# ARGOS laptop (amd64)

Pull **shared + laptop** only — no Pi Docker contexts required on day-to-day runs
(build context needs `argos/shared` + `argos/laptop` from repo root).

## Sparse-checkout

```bash
git sparse-checkout init --cone
git sparse-checkout set argos/README.md argos/LICENSE argos/shared argos/laptop
```

## Roles

| Mode | What |
|------|------|
| **Live map showcase** | Join CycloneDDS domain; Foxglove / RViz on **whitelisted** topics (odom, map, compressed scan/cloud). Laptop **subscribes** — no Pi forward. Do **not** pull raw Blackfly + 2× Vivotek live. |
| **Offline COLMAP** | Reconstruct from Vivotek bags (Pi B is 32 GB / lean — pull bags from Pi B or from Pi A’s 256 GB staging via rsync). COLMAP compute is here. |
| **Align** | CloudCompare: COLMAP sparse/dense ↔ RTABMAP / lidar cloud using bag `/tf` + `OV_ODOM_TOPIC`. |
| **Bag review** | Foxglove Studio on mcap/db3 bags (host or `playback` profile). |

## Configure

```bash
cp shared/.env.example laptop/.env
# Set PI_LIDAR_IP, PI_VIO_IP, LAPTOP_IP to match the Pis
# Prefer chrony on the laptop if it is the NTP source for the Pis
```

## Live showcase

```bash
cd laptop
./scripts/build.sh
./scripts/run.sh monitor           # RViz on multi-Pi domain (use_sim_time=false)
```

Foxglove: connect to `ws://<PI_LIDAR_IP>:8765` (mapper bridge) or
`ws://<PI_VIO_IP>:8765` (lightweight VIO bridge). Prefer the lidar Pi when
RTABMAP runs there. Topic whitelist idea — odom / map / scan / cloud / tf —
**not** three raw camera streams.

Preferred field stack: OpenVINS on Pi B, **RTABMAP on Pi A**, laptop subscribe-only.

## Offline COLMAP + lidar align

1. Copy COLMAP session bags from Pi B (`VIVOTEK_*` + `/tf` + odom).
2. Install host tools (not in Docker):

```bash
sudo apt install colmap cloudcompare   # availability varies
```

3. Extract images (at `COLMAP_IMAGE_RATE_HZ` or subsample), run COLMAP.
4. Export RTABMAP / lidar cloud (PCD/PLY) from the mapping session.
5. In CloudCompare, align COLMAP model to the lidar/RTABMAP cloud (shared
   landmarks / manual ICP; use bag poses as a prior when helpful).
6. Re-open bags in Foxglove for timeline QA.

## Docker profiles

```bash
./scripts/run.sh monitor
./scripts/run.sh playback /data/bags/<bag>    # use_sim_time + --clock
./scripts/run.sh analysis                     # Jupyter :8888
```

## Notes

- Live: same `ROS_DOMAIN_ID` + CycloneDDS peers as both Pis; `use_sim_time=false`.
- Playback: `USE_SIM_TIME=true` and `ros2 bag play --clock` only.
- Optional `PLAYBACK_RUN_OPENVINS=true` re-runs VIO from Blackfly+IMU in the bag.
- Alternatives: live RTABMAP on this laptop (max Pi headroom, needs good Wi‑Fi).
