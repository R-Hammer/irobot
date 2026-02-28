# Isaac Sim WebRTC How-To (Simplified)

Run from:

```bash
cd ~/isaac_ros_stack
```

## 1) Set VPN/host IP for WebRTC

Find reachable host IPs:

```bash
ip -4 -o addr show | awk '$2 !~ /^(lo|docker0|br-)/ {print $2, $4}'
```

Set the one your client can reach (VPN IP if available):

```bash
export PUBLIC_IP=<YOUR_REACHABLE_HOST_IP>
export PUBLIC_IP=141.83.113.173
echo "$PUBLIC_IP"
```

## 2) Start required services (always first)

```bash
docker compose --profile webrtc up -d --build isaac-webrtc ros2-isaac
docker compose ps
docker compose logs --no-color isaac-webrtc | grep -E "app ready|Full Streaming App is loaded"
```

Why:
- `isaac-webrtc` provides the stream.
- `ros2-isaac` runs ROS nodes (teleop, wall-follow, SLAM).

Connect WebRTC client to:
- Server: `PUBLIC_IP`
- Port: `49100`

## 3) Load scene and press Play

### Option A: in WebRTC UI

Open:

```text
/Isaac/Samples/ROS2/Scenario/carter_warehouse_navigation.usd
```

Then press **Play**.

### Option B: CLI auto-load + auto-Play (optional)

This keeps your default startup unchanged, and only recreates `isaac-webrtc` when you want scene auto-load.

```bash
docker compose -f docker-compose.yml -f docker-compose.webrtc.scene.yml up -d --force-recreate --no-deps isaac-webrtc
docker compose logs --no-color isaac-webrtc | grep -E "auto_open_play|app ready|Full Streaming App is loaded"
```

## 4) Move robot

Robot stays idle until something publishes `/cmd_vel`.

### 4.1 Teleop keyboard (manual)

One-time install:

```bash
docker compose exec ros2-isaac bash -lc 'apt-get update && apt-get install -y ros-jazzy-teleop-twist-keyboard'
```

Run teleop:

```bash
docker compose exec ros2-isaac bash -lc 'source /opt/ros/jazzy/setup.bash && source /workspaces/ros2_ws/install/setup.bash && ros2 run teleop_twist_keyboard teleop_twist_keyboard --ros-args -r cmd_vel:=/cmd_vel'
```

### 4.2 Wall-follow (autonomous)

```bash
docker compose exec ros2-isaac bash -lc 'source /opt/ros/jazzy/setup.bash && source /workspaces/ros2_ws/install/setup.bash && ros2 launch robot_navigation wall_follow.launch.py scan_topic:=/scan cmd_vel_topic:=/cmd_vel'
```

## 5) Quick checks

```bash
docker compose ps
docker compose exec ros2-isaac bash -lc 'source /opt/ros/jazzy/setup.bash && ros2 topic list | grep -E "^/cmd_vel$|^/scan$|^/odom$"'
```

## 6) Visual SLAM + odometry (requires VPI runtime)

Your current `ros2-isaac` image does not contain `libnvvpi.so.3`, so `isaac_ros_visual_slam`
fails there. Keep your normal flow unchanged and run Visual SLAM in a separate
VPI-enabled container.

```bash
cd ~/isaac_ros_stack
export ROS2_VPI_IMAGE=<YOUR_VPI_ENABLED_ISAAC_ROS_IMAGE>
./scripts/vslam_vpi.sh up
```

Verify VPI library exists in that container:

```bash
./scripts/vslam_vpi.sh check
```

Launch Visual SLAM and check odometry:

```bash
./scripts/vslam_vpi.sh launch
# in another terminal:
./scripts/vslam_vpi.sh odom_once
```
