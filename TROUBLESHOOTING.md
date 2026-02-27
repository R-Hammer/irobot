# Troubleshooting: Carter Robot Teleop in Isaac Sim

## Problem

The Carter robot in the Isaac Sim warehouse scene cannot be controlled via `teleop_twist_keyboard` from the ROS2 container.

---

## Root Cause

Two issues prevented the Carter robot from being controlled via teleop:

1. **Physics simulation never starts** in Isaac Sim's streaming/WebRTC mode. The ROS2 bridge extension loads and registers topics, but `deltaTime` remains `0.000000` — the physics engine never ticks. NVIDIA's official examples use `SimulationContext.play()` in standalone Python scripts, not the UI Play button.

2. **FastDDS shared memory transport** blocks cross-container data flow. Even with `network_mode: host`, FastDDS defaults to shared memory transport for "local" participants. Docker containers have isolated `/dev/shm` namespaces, so DDS discovery works (multicast) but actual data transfer fails silently. The fix: set `FASTRTPS_DEFAULT_PROFILES_FILE` to a config that disables shared memory and forces UDP-only transport.

---

## What Was Investigated & Ruled Out

| # | Hypothesis | Result |
|---|-----------|--------|
| 1 | **Keyboard input not reaching teleop node** — original `bash -lc` wrapper swallowed raw keypresses | **Fixed** (use interactive shell), but robot still didn't move |
| 2 | **DDS/networking broken between containers** | **Was broken** — FastDDS shared memory transport doesn't work across Docker containers. Fixed with UDP-only transport profile |
| 3 | **ROS2 bridge not loaded** | **Working** — `isaacsim.ros2.bridge-4.12.4` with Jazzy libs confirmed loaded |
| 4 | **Timeline play via Script Editor** | `omni.timeline.get_timeline_interface().play()` and async stop/play both executed in WebRTC Script Editor but physics stayed at `deltaTime=0` |
| 5 | **Kit REST API for simulation control** | Port 8011 only has `/status`, `/health`, `/v1/streaming/*` — no simulation control endpoints |

**Conclusion:** The streaming Kit app's OmniGraph ticks but physics never properly initializes when loading a scene through the WebRTC Content Browser. NVIDIA's official examples use `SimulationContext.play()` in standalone Python scripts, not the UI Play button.

---

## Changes Made

### 1. `docker-compose.yml` — Added `isaac-headless` service

A new service (profile: `headless`) that overrides the container entrypoint to run `/isaac-sim/python.sh /shared/carter_headless.py` directly, bypassing the streaming app entirely.

### 2. `docker-compose.yml` — Added FastDDS UDP-only transport

Both `isaac-headless` and `ros2` services now set `FASTRTPS_DEFAULT_PROFILES_FILE=/shared/fastdds_no_shm.xml` to disable shared memory transport and force UDP, which works correctly across Docker container boundaries.

### 3. `shared/fastdds_no_shm.xml` — FastDDS transport profile

Configures FastDDS to use only UDPv4 transport, disabling the shared memory transport that causes silent data loss between containers.

### 4. `shared/carter_headless.py` — Standalone headless script

Loads the Carter warehouse scene, uses `SimulationContext` with `initialize_physics()` + `play()`, then loops `ctx.step(render=True)` to tick both physics and OmniGraph (ROS2 bridge publishers). Runs at ~62-75 fps.

### 5. `README.md` — Updated teleop instructions

Steps 5-7 updated to use an interactive shell (`docker compose exec ros2 bash`) instead of a single-line `bash -lc` command, so raw keyboard input works.

---

## Architecture

```
┌─────────────────────┐       ┌──────────────────┐
│  isaac-headless     │  DDS  │     ros2          │
│  (physics + bridge) │◄─────►│  (teleop_twist)   │
│  SimulationContext  │       │                   │
│  .play() + .step()  │ /cmd_vel, /clock, /odom   │
└─────────────────────┘       └──────────────────┘
   No UI, no streaming           keyboard input
```

---

## Current State (as of Feb 27, 2026)

- **WORKING END-TO-END** — Carter robot responds to `/cmd_vel` teleop commands.
- Physics runs at ~62-75 fps headless via `SimulationContext.step(render=True)`.
- `/clock` publishes simulation time, `/chassis/odom` publishes odometry data.
- Sending `linear.x=0.5` for 3 seconds moves the robot ~1.7 meters forward.
- FastDDS cross-container data flow fixed with UDP-only transport profile.
- Assets cached in `docker/isaac-sim/cache/` — second startup takes ~15-20 seconds.

---

## Quick Start

### 1. Start the headless simulation + ROS2 container

```bash
cd ~/isaac_ros_stack
docker compose --profile headless up -d ros2
docker compose --profile headless up -d isaac-headless
```

### 2. Wait for READY (check logs)

```bash
docker logs -f isaac-sim-headless 2>&1 | grep "\[carter\]"
```

Wait until you see `[carter] READY — robot listens on /cmd_vel`.

### 3. Verify data flow

```bash
docker compose exec ros2 bash -c 'source /opt/ros/jazzy/setup.bash && timeout 5 ros2 topic echo /clock --once'
```

If you see `sec:` / `nanosec:`, everything is working.

### 4. Run teleop

```bash
docker compose exec ros2 bash
# inside the container:
source /opt/ros/jazzy/setup.bash
ros2 run teleop_twist_keyboard teleop_twist_keyboard --ros-args -r cmd_vel:=/cmd_vel
```

Use `i/j/k/l` keys to drive.

### 5. Verify robot movement (separate terminal)

```bash
docker compose exec ros2 bash -c 'source /opt/ros/jazzy/setup.bash && ros2 topic echo /chassis/odom --once'
```

### 6. Stop everything

```bash
docker compose --profile headless down
```

---

## Key Technical Details

| Item | Value |
|------|-------|
| Isaac Sim version | 5.1.0 (`nvcr.io/nvidia/isaac-sim:5.1.0`) |
| Isaac Sim OS | Ubuntu 24.04 (Noble) |
| ROS2 distro | Jazzy |
| DDS implementation | `rmw_fastrtps_cpp` |
| DDS transport | UDP-only (`shared/fastdds_no_shm.xml`) — SHM disabled for cross-container compat |
| ROS domain ID | 0 |
| Network mode | `host` (both containers) |
| ROS2 bridge extension | `isaacsim.ros2.bridge-4.12.4` |
| Carter scene USD | `/Isaac/Samples/ROS2/Scenario/carter_warehouse_navigation.usd` |
| Headless entrypoint | `/isaac-sim/python.sh /shared/carter_headless.py` |
| Physics stepping | `SimulationContext.step(render=True)` at ~62-75 fps |
| Streaming entrypoint (broken for physics) | `/isaac-sim/runheadless.sh` → `kit ... isaacsim.exp.full.streaming.kit` |

---

## Useful Debug Commands

```bash
# List all ROS2 topics from Isaac Sim
docker compose exec ros2 bash -lc 'source /opt/ros/jazzy/setup.bash && ros2 topic list'

# Check if any data on a topic
docker compose exec ros2 bash -lc 'source /opt/ros/jazzy/setup.bash && timeout 5 ros2 topic hz /clock'

# View Isaac Sim logs
docker logs isaac-sim-headless 2>&1 | grep -i "carter\|error\|fatal\|READY"

# Stop everything
docker compose --profile headless down
```
