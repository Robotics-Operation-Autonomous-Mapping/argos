# Time synchronization

Bags and multi-sensor SLAM are only as good as clock agreement across
**Pi A (lidar)**, **Pi B (VIO)**, and the **laptop**. ARGOS assumes
**system clocks are synchronized**; ROS message headers use those clocks.

## Cam ↔ IMU is already same-clock (important)

On **Pi B** the **Blackfly camera and the ICM-20948 IMU share ONE system clock**
— every `/blackfly/image_raw` and `/imu/data_raw` stamp comes from the same host.
So the **cam–IMU time relationship is a single-clock problem**: any residual bias
is a fixed sensor/driver latency absorbed by Kalibr `timeshift_cam_imu` /
OpenVINS `calib_cam_timeoffset`, **not** an NTP problem. chrony does **not** affect
cam↔IMU sync.

chrony matters for the **cross-host** relationships instead: Pi B's VIO odom vs
**Pi A's lidar** and vs the **laptop** (monitoring / bag replay). Those hosts have
independent clocks and must be disciplined to a common source.

## Default: chrony (NTP)

Recommended for Pi↔Pi↔laptop on a LAN without PTP hardware. One host is the shared
time source `CHRONY_NTP_SERVER` (default = `LAPTOP_IP`); the others are clients.

`shared/scripts/setup_chrony.sh` auto-detects the role from this host's IP:

* If the host's IP **is** `CHRONY_NTP_SERVER` → configured as the **NTP server**
  (serves the LAN via `allow <subnet>` + `local stratum 10`, so it works even with
  no internet). Keep any upstream pool in `/etc/chrony/chrony.conf` for real time.
* Otherwise → configured as a **client** of that server (`server … iburst prefer`,
  fast `makestep` so bag stamps line up quickly).

Set the source once in `.env` (all hosts share the same value):

```bash
# shared/.env.example
CHRONY_NTP_SERVER=192.168.1.60   # = LAPTOP_IP on the current LAN
PI_LIDAR_IP=192.168.1.51         # Pi A
PI_VIO_IP=192.168.1.52           # Pi B
LAPTOP_IP=192.168.1.60
```

Then, on **every** host (server first, then the Pis) — on the HOST, not in Docker:

```bash
# from a checkout that includes shared/ (reads CHRONY_NTP_SERVER from .env):
sudo ./shared/scripts/setup_chrony.sh
# or pass it explicitly / force a role:
CHRONY_NTP_SERVER=192.168.1.60 sudo ./shared/scripts/setup_chrony.sh
ROLE=server sudo ./shared/scripts/setup_chrony.sh
```

Keep chrony running at boot (`systemd`). Re-check after long power-offs.

## Verify (run on ALL hosts)

The setup script ends by verifying; re-run the check any time (no root needed):

```bash
./shared/scripts/setup_chrony.sh --verify
```

It prints and grades the sync:

```bash
chronyc tracking     # Reference ID + "Last offset" (should be small & stable)
chronyc sources -v   # '^*' marks the selected source = CHRONY_NTP_SERVER on clients
```

The `--verify` clause extracts `|Last offset|` and grades it against
`OFFSET_WARN_MS` (default 10) and `OFFSET_FAIL_MS` (default 50). All three hosts
must track the **same** reference and settle under the warn threshold before you
trust cross-host lidar+VIO fusion.

Acceptance (cross-host, for VIO ↔ lidar fusion):

| Measured `|Last offset|` | Meaning |
|---|---|
| **< 10 ms** | Good — safe for lidar+VIO fusion / multi-host replay. |
| 10–50 ms | Marginal — OK for monitoring; tighten before `RTABMAP_USE_LIDAR=true`. |
| **> 50 ms** | Bad — scan-matching / loop-closure association degrades. Fix first. |

## Optional: PTP

If switches/NICs support hardware or software PTP (`linuxptp`), you can
tighten sync further. Only pursue this after chrony is stable; document your
grandmaster hostname in the host wiki. ARGOS does not require PTP.

## ROS / bags rules

| Mode | Clocks |
|------|--------|
| **Live multi-host** | Real synchronized system time on every node. `use_sim_time:=false`. |
| **Bag playback** | `use_sim_time:=true` on consumers; `ros2 bag play … --clock`. Do not mix live Pi clocks with sim time. |

Record bags with hosts already chrony-synced (verify green first) so inter-bag and
multi-host replay stay alignable.

## Approximate tolerances (guidance)

| Use | Rough sync you want |
|-----|---------------------|
| OpenVINS mono+IMU alone (cam+IMU on one Pi) | Same-clock — chrony irrelevant; still sync Pi↔laptop for monitoring bags |
| Later RTABMAP image + external `/odom` on VIO Pi | Local sensors dominant |
| Lidar scan fusion with VIO odom / camera over DDS | Prefer **< 5–10 ms** skew Pi↔Pi; **>50 ms** often hurts scan matching / LC association |
| Offline bag analysis | Prefer recorded timestamps from sync'd hosts; use sim time on playback |

These are engineering guidelines, not hard OpenVINS limits. Tighten before
enabling `subscribe_scan` in RTABMAP.
