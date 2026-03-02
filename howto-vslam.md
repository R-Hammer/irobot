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

### Visual SLAM launch

```bash
./scripts/vslam_vpi.sh launch
# new terminal:
./scripts/vslam_vpi.sh odom_once
./scripts/slam_step_check.sh phase4
```

Exit criteria: `/visual_slam/tracking/odometry` publishes.

### Stop VSLAM sidecar

```bash
./scripts/vslam_vpi.sh down || true
```

---