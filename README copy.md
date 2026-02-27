# Isaac Sim + ROS2 (Jazzy) Docker Setup

This workspace runs:
- `isaac` (Isaac Sim service used in all commands below)
- `ros2` (ROS2 Jazzy dev container)

---

## Which Isaac Sim mode should I use?

| Mode | Profile | When to use | Visual UI? | Physics? |
|------|---------|------------|-----------|----------|
| **Headless** | `headless` | Robot control via ROS2 (teleop, nav, SLAM). Best for development, CI, and when you don't need to see the scene. | No | Yes — runs at 60-75 fps |
| **WebRTC Streaming** | `webrtc` | You need to see/interact with the scene remotely (e.g., place objects, inspect robot visually). Connects via the Isaac Sim WebRTC Streaming Client. | Yes (remote) | Only if you press Play in the UI or use a script |
| **GUI** | `gui` | Local development on a machine with a display. Full Isaac Sim desktop UI. | Yes (local X11) | Only if you press Play |

### Rule of thumb

- **Just want the robot to move via ROS2?** → Use **headless**. It starts physics automatically, publishes all ROS2 topics, and has the lowest resource usage.
- **Need to see the warehouse / debug visually?** → Use **webrtc** (remote) or **gui** (local display).
- **Running in CI or automated tests?** → Use **headless**.

---

## Quick Start: Headless mode (recommended for teleop)

```bash
cd ~/isaac_ros_stack

# 1. Start both containers
docker compose --profile headless up -d ros2
docker compose --profile headless up -d isaac

# 2. Wait for READY (first run downloads assets ~2-5 min, subsequent runs ~20s)
docker compose logs -f isaac 2>&1 | grep "\[carter\]"
# Wait for: [carter] READY — robot listens on /cmd_vel. Ctrl+C to quit.

# 3. Verify data flows
docker compose exec ros2 bash -c 'source /opt/ros/jazzy/setup.bash && timeout 5 ros2 topic echo /clock --once'

# 4. Drive the robot
docker compose exec ros2 bash
# inside the container:
source /opt/ros/jazzy/setup.bash
ros2 run teleop_twist_keyboard teleop_twist_keyboard --ros-args -r cmd_vel:=/cmd_vel
# Use i/j/k/l keys to drive

# 5. Stop everything
docker compose --profile headless down
```

---

## Quick Start: WebRTC Streaming mode

```bash
cd ~/isaac_ros_stack

# 1. Set your server IP (reachable by the streaming client)
export PUBLIC_IP=<YOUR_SERVER_IP>

# 2. Start Isaac + ROS2
docker compose --profile webrtc up -d isaac ros2

# 3. Wait for Isaac to be ready
docker compose logs --no-color isaac | grep -E "app ready|Full Streaming App is loaded"

# 4. Connect with Isaac Sim WebRTC Streaming Client to <PUBLIC_IP>:49100

# 5. In the streamed UI, open a scene and press Play

# 6. Stop everything
docker compose --profile webrtc down
```

---

## Quick Start: GUI mode (local display)

```bash
cd ~/isaac_ros_stack

# 1. Allow X11 access
xhost +si:localuser:root

# 2. Start GUI + ROS2
docker compose --profile gui up -d isaac ros2

# 3. Isaac Sim desktop UI opens on your local display

# 4. Stop everything
docker compose --profile gui down
```

---

## Setup

### 1) Prerequisites

- Ubuntu host with NVIDIA driver + GPU working (`nvidia-smi`)
- Docker + Docker Compose plugin installed
- User in `docker` group
- NVIDIA Container Toolkit installed

### 2) First-time setup

From the project root:

```bash
cd /home/stu138438/isaac_ros_stack
chmod +x setup.sh
./setup.sh
```

This creates required bind-mount folders under `./docker/isaac-sim`.

### 3) Build/start base stack

```bash
docker compose up -d ros2
```

You can open a ROS2 shell with:

```bash
docker compose exec ros2 bash
```

---

## Current recommended path (2026)

Based on Isaac Sim 5.1 docs, this is the up-to-date setup for this repository:

- Use **Container installation** for remote/headless deployment.
- Use **Isaac Sim WebRTC Streaming Client** (desktop app) to connect to stream.
- Set `PUBLIC_IP` once per shell session and use stream port `49100`.
- Open network rules for `49100/tcp` and `47998/udp`.
- Wait for log line: `Isaac Sim Full Streaming App is loaded` before connecting.
- Use only one streaming method and one client per Isaac Sim instance.

