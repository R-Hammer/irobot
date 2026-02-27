#!/usr/bin/env bash
set -eu

BASE_DIR="${1:-./docker/isaac-sim}"
ISAAC_UID="${ISAAC_UID:-$(id -u)}"
ISAAC_GID="${ISAAC_GID:-$(id -g)}"
DO_CHOWN="${DO_CHOWN:-0}"

echo "Preparing Isaac Sim host directories under: ${BASE_DIR}"

mkdir -p "${BASE_DIR}/cache/main/ov"
mkdir -p "${BASE_DIR}/cache/main/warp"
mkdir -p "${BASE_DIR}/cache/main/ov/Kit/107.3/69cbf6ad"
mkdir -p "${BASE_DIR}/cache/main/ov/ogn_generated"
mkdir -p "${BASE_DIR}/cache/main/ov/texturecache"
mkdir -p "${BASE_DIR}/cache/computecache"
mkdir -p "${BASE_DIR}/logs"
mkdir -p "${BASE_DIR}/config"
mkdir -p "${BASE_DIR}/data"
mkdir -p "${BASE_DIR}/data/documents"
mkdir -p "${BASE_DIR}/data/Kit"
mkdir -p "${BASE_DIR}/pkg"
mkdir -p "${BASE_DIR}/documents/Kit/shared/screenshots"
mkdir -p "./shared"
mkdir -p "./ros2_ws"

if [ "${DO_CHOWN}" = "1" ]; then
  echo "Trying to set ownership to ${ISAAC_UID}:${ISAAC_GID}"
  if chown -R "${ISAAC_UID}:${ISAAC_GID}" "${BASE_DIR}" 2>/dev/null; then
    echo "Ownership updated."
  else
    echo "Could not change ownership. Run this once manually as a privileged user:"
    echo "  chown -R ${ISAAC_UID}:${ISAAC_GID} ${BASE_DIR}"
  fi
else
  echo "Skipping chown."
  echo "If needed, run this once manually as a privileged user:"
  echo "  chown -R ${ISAAC_UID}:${ISAAC_GID} ${BASE_DIR}"
fi

echo "Directory setup complete."

if [ -f "docker-compose.yml" ] || [ -f "compose.yaml" ] || [ -f "compose.yml" ]; then
  echo "Starting containers with Docker Compose..."
#  docker compose up -d
else
  echo "No compose file found in current directory."
fi

