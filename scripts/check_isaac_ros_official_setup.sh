#!/usr/bin/env bash
set -euo pipefail

ok() { echo "[OK] $1"; }
warn() { echo "[WARN] $1"; }
fail() { echo "[FAIL] $1"; }

OS_ID="$(. /etc/os-release && echo "${ID}")"
OS_VER="$(. /etc/os-release && echo "${VERSION_ID}")"

if [[ "${OS_ID}" == "ubuntu" && "${OS_VER}" == "24.04" ]]; then
  ok "Host OS is Ubuntu 24.04 (officially supported by latest Isaac ROS docs)."
else
  warn "Host OS is ${OS_ID} ${OS_VER}. Latest Isaac ROS docs target Ubuntu 24.04."
fi

if command -v nvidia-smi >/dev/null 2>&1; then
  if nvidia-smi -L >/dev/null 2>&1; then
    ok "nvidia-smi can access GPU."
  else
    fail "nvidia-smi exists but cannot access GPU."
  fi
else
  fail "nvidia-smi is not installed."
fi

if command -v docker >/dev/null 2>&1; then
  ok "Docker CLI installed: $(docker --version)"
else
  fail "Docker CLI not installed."
fi

if command -v nvidia-ctk >/dev/null 2>&1; then
  ok "nvidia-ctk installed: $(nvidia-ctk --version | head -n 1)"
else
  fail "nvidia-ctk not installed (install NVIDIA Container Toolkit)."
fi

if command -v isaac-ros >/dev/null 2>&1; then
  ok "isaac-ros CLI installed."
else
  warn "isaac-ros CLI not installed yet (sudo apt-get install isaac-ros-cli)."
fi

echo
echo "Next recommended commands (official Docker mode):"
echo "  sudo nvidia-ctk runtime configure --runtime=docker"
echo "  sudo systemctl daemon-reload && sudo systemctl restart docker"
echo "  pip install termcolor --break-system-packages"
echo "  sudo apt-get install -y isaac-ros-cli"
echo "  sudo isaac-ros init docker"
echo "  isaac-ros activate --build-local   # avoids dependency on prebuilt registry image"
