# Main How-To: Isaac WebRTC + Foxglove + 2D SLAM + Nav2

This is the default path for this workspace.

- Isaac Sim visualization: `isaac-webrtc`
- ROS container: `ros2-isaac`
- Foxglove bridge: `foxglove-bridge`
- Mapping: `slam_toolbox` (2D)
- Navigation: `nav_slam.launch.py`

Run from:

```bash
cd ~/isaac_ros_stack
```

---

## 0) Preflight (once)

```bash
./scripts/check_isaac_ros_official_setup.sh
./scripts/slam_step_check.sh phase0
```

If needed, configure Docker GPU runtime:

```bash
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl daemon-reload
sudo systemctl restart docker
```

---

## 1) Set host IP and start core services (default)

Set your reachable host IP:

```bash
ip -4 -o addr show | awk '$2 !~ /^(lo|docker0|br-)/ {print $2, $4}'
export PUBLIC_IP=<YOUR_REACHABLE_HOST_IP>
export PUBLIC_IP=141.83.113.173
echo "$PUBLIC_IP"
```

Start default stack:

```bash
docker compose --profile webrtc up -d --build isaac-webrtc ros2-isaac foxglove-bridge
```

Optional auto-open Carter warehouse + auto-Play:

```bash
docker compose -f docker-compose.yml -f docker-compose.webrtc.scene.yml up -d --force-recreate --no-deps isaac-webrtc
```

Check Isaac and ROS bridge gate:

```bash
docker compose logs --no-color isaac-webrtc | grep -E "auto_open_play|app ready|Full Streaming App is loaded"
./scripts/slam_step_check.sh phase1
```

Check Foxglove readiness gate:

```bash
./scripts/check_foxglove_ready.sh
```

---

## 2) Ensure `/scan` exists (required for SLAM/Nav2)

If `/scan` is already present, skip this section.

Quick check:

```bash
docker compose exec ros2-isaac bash -lc 'source /opt/ros/${ROS_DISTRO:-jazzy}/setup.bash && ros2 topic list | grep -E "^/scan$|^/front_3d_lidar/lidar_points$"'
```

If only point cloud exists, install converter once:

```bash
docker compose exec ros2-isaac bash -lc 'source /opt/ros/${ROS_DISTRO:-jazzy}/setup.bash && apt-get update && apt-get install -y ros-${ROS_DISTRO:-jazzy}-pointcloud-to-laserscan'
```

Start converter (keep this terminal open):

```bash
docker compose exec ros2-isaac bash -lc 'source /opt/ros/${ROS_DISTRO:-jazzy}/setup.bash && ros2 run pointcloud_to_laserscan pointcloud_to_laserscan_node --ros-args -r cloud_in:=/front_3d_lidar/lidar_points -r scan:=/scan -p target_frame:=base_link -p transform_tolerance:=0.1 -p min_height:=-1.0 -p max_height:=1.0 -p range_min:=0.1 -p range_max:=30.0'
```

Check LiDAR + baseline topics:

```bash
./scripts/slam_step_check.sh phase2
```

---

## 3) Start 2D mapping (`slam_toolbox`)

In a new terminal:

```bash
docker compose exec ros2-isaac bash -lc 'source /opt/ros/${ROS_DISTRO:-jazzy}/setup.bash && source /workspaces/ros2_ws/install/setup.bash && ros2 launch robot_bringup mapping_2d.launch.py use_sim_time:=true scan_topic:=/scan odom_topic:=/chassis/odom'
```

Drive robot in another terminal (manual):

```bash
docker compose exec ros2-isaac bash -lc 'source /opt/ros/${ROS_DISTRO:-jazzy}/setup.bash && source /workspaces/ros2_ws/install/setup.bash && ros2 run teleop_twist_keyboard teleop_twist_keyboard --ros-args -r cmd_vel:=/cmd_vel'
```

Or automatic circle drive: teleip-like 'o'

