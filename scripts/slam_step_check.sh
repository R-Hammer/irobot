#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_COMPOSE=(-f "${ROOT_DIR}/docker-compose.yml")
VPI_COMPOSE=(-f "${ROOT_DIR}/docker-compose.yml" -f "${ROOT_DIR}/docker-compose.vpi.yml")
ROS_DISTRO="${ROS_DISTRO:-jazzy}"

usage() {
  cat <<'EOF'
Usage:
  scripts/slam_step_check.sh phase0
  scripts/slam_step_check.sh phase1
  scripts/slam_step_check.sh phase2
  scripts/slam_step_check.sh phase3
  scripts/slam_step_check.sh phase4
  scripts/slam_step_check.sh all_base
  scripts/slam_step_check.sh all_vslam

Phase meanings:
  phase0  Compose config sanity
  phase1  Core containers ready (isaac-webrtc, ros2-isaac)
  phase2  Baseline ROS topics present (/scan, /cmd_vel, /odom)
  phase3  VPI container + libnvvpi.so.3 available
  phase4  Visual SLAM odometry topic active
EOF
}

ok() {
  echo "[OK] $1"
}

fail() {
  echo "[FAIL] $1" >&2
  exit 1
}

check_phase0() {
  docker compose "${BASE_COMPOSE[@]}" config -q || fail "docker compose config failed"
  ok "phase0: compose config valid"
}

check_phase1() {
  docker compose "${BASE_COMPOSE[@]}" ps isaac-webrtc ros2-isaac
  docker compose "${BASE_COMPOSE[@]}" logs --no-color isaac-webrtc | grep -E "app ready|Full Streaming App is loaded" >/dev/null \
    || fail "isaac-webrtc not ready yet"
  ok "phase1: isaac-webrtc and ros2-isaac reachable"
}

check_phase2() {
  docker compose "${BASE_COMPOSE[@]}" exec ros2-isaac bash -lc \
    "source /opt/ros/${ROS_DISTRO}/setup.bash && ros2 topic list | grep -E '^/scan$|^/cmd_vel$|^/odom$'" \
    >/dev/null || fail "missing one or more baseline topics (/scan,/cmd_vel,/odom)"
  ok "phase2: baseline ROS topics present"
}

check_phase3() {
  [[ -n "${ROS2_VPI_IMAGE:-}" ]] || fail "ROS2_VPI_IMAGE is not set"
  docker compose "${VPI_COMPOSE[@]}" ps ros2-isaac-vpi
  docker compose "${VPI_COMPOSE[@]}" exec ros2-isaac-vpi bash -lc "ldconfig -p | grep libnvvpi.so.3" >/dev/null \
    || fail "libnvvpi.so.3 not found in ros2-isaac-vpi"
  ok "phase3: VPI runtime present in ros2-isaac-vpi"
}

check_phase4() {
  docker compose "${VPI_COMPOSE[@]}" exec ros2-isaac-vpi bash -lc \
    "source /opt/ros/${ROS_DISTRO}/setup.bash && ros2 topic echo /visual_slam/tracking/odometry --once" >/dev/null \
    || fail "no /visual_slam/tracking/odometry message received"
  ok "phase4: visual slam odometry active"
}

case "${1:-}" in
  phase0) check_phase0 ;;
  phase1) check_phase1 ;;
  phase2) check_phase2 ;;
  phase3) check_phase3 ;;
  phase4) check_phase4 ;;
  all_base)
    check_phase0
    check_phase1
    check_phase2
    ;;
  all_vslam)
    check_phase3
    check_phase4
    ;;
  *)
    usage
    exit 2
    ;;
esac
