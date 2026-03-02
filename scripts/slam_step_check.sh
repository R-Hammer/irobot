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
  scripts/slam_step_check.sh phase2b
  scripts/slam_step_check.sh phase3
  scripts/slam_step_check.sh phase4
  scripts/slam_step_check.sh all_base
  scripts/slam_step_check.sh all_slam_nav2
  scripts/slam_step_check.sh all_vslam

Phase meanings:
  phase0  Compose config sanity
  phase1  Core containers + ROS2 bridge activity (/clock, /tf)
  phase2  LiDAR contract + baseline control topics (/scan,/cmd_vel,/odom)
  phase2b Baseline TF/map + slam-first Nav2 gate (lifecycle + one goal)
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

  docker compose "${BASE_COMPOSE[@]}" exec ros2-isaac bash -lc \
    "source /opt/ros/${ROS_DISTRO}/setup.bash && timeout 12 ros2 topic echo /clock --once >/dev/null" \
    || fail "ROS2 bridge gate failed: no /clock message"

  docker compose "${BASE_COMPOSE[@]}" exec ros2-isaac bash -lc \
    "source /opt/ros/${ROS_DISTRO}/setup.bash && timeout 12 ros2 topic echo /tf --once >/dev/null" \
    || fail "ROS2 bridge gate failed: no /tf message (simulation may not be playing)"

  ok "phase1: isaac-webrtc ready + ROS2 bridge active (/clock,/tf)"
}

check_phase2() {
  docker compose "${BASE_COMPOSE[@]}" exec ros2-isaac bash -lc \
    "source /opt/ros/${ROS_DISTRO}/setup.bash && ros2 topic list | grep -E '^/scan$|^/cmd_vel$|^/odom$'" \
    >/dev/null || fail "missing one or more baseline topics (/scan,/cmd_vel,/odom)"

  docker compose "${BASE_COMPOSE[@]}" exec ros2-isaac bash -lc \
    "source /opt/ros/${ROS_DISTRO}/setup.bash && ros2 topic info /scan | grep -F 'sensor_msgs/msg/LaserScan' >/dev/null" \
    || fail "LiDAR gate failed: /scan is not sensor_msgs/msg/LaserScan"

  docker compose "${BASE_COMPOSE[@]}" exec ros2-isaac bash -lc '
    source /opt/ros/'"${ROS_DISTRO}"'/setup.bash
    frame_id="$(timeout 12 ros2 topic echo /scan --once | awk -F"\x27" "/frame_id:/ {print \$2; exit}")"
    test -n "$frame_id"
  ' || fail "LiDAR gate failed: /scan frame_id is empty"

  docker compose "${BASE_COMPOSE[@]}" exec ros2-isaac bash -lc '
    source /opt/ros/'"${ROS_DISTRO}"'/setup.bash
    rate="$(timeout 12 ros2 topic hz /scan 2>/dev/null | awk "/average rate:/ {print \$3; exit}")"
    test -n "$rate"
    awk -v r="$rate" "BEGIN { exit !(r + 0 >= 1.0) }"
  ' || fail "LiDAR gate failed: /scan average rate < 1 Hz (or not measurable)"

  ok "phase2: native /scan contract passes (LaserScan + frame_id + rate) and baseline topics present"
}

