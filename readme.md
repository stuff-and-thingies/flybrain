# how to start SIH sitl

## in terminal 1
1. `nix develop --impure`
2. `start-sih-sitl`

## in terminal 2
1. `nix develop --impure`
2. `qcntrl`

# dev utils

## formatting
### format the code with
```
nix fmt
```

# TODO
- [ ] get ROS2 msgs start being output by px4 in sitl 
- [ ] get aruco tags detected in sitl with camera
- [ ] design initial estimator for localization based on aruco tags + imu