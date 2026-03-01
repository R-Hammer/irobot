#!/usr/bin/env bash
set -euo pipefail

# Dedicated Visual SLAM helper that uses the VPI-enabled overlay container.
#
# Required:
#   export ROS2_VPI_IMAGE=<VPI-enabled image>
#
# Usage:
#   scripts/vslam_vpi.sh up
#   scripts/vslam_vpi.sh check
#   scripts/vslam_vpi.sh launch
#   scripts/vslam_vpi.sh odom_once
#   scripts/vslam_vpi.sh status
#   scripts/vslam_vpi.sh down

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_ARGS=(-f "${ROOT_DIR}/docker-compose.yml" -f "${ROOT_DIR}/docker-compose.vpi.yml")

if [[ "${1:-}" == "" ]]; then
  echo "Usage: scripts/vslam_vpi.sh {up|check|launch|odom_once|status|down}"
  exit 2
fi

if [[ "${1}" != "down" && -z "${ROS2_VPI_IMAGE:-}" ]]; then
  echo "ROS2_VPI_IMAGE is not set."
  echo "Example:"
  echo "  export ROS2_VPI_IMAGE=<YOUR_VPI_ENABLED_ISAAC_ROS_IMAGE>"
  exit 2
fi

run_in_vpi() {
  docker compose "${COMPOSE_ARGS[@]}" exec ros2-isaac-vpi bash -lc "$1"
}

ROS_SETUP='source /opt/ros/${ROS_DISTRO:-jazzy}/setup.bash && source /workspaces/ros2_ws/install/setup.bash'

case "${1}" in
  up)
    docker compose "${COMPOSE_ARGS[@]}" up -d isaac-webrtc ros2-isaac-vpi
    ;;
  check)
    run_in_vpi 'ldconfig -p | grep libnvvpi.so.3'
    ;;
  launch)
    run_in_vpi "${ROS_SETUP} && ros2 launch robot_bringup mapping.launch.py use_sim_time:=true"
    ;;
  odom_once)
    run_in_vpi "${ROS_SETUP} && ros2 topic echo /visual_slam/tracking/odometry --once"
    ;;
  status)
    docker compose "${COMPOSE_ARGS[@]}" ps ros2-isaac-vpi isaac-webrtc
    ;;
  down)
    docker compose "${COMPOSE_ARGS[@]}" stop ros2-isaac-vpi
    ;;
  *)
    echo "Unknown command: ${1}"
    echo "Usage: scripts/vslam_vpi.sh {up|check|launch|odom_once|status|down}"
    exit 2
    ;;
esac
