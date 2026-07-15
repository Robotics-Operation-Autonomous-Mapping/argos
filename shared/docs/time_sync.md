# Time synchronization

Bags and multi-sensor SLAM are only as good as clock agreement across
**Pi A (lidar)**, **Pi B (VIO)**, and the **laptop**. ARGOS assumes
**system clocks are synchronized**; ROS message headers use those clocks.

## Default: chrony (NTP)

Recommended for Pi↔Pi↔laptop on a LAN without PTP hardware.

1. Pick an NTP source (often the laptop, or a house NTP/router).
2. On each Pi (and optionally the laptop if it is not already NTP-synced):

```bash
# from a checkout that includes shared/
./shared/scripts/setup_chrony.sh
# or pass the server explicitly:
CHRONY_NTP_SERVER=192.168.1.60 ./shared/scripts/setup_chrony.sh
```

3. Verify:

```bash
chronyc tracking
chronyc sources -v
# offset should settle well under ~10 ms on a quiet LAN
```

Keep chrony running at boot (`systemd`). Re-check after long power-offs.

## Optional: PTP

If switches/NICs support hardware or software PTP (`linuxptp`), you can
tighten sync further. Only pursue this after chrony is stable; document your
grandmaster hostname in the host wiki. ARGOS does not require PTP.

## ROS / bags rules

| Mode | Clocks |
|------|--------|
| **Live multi-host** | Real synchronized system time on every node. `use_sim_time:=false`. |
| **Bag playback** | `use_sim_time:=true` on consumers; `ros2 bag play … --clock`. Do not mix live Pi clocks with sim time. |

Record bags with hosts already chrony-synced so inter-bag and multi-host
replay stay alignable.

## Approximate tolerances (guidance)

| Use | Rough sync you want |
|-----|---------------------|
| OpenVINS mono+IMU alone (cam+IMU on one Pi) | Mostly local; still sync Pi↔laptop for monitoring bags |
| Later RTABMAP image + external `/odom` on VIO Pi | Local sensors dominant |
| Lidar scan fusion with VIO odom / camera over DDS | Prefer **&lt; 5–10 ms** skew Pi↔Pi; **&gt;50 ms** often hurts scan matching / LC association |
| Offline bag analysis | Prefer recorded timestamps from sync'd hosts; use sim time on playback |

These are engineering guidelines, not hard OpenVINS limits. Tighten before
enabling `subscribe_scan` in RTABMAP.