Notes:
- Workstation install is still best for full local GUI development.
- Nucleus/Cache are not required to run Isaac Sim.
- Legacy Nucleus Cache is replaced by **Hub Workstation Cache** (optional performance add-on).

Official references:
- `https://docs.isaacsim.omniverse.nvidia.com/5.1.0/installation/install_workstation.html`
- `https://docs.isaacsim.omniverse.nvidia.com/5.1.0/installation/install_container.html`
- `https://docs.isaacsim.omniverse.nvidia.com/5.1.0/installation/manual_livestream_clients.html`
- `https://docs.omniverse.nvidia.com/utilities/latest/cache/hub-workstation.html`

---

## Operation Guides

### Headless streaming over VPN (remote WebRTC Streaming Client)

Use when client connects through VPN.

1. Find server IP reachable by your VPN client:

```bash
ip -4 -o addr show | awk '$2 !~ /^(lo|docker0|br-)/ {print $2, $4}'
```

Pick the interface/IP that your VPN client can reach.

2. Export it once in your current shell session:

```bash
export PUBLIC_IP=<SERVER_VPN_IP>
```

Example:

```bash
export PUBLIC_IP=141.83.113.173
```

3. Start Isaac + ROS2 with that exported value:

```bash
docker compose --profile webrtc up -d isaac ros2
```

4. Connect from client to:
- `<SERVER_VPN_IP>:49100`

5. Firewall/VPN rules:
- allow `49100/tcp`
- if stream connects but video fails, also allow stream UDP (commonly `47998/udp`)

---

## ROS2 + Isaac sanity checks

These checks use the Isaac service name `isaac`.

### 1) Container status

```bash
docker compose ps
```

### 2) ROS settings match between containers

```bash
docker compose exec -T isaac bash -lc 'echo isaac:$ROS_DOMAIN_ID:$RMW_IMPLEMENTATION'
docker compose exec -T ros2  bash -lc 'echo ros2:$ROS_DOMAIN_ID:$RMW_IMPLEMENTATION'
```

Expected: same `ROS_DOMAIN_ID` and `rmw_fastrtps_cpp`.

### 3) Built-in ROS2 bridge demo (clock)

Run inside Isaac container:

```bash
docker compose exec -T isaac bash -lc 'export ROS_DISTRO=jazzy; export RMW_IMPLEMENTATION=rmw_fastrtps_cpp; export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/isaac-sim/exts/isaacsim.ros2.bridge/jazzy/lib; ./python.sh /isaac-sim/standalone_examples/api/isaacsim.ros2.bridge/clock.py'
```

Then from ROS2 container check topics:

```bash
docker compose exec -T ros2 bash -lc 'source /opt/ros/jazzy/setup.bash; ros2 topic list | grep -E "sim_time|manual_time"'
```

Important:
- This demo publishes `sim_time` and `manual_time` (not `/clock`).

---

## Reference Commands

Start headless + ROS2:

```bash
docker compose --profile headless up -d isaac ros2
```

Stop all:

```bash
docker compose down
```

Follow logs:

```bash
docker compose logs -f isaac
```

Recreate containers after compose changes:

```bash
docker compose up -d --force-recreate
```

---

## Troubleshooting

- If Isaac fails at startup after edits, check:
  - `docker compose logs --no-color isaac | tail -n 200`
- If ROS2 demo cannot load bridge libs, ensure the demo command includes:
  - `ROS_DISTRO=jazzy`
  - `RMW_IMPLEMENTATION=rmw_fastrtps_cpp`
  - `LD_LIBRARY_PATH+=/isaac-sim/exts/isaacsim.ros2.bridge/jazzy/lib`
- If GUI doesn’t open:
  - run `xhost +si:localuser:root`
  - verify `DISPLAY` exists on host (`echo $DISPLAY`)
  - try Xorg session instead of Wayland

---

## VPN Quick Start: stream to VPN client

Use this when Isaac runs on the host and your WebRTC client is on another machine connected through VPN.

1. On host, get the VPN IP:

```bash
ip -4 -o addr show | awk '$2 !~ /^(lo|docker0|br-)/ {print $2, $4}'
```

- If Cisco/Forti exposes a tunnel interface, it may appear as `cscotun0`, `ppp0`, or `tun0`.
- If no tunnel interface appears, use the non-Docker host IP that is reachable from the VPN client.

