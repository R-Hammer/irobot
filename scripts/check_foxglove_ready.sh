#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose -f "${ROOT_DIR}/docker-compose.yml")
ROS_DISTRO="${ROS_DISTRO:-jazzy}"
FAILED=0

ok() {
  echo "[OK] $1"
}

fail() {
  echo "[FAIL] $1"
  FAILED=1
}

check_cmd() {
  if command -v "$1" >/dev/null 2>&1; then
    ok "command available: $1"
  else
    fail "missing command: $1"
  fi
}

echo "[INFO] Checking Foxglove bridge readiness..."

check_cmd docker
check_cmd ss
check_cmd timeout
check_cmd grep

if ! "${COMPOSE[@]}" config -q >/dev/null 2>&1; then
  fail "docker compose config is invalid"
  echo "[HINT] Run: docker compose config"
  exit 1
fi
ok "docker compose config is valid"

if "${COMPOSE[@]}" ps --status running foxglove-bridge | grep -q foxglove-bridge; then
  ok "service running: foxglove-bridge"
else
  fail "service not running: foxglove-bridge"
  echo "[HINT] Run: docker compose up -d --build foxglove-bridge"
fi

if "${COMPOSE[@]}" ps --status running ros2-isaac | grep -q ros2-isaac; then
  ok "service running: ros2-isaac"
else
  fail "service not running: ros2-isaac"
  echo "[HINT] Run: docker compose up -d --build ros2-isaac"
fi

if "${COMPOSE[@]}" logs --no-color foxglove-bridge 2>/dev/null | grep -q "Server listening on port 8765"; then
  ok "foxglove_bridge reports 'Server listening on port 8765'"
else
  fail "foxglove_bridge log does not show server listening on 8765"
  echo "[HINT] Run: docker compose logs --no-color foxglove-bridge | tail -n 100"
fi

if ss -ltn | grep -qE 'LISTEN.+:8765\b'; then
  ok "host socket is listening on tcp/8765"
else
  fail "host socket not listening on tcp/8765"
fi

run_ros_check() {
  local label="$1"
  local cmd="$2"
  if "${COMPOSE[@]}" exec -T ros2-isaac bash -lc "source /opt/ros/${ROS_DISTRO}/setup.bash && ${cmd}" >/dev/null 2>&1; then
    ok "${label}"
  else
    fail "${label}"
  fi
}

run_ros_check "topic exists: /clock" "ros2 topic list | grep -qx '/clock'"
run_ros_check "topic exists: /scan" "ros2 topic list | grep -qx '/scan'"
run_ros_check "topic exists: /map" "ros2 topic list | grep -qx '/map'"

run_ros_check "topic publishes: /clock" "timeout 10 ros2 topic echo /clock --once"
run_ros_check "topic publishes: /scan" "timeout 10 ros2 topic echo /scan --once"
run_ros_check "topic publishes: /map" "timeout 10 ros2 topic echo /map --once"

echo
if [[ "${FAILED}" -eq 0 ]]; then
  ok "Foxglove is ready: bridge + port + /clock + /scan + /map are all active"
  echo "[NEXT] Connect Foxglove Desktop to: ws://<HOST_IP>:8765"
  exit 0
else
  fail "Foxglove readiness check failed"
  echo "[NEXT] Fix failed checks above, then re-run: ./scripts/check_foxglove_ready.sh"
  exit 1
fi
