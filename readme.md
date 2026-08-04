
# how to start Gazebo SITL with ArUco world

## prerequisites

- Docker is installed and running.
- Your user can run Docker without `sudo`.
- The launcher script is tracked as executable, so a fresh clone should not require `chmod`.
- Native Gazebo mode additionally requires host ROS Jazzy at `/opt/ros/jazzy/setup.bash`.

## Nix Gazebo path

Use this on machines where the Nix-provided Gazebo render stack works well.

### in terminal 1
1. enter devshell: `nix develop --impure`
2. `start-sim-gz-nix`

### in terminal 2
1. enter devshell: `nix develop --impure`
2. `qcntrl`

## native Gazebo path

Use this on machines where the Nix Gazebo OpenGL stack does not use the GPU correctly, such as the NVIDIA desktop.

This still uses the Nix-managed PX4 image and PX4 Gazebo models/worlds, but launches Gazebo itself from `/opt/ros/jazzy`.

### in terminal 1
1. enter devshell: `nix develop --impure`
2. `start-sim-gz-native`

The native path is useful on NVIDIA desktops where the Nix Gazebo OpenGL stack does not use the GPU correctly. Check `nvidia-smi` while the sim is running to confirm Gazebo is using the GPU.

### in terminal 2
1. enter devshell: `nix develop --impure`
2. `qcntrl`

## Gazebo sim defaults

- world: `aruco`
- model: `gz_x500_mono_cam_down`
- Gazebo model instance: `x500_mono_cam_down_0`
- camera ROS topics: `/sim/camera/image_raw`, `/sim/camera/camera_info`

## useful Gazebo sim options

- headless Gazebo: `FLYBRAIN_GZ_GUI=0 start-sim-gz-nix`
- lightweight camera/render load: `FLYBRAIN_GZ_LITE=1 FLYBRAIN_GZ_GUI=0 start-sim-gz-nix`
- multi-tag ArUco world with Nix Gazebo: `start-sim-gz-aruco-multi-nix`
- multi-tag ArUco world with native Gazebo: `start-sim-gz-aruco-multi-native`
- regenerate committed multi-tag assets after editing the layout: `generate-aruco-world`

The start commands automatically build the Gazebo bridge image and load the Nix-built PX4 Gazebo Docker image if they are missing.

The multi-tag world assets are committed under `sim/` so the simulator can start from a fresh clone without a generation step. The tag map is `sim/maps/aruco_multi.yaml`; it records each marker ID, size, surface, position, and orientation for later visual localization work.

# how to start SIH sitl

## in terminal 1
1. enter devshell: `nix develop --impure`
2. `start-sih-sitl`

## in terminal 2
1.  enter devshell: `nix develop --impure`
2. `qcntrl`

## ROS2 support:
### in terminal 3
1. enter devshell
2. `MicroXRCEAgent udp4 -p 8888`

### in terminal 4 (foxglove adapter)
1. enter devshell
2. `ros2 launch foxglove_bridge foxglove_bridge_launch.xml`

# dev utils

## formatting
### format the code with
```
nix fmt
```

# TODO
## effort 1: simple imu + gps estimator
- [x] get ROS2 msgs start being output by px4 in sitl 
    - [x] micro xrce dds agent running in the devshell
    - [x] foxglove adapter available
- [ ] estimator core
- [ ] ros2 node wrapper for estimator
- [ ] flybrain launch file using node composition

## effort 2: planner
- [ ] create some gui that can visualize / set up the fake map for the drone to navigate within
- [ ] make a* planner that can plan a path through the environment to give to px4 to follow

## effort 3(?): map creation
- [ ] design / implement SLAM for localization based on aruco tags + imu
    - [ ] map should be the same that was being emulated for the planner to navigate through

# versions: 
- ROS2: kilted
