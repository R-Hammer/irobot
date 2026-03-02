## Optional: YOLO sidecar (`ros2-yolo`)

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
