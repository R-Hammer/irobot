#!/usr/bin/env bash
set -euo pipefail

# Save the current SLAM map to a file
# Usage: bash scripts/save_map.sh [output_path]

OUTPUT=${1:-./my_map}

echo "Saving map to ${OUTPUT}.pgm and ${OUTPUT}.yaml..."

docker compose exec ros2-isaac bash -lc "
source /opt/ros/\${ROS_DISTRO:-jazzy}/setup.bash
ros2 run nav2_map_server map_saver_cli -f /tmp/slam_map
"

docker compose cp ros2-isaac:/tmp/slam_map.pgm "${OUTPUT}.pgm"
docker compose cp ros2-isaac:/tmp/slam_map.yaml "${OUTPUT}.yaml"

echo "✓ Map saved!"
echo "  Image: ${OUTPUT}.pgm"
echo "  Metadata: ${OUTPUT}.yaml"
echo ""
echo "View the map image with any image viewer, or load it into Nav2:"
echo "  ros2 launch robot_navigation nav_slam.launch.py map_file:=$(pwd)/${OUTPUT}.yaml"
