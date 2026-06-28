
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