check_phase2b() {
  local nav_goal_x="${NAV_GOAL_X:-0.5}"
  local nav_goal_y="${NAV_GOAL_Y:-0.0}"
  local nav_goal_yaw="${NAV_GOAL_YAW:-0.0}"
  local nav_goal_timeout="${NAV_GOAL_TIMEOUT_SEC:-90}"

  docker compose "${BASE_COMPOSE[@]}" exec ros2-isaac bash -lc '
    source /opt/ros/'"${ROS_DISTRO}"'/setup.bash
    python3 - <<"PY"
import time
import rclpy
from rclpy.node import Node
from rclpy.time import Time
from rclpy.duration import Duration
from tf2_ros import Buffer, TransformListener

rclpy.init()
node = Node("tf_connectivity_gate")
buffer = Buffer()
listener = TransformListener(buffer, node, spin_thread=False)
deadline = time.time() + 15.0
required = [("map", "odom"), ("odom", "base_link")]
ok = {p: False for p in required}

while time.time() < deadline and not all(ok.values()):
    for pair in required:
        if ok[pair]:
            continue
        parent, child = pair
        if buffer.can_transform(parent, child, Time(), timeout=Duration(seconds=0.1)):
            ok[pair] = True
    rclpy.spin_once(node, timeout_sec=0.1)

rclpy.shutdown()
if not all(ok.values()):
    missing = [f"{p}->{c}" for (p, c), state in ok.items() if not state]
    raise SystemExit("missing TF links: " + ", ".join(missing))
PY
  ' || fail "phase2b TF gate failed: expected map->odom and odom->base_link"

  docker compose "${BASE_COMPOSE[@]}" exec ros2-isaac bash -lc '
    source /opt/ros/'"${ROS_DISTRO}"'/setup.bash
    python3 - <<"PY"
import time
import rclpy
from rclpy.node import Node
from nav_msgs.msg import OccupancyGrid

rclpy.init()
node = Node("map_update_gate")
stamps = []

def cb(msg: OccupancyGrid):
    stamp = (int(msg.header.stamp.sec), int(msg.header.stamp.nanosec))
    if not stamps or stamp != stamps[-1]:
        stamps.append(stamp)

sub = node.create_subscription(OccupancyGrid, "/map", cb, 10)
deadline = time.time() + 25.0
while time.time() < deadline and len(stamps) < 2:
    rclpy.spin_once(node, timeout_sec=0.2)

sub.destroy()
rclpy.shutdown()
if len(stamps) < 2:
    raise SystemExit("/map did not show at least two distinct timestamps in 25s")
PY
  ' || fail "phase2b map gate failed: /map is not updating over time"

  docker compose "${BASE_COMPOSE[@]}" exec ros2-isaac bash -lc '
    source /opt/ros/'"${ROS_DISTRO}"'/setup.bash
    for node in /planner_server /controller_server /behavior_server /bt_navigator; do
      ros2 lifecycle get "$node" | grep -qi active || exit 1
    done
  ' || fail "phase2b Nav2 lifecycle gate failed: one or more core nodes are not active"

  docker compose "${BASE_COMPOSE[@]}" exec ros2-isaac bash -lc '
    source /opt/ros/'"${ROS_DISTRO}"'/setup.bash
    source /workspaces/ros2_ws/install/setup.bash
    export NAV_GOAL_X='"${nav_goal_x}"'
    export NAV_GOAL_Y='"${nav_goal_y}"'
    export NAV_GOAL_YAW='"${nav_goal_yaw}"'
    export NAV_GOAL_TIMEOUT_SEC='"${nav_goal_timeout}"'
    python3 - <<"PY"
import math
import os
import time
import rclpy
from rclpy.node import Node
from rclpy.action import ActionClient
from action_msgs.msg import GoalStatus
from nav2_msgs.action import NavigateToPose
from geometry_msgs.msg import Quaternion

goal_x = float(os.environ.get("NAV_GOAL_X", "0.5"))
goal_y = float(os.environ.get("NAV_GOAL_Y", "0.0"))
goal_yaw = float(os.environ.get("NAV_GOAL_YAW", "0.0"))
timeout_sec = float(os.environ.get("NAV_GOAL_TIMEOUT_SEC", "90"))

def yaw_to_quat(yaw: float) -> Quaternion:
    q = Quaternion()
    q.z = math.sin(yaw / 2.0)
    q.w = math.cos(yaw / 2.0)
    return q

rclpy.init()
node = Node("nav_goal_gate")
client = ActionClient(node, NavigateToPose, "/navigate_to_pose")

if not client.wait_for_server(timeout_sec=15.0):
    rclpy.shutdown()
    raise SystemExit("navigate_to_pose action server not available")

goal = NavigateToPose.Goal()
goal.pose.header.frame_id = "map"
goal.pose.header.stamp = node.get_clock().now().to_msg()
goal.pose.pose.position.x = goal_x
goal.pose.pose.position.y = goal_y
goal.pose.pose.orientation = yaw_to_quat(goal_yaw)

send_future = client.send_goal_async(goal)
rclpy.spin_until_future_complete(node, send_future, timeout_sec=15.0)
goal_handle = send_future.result()
if goal_handle is None or not goal_handle.accepted:
    rclpy.shutdown()
    raise SystemExit("navigation goal rejected")

result_future = goal_handle.get_result_async()
rclpy.spin_until_future_complete(node, result_future, timeout_sec=timeout_sec)
result = result_future.result()
rclpy.shutdown()

if result is None:
    raise SystemExit("navigation goal did not finish before timeout")

if result.status != GoalStatus.STATUS_SUCCEEDED:
    raise SystemExit(f"navigation goal finished with status={result.status}, expected SUCCEEDED")
PY
  ' || fail "phase2b goal gate failed: could not execute one NavigateToPose goal"

  ok "phase2b: TF connectivity, map updates, Nav2 lifecycle, and one-goal execution all passed"
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
  phase2b) check_phase2b ;;
  phase3) check_phase3 ;;
  phase4) check_phase4 ;;
  all_base)
    check_phase0
    check_phase1
    check_phase2
    ;;
  all_slam_nav2)
    check_phase0
    check_phase1
    check_phase2
    check_phase2b
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