2. Export the VPN IP once in your current shell session:

```bash
export PUBLIC_IP=<HOST_VPN_IP>
```

3. Start Isaac + ROS2 bound to that exported VPN IP:

```bash
docker compose --profile webrtc up -d isaac ros2
```

4. Verify Isaac is ready:

```bash
docker compose logs --no-color isaac | grep -E "app ready|Full Streaming App is loaded"
```

5. On the VPN client machine, open **Isaac Sim WebRTC Streaming Client** and connect:
  - Server: the exported `PUBLIC_IP`
  - Port: `49100`

6. If connection fails, check:
  - VPN routes allow client -> `PUBLIC_IP`
  - host firewall allows `49100/tcp`
  - if connected but no video, allow `47998/udp`

Quick connectivity check from client:

```bash
nc -vz <HOST_VPN_IP> 49100
```

---

### Keyboard robot demo (headless — recommended)

This is the simplest way to drive the Carter robot. No UI needed.

1. Start headless simulation + ROS2:

```bash
docker compose --profile headless up -d ros2
docker compose --profile headless up -d isaac
```

2. Wait until physics is ready:

```bash
docker compose logs -f isaac 2>&1 | grep "\[carter\]"
```

Wait for `[carter] READY`. Press Ctrl+C to stop following logs.

3. Verify `/clock` is publishing:

```bash
docker compose exec ros2 bash -c 'source /opt/ros/jazzy/setup.bash && timeout 5 ros2 topic echo /clock --once'
```

4. Open an interactive shell in the ROS2 container and run teleop:

```bash
docker compose exec ros2 bash
```

Then inside the container:

```bash
source /opt/ros/jazzy/setup.bash
ros2 run teleop_twist_keyboard teleop_twist_keyboard --ros-args -r cmd_vel:=/cmd_vel
```

> **Important:** Do NOT run teleop via `docker compose exec ros2 bash -lc '...'` in a single
> command. The login-shell wrapper prevents raw keyboard input from reaching the teleop node,
> so keypresses are silently dropped. You must exec into the container first, then launch teleop.

5. Use keyboard in that terminal (`i`, `j`, `l`, `,`, `k`) to drive. Verify movement in another terminal:

```bash
docker compose exec ros2 bash -c 'source /opt/ros/jazzy/setup.bash && ros2 topic echo /chassis/odom --once'
```

6. Stop:

```bash
docker compose --profile headless down
```

---

### Keyboard robot demo over WebRTC (visual)

1. Start Isaac headless streaming + ROS2:

```bash
docker compose --profile webrtc up -d isaac ros2
```

2. Wait until Isaac is ready:

```bash
docker compose logs --no-color isaac | grep -E "app ready|Full Streaming App is loaded|isaacsim.ros2.bridge"
```

3. On the VPN client machine, open **Isaac Sim WebRTC Streaming Client** and connect to:
  - Server: the exported `PUBLIC_IP`
  - Port: `49100`

If you cannot install system-wide, run the AppImage in your home folder (no root):

```bash
chmod +x IsaacSimWebRTCStreamingClient*.AppImage
./IsaacSimWebRTCStreamingClient*.AppImage
```

4. In the streamed Isaac UI, open this sample scene in the bottom scene browser:
  - `/Isaac/Samples/ROS2/Scenario/carter_warehouse_navigation.usd`
  - Press **Play** in Isaac Sim.

5. In ROS2 container, install teleop (one-time):

```bash
docker compose exec ros2 bash -lc 'apt-get update && apt-get install -y ros-jazzy-teleop-twist-keyboard'
```

6. Open an interactive shell in the ROS2 container and run teleop from inside:

```bash
docker compose exec ros2 bash
```

Then inside the container:

```bash
source /opt/ros/jazzy/setup.bash
ros2 run teleop_twist_keyboard teleop_twist_keyboard --ros-args -r cmd_vel:=/cmd_vel
```

> **Important:** Do NOT run teleop via `docker compose exec ros2 bash -lc '...'` in a single
> command. The login-shell wrapper prevents raw keyboard input from reaching the teleop node,
> so keypresses are silently dropped. You must exec into the container first, then launch teleop.

7. Use keyboard in that terminal (`i`, `j`, `l`, `,`, `k`) and watch Carter move in the streamed viewport.