```bash
docker compose exec ros2-isaac bash -lc 'source /opt/ros/${ROS_DISTRO:-jazzy}/setup.bash && source /workspaces/ros2_ws/install/setup.bash && ros2 launch robot_navigation circle_drive.launch.py cmd_vel_topic:=/cmd_vel linear_speed:=0.2 angular_speed:=-0.5'
```

---

## 4) Foxglove client (default visualization)

From your client machine, connect Foxglove Desktop to:

```text
ws://<HOST_IP>:8765
```

Recommended panels/topics:

- 3D panel, Fixed frame: `map` (fallback `odom`)
- LaserScan: `/scan`
- Map: `/map`
- PointCloud: `/front_3d_lidar/lidar_points`
- Image: `/front_stereo_camera/left/image_raw`

If panel says waiting for events:

- Check that the panel topic exactly matches an existing ROS topic.
- Do not use `/points` unless your system actually publishes `/points`.
- Re-run readiness gate:

```bash
./scripts/check_foxglove_ready.sh
```

---

## 5) Nav2 on top of SLAM map

Start slam-first Nav2 in a new terminal:

```bash
docker compose exec ros2-isaac bash -lc 'source /opt/ros/${ROS_DISTRO:-jazzy}/setup.bash && source /workspaces/ros2_ws/install/setup.bash && ros2 launch robot_navigation nav_slam.launch.py map_file:=/workspaces/ros2_ws/src/robot_navigation/maps/phase1_map.yaml'
```

Run the Nav2 baseline validation gate (TF + map updates + lifecycle + one goal):

```bash
./scripts/slam_step_check.sh phase2b
```

Optional goal overrides for the phase2b goal gate:

```bash
NAV_GOAL_X=0.5 NAV_GOAL_Y=0.0 NAV_GOAL_YAW=0.0 NAV_GOAL_TIMEOUT_SEC=90 ./scripts/slam_step_check.sh phase2b
```

---

## 6) Save map

```bash
bash scripts/save_map.sh my_map
```

Outputs:

- `my_map.pgm`
- `my_map.yaml`

---

## 7) Stop default stack

```bash
docker compose down
```

---

## Optional: Visual SLAM (VPI sidecar, separate from default flow)

Use this only after the default flow above is working.

### VPI runtime gate

```bash
export ROS2_VPI_IMAGE=<YOUR_VPI_ENABLED_ISAAC_ROS_IMAGE>
./scripts/vslam_vpi.sh up
./scripts/vslam_vpi.sh status
./scripts/slam_step_check.sh phase3
```

Exit criteria: `libnvvpi.so.3` exists in `ros2-isaac-vpi`.

## Foxglove: Add PointCloud layer (quick steps)

Open a 3D panel

- Click the + (Add Panel) → choose **3D**. If a panel is already open, click the panel title to reveal the panel menu.

Add a PointCloud layer (click-by-click)

- Open the left panel (panel settings) of the 3D panel if it’s collapsed.
- Expand **Topics** or **Layers**.
- Click the **Add** (plus) button under Layers → choose **PointCloud**.

Layer settings

- **Topic:** the exact topic name (e.g. `/front_3d_lidar/lidar_points` or `/point_cloud`).
- **Color / Mode:** `intensity` (or `rgb` if your messages contain RGB fields).
- **Point size:** increase to `2–4` if points look tiny.
- **Decimation:** increase to reduce bandwidth if too many points are shown.
- **Fixed Frame (3D panel header):** choose `map` if you have TF from `base_scan` → `map`; otherwise set the Fixed Frame to the point cloud's `header.frame_id` (e.g. `base_scan`).

Foxglove tips

- If the cloud is invisible, switch the 3D panel Fixed Frame to the cloud's `header.frame_id` (e.g. `base_scan`) to confirm the raw points appear.
- If the topic is not present in Foxglove, ensure the Isaac scene is playing and the RTX Lidar Helper is attached and configured to publish `point_cloud`.
- Reduce `Publish Full Scan` or increase decimation if bandwidth causes missing updates.

