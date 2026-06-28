
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
- [ ] get ROS2 msgs start being output by px4 in sitl 
    - [ ] micro xrce dds agent running in the devshell
    - [ ] 
- [ ] get aruco tags detected in sitl with camera
    - [ ] requires px4 gazebo sitl running
- [ ] design initial estimator for localization based on aruco tags + imu

# versions: 
- ROS2: lyrical
- v3.0.1  