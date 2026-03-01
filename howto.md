# Docker Bring-Up Plan (Stepwise, Testable)

## Implement / Do Not Implement (first decision)

Implement now:
- Keep current working Docker flow (`isaac-webrtc` + `ros2-isaac`) unchanged.
- Bring up robot motion + 2D SLAM (`slam_toolbox`) with clear pass/fail checks per phase.
- Keep Visual SLAM isolated in a separate optional VPI container (`ros2-isaac-vpi`).
- Add repeatable validation commands via `scripts/slam_step_check.sh`.

Do not implement now:
- Do not block the whole stack on finding a VPI image first.
- Do not mix Visual SLAM dependencies into the baseline `ros2-isaac` image.
- Do not introduce a distro pivot unless a concrete VPI image requires it.

Run from:

```bash
cd ~/isaac_ros_stack
```

## Official guide path (no NGC account dependency)

This follows the docs you linked:
- Isaac ROS getting started + Docker mode
- NVIDIA Container Toolkit (apt)

Key point:
- For a no-account flow, use local image build with:
  `isaac-ros activate --build-local`
- Do not rely on pulling a prebuilt registry image.

Preflight check:

```bash
./scripts/check_isaac_ros_official_setup.sh
```

Install/configure Docker GPU runtime (official toolkit flow):

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl daemon-reload
sudo systemctl restart docker
```

Install Isaac ROS CLI and initialize Docker mode:

```bash
pip install termcolor --break-system-packages
sudo apt-get update
sudo apt-get install -y isaac-ros-cli
sudo isaac-ros init docker
```

Activate local image build (no prebuilt pull required):

```bash
export ISAAC_ROS_WS=~/isaac_ros_stack/ros2_ws
isaac-ros activate --build-local
```

## Phase 0: Compose sanity

```bash
./scripts/slam_step_check.sh phase0
```

Exit criteria:
- `docker compose config` is valid.

## Phase 1: Start base services

Set reachable host IP:

```bash
ip -4 -o addr show | awk '$2 !~ /^(lo|docker0|br-)/ {print $2, $4}'
export PUBLIC_IP=<YOUR_REACHABLE_HOST_IP>
echo "$PUBLIC_IP"
```

Start services:

```bash
docker compose --profile webrtc up -d --build isaac-webrtc ros2-isaac
./scripts/slam_step_check.sh phase1
```

Optional auto-open Carter warehouse + auto-Play:

```bash
docker compose -f docker-compose.yml -f docker-compose.webrtc.scene.yml up -d --force-recreate --no-deps isaac-webrtc
docker compose logs --no-color isaac-webrtc | grep -E "auto_open_play|app ready|Full Streaming App is loaded"
```

Exit criteria:
- WebRTC client connects to `${PUBLIC_IP}:49100`.
- Isaac log shows `app ready` or `Full Streaming App is loaded`.

## Phase 2: Baseline control + 2D SLAM

Install teleop once:

```bash
docker compose exec ros2-isaac bash -lc 'source /opt/ros/${ROS_DISTRO:-jazzy}/setup.bash && apt-get update && apt-get install -y ros-${ROS_DISTRO:-jazzy}-teleop-twist-keyboard'
```

Check baseline topics:

```bash
./scripts/slam_step_check.sh phase2
```

Manual drive:

```bash
docker compose exec ros2-isaac bash -lc 'source /opt/ros/${ROS_DISTRO:-jazzy}/setup.bash && source /workspaces/ros2_ws/install/setup.bash && ros2 run teleop_twist_keyboard teleop_twist_keyboard --ros-args -r cmd_vel:=/cmd_vel'
```

Simple circular motion (teleop-like `o` / right arc):

```bash
docker compose exec ros2-isaac bash -lc 'source /opt/ros/${ROS_DISTRO:-jazzy}/setup.bash && source /workspaces/ros2_ws/install/setup.bash && ros2 launch robot_navigation circle_drive.launch.py cmd_vel_topic:=/cmd_vel linear_speed:=0.2 angular_speed:=-0.5'
```

For left arc (teleop-like `u`), use `angular_speed:=0.5`.

2D mapping:

```bash
docker compose exec ros2-isaac bash -lc 'source /opt/ros/${ROS_DISTRO:-jazzy}/setup.bash && source /workspaces/ros2_ws/install/setup.bash && ros2 launch robot_bringup mapping_2d.launch.py use_sim_time:=true scan_topic:=/scan'
```

Exit criteria:
- `/scan`, `/cmd_vel`, `/odom`, `/map` are active.
- Robot can be driven and map grows over time.

## Phase 3: Optional Visual SLAM runtime gate (VPI)

Set VPI-enabled image and start sidecar container:

```bash
export ROS2_VPI_IMAGE=<YOUR_VPI_ENABLED_ISAAC_ROS_IMAGE>
./scripts/vslam_vpi.sh up
./scripts/vslam_vpi.sh status
./scripts/slam_step_check.sh phase3
```

Exit criteria:
- `libnvvpi.so.3` exists in `ros2-isaac-vpi`.

## Phase 4: Visual SLAM launch

```bash
./scripts/vslam_vpi.sh launch
# new terminal:
./scripts/vslam_vpi.sh odom_once
./scripts/slam_step_check.sh phase4
```

Exit criteria:
- `/visual_slam/tracking/odometry` publishes.

## Sensor add-on path (easy-first)

- Start with Isaac Sim sensors already in Carter scene (no hardware friction).
- Then add one real sensor only:
  - Realsense first, or
  - ZED first.
- After sensor works standalone (`image`, `camera_info`, `tf`), wire it into Phase 4.

## Stop commands

```bash
./scripts/vslam_vpi.sh down || true
docker compose down
```

## Optional: YOLO sidecar container (`ros2-yolo`)

Build and start the YOLO container:

```bash
docker compose --profile yolo build ros2-yolo
docker compose --profile yolo up -d ros2-yolo
docker compose --profile yolo ps ros2-yolo
```

Quick checks:

```bash
docker compose exec ros2-yolo bash -lc 'source /opt/ros/${ROS_DISTRO:-jazzy}/setup.bash && ros2 topic hz /front_stereo_camera/left/image_raw'
docker compose exec ros2-yolo bash -lc 'python3 -c "import torch; print(torch.cuda.is_available())"'
docker compose exec ros2-yolo bash -lc 'python3 -c "from ultralytics import YOLO; print(\"ultralytics_ok\")"'
```

Build bringup package (contains YOLO ROS2 node):

```bash
docker compose exec ros2-yolo bash -lc 'source /opt/ros/${ROS_DISTRO:-jazzy}/setup.bash && cd /workspaces/ros2_ws && colcon build --symlink-install --packages-select robot_bringup'
```

Launch live detection from robot camera:
fix numpy version
```bash
docker compose exec ros2-yolo bash -lc 'python3 -c "import numpy; print(numpy.__version__)"'
```

```bash
docker compose exec ros2-yolo bash -lc 'source /opt/ros/${ROS_DISTRO:-jazzy}/setup.bash && source /workspaces/ros2_ws/install/setup.bash && ros2 launch robot_bringup yolo_detector.launch.py image_topic:=/front_stereo_camera/left/image_raw device:=cuda:0 conf_threshold:=0.25 max_fps:=10.0'
```

Output topics:

```bash
docker compose exec ros2-yolo bash -lc 'source /opt/ros/${ROS_DISTRO:-jazzy}/setup.bash && ros2 topic list | grep -E "^/yolo/annotated_image$|^/yolo/detections$"'
docker compose exec ros2-yolo bash -lc 'source /opt/ros/${ROS_DISTRO:-jazzy}/setup.bash && ros2 topic echo /yolo/detections --once'
```

Image saving behavior:
- Default: `save_images:=false` so `0` images are saved to disk.
- Enable saving:

```bash
docker compose exec ros2-yolo bash -lc 'source /opt/ros/${ROS_DISTRO:-jazzy}/setup.bash && source /workspaces/ros2_ws/install/setup.bash && ros2 launch robot_bringup yolo_detector.launch.py save_images:=true save_dir:=/shared/yolo_frames save_every_n:=10 max_saved_images:=500'
```

Notes:
- `save_every_n:=10` saves every 10th processed frame.
- `max_saved_images:=500` caps saved files at 500. Use `0` for no cap.

Stop only YOLO sidecar:

```bash
docker compose --profile yolo stop ros2-yolo
```
