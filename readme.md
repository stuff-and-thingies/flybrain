
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

# raspberry pi 5 system (`flybrain-rpi5`)

The `flybrain-rpi5` NixOS config targets `aarch64-linux`, so an `x86_64-linux`
dev box cannot build it as-is. Cross-compiling (`nixpkgs.buildPlatform =
"x86_64-linux"`) is possible but was dropped here — it forces most of the
closure (RPi5 vendor kernel, ZFS, etc.) to rebuild locally from source instead
of substituting from `cache.nixos.org`/`nixos-raspberrypi.cachix.org`, since
cross-built store paths hash differently from the natively-built aarch64 paths
those caches publish. Building `aarch64-linux` under emulation instead keeps
the cache hits, at the cost of the (small) parts of the closure that do need
to build running under qemu instead of natively.

## native aarch64 build under qemu (keeps the binary caches)

Build the unmodified `flybrain-rpi5` config as `aarch64-linux` under
emulation. This needs `qemu-user-static` registered with the `F`
(fix-binary) flag — `F` is required so the interpreter stays visible inside
the nix build sandbox.

on Fedora:
```
sudo dnf install qemu-user-static-aarch64
cat /proc/sys/fs/binfmt_misc/qemu-aarch64   # expect: flags: F
```

on NixOS:
```nix
boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
```

then let nix build for that platform, in `/etc/nix/nix.conf`:
```
extra-platforms = aarch64-linux
```

and build:
```
nix build .#nixosConfigurations.flybrain-rpi5.config.system.build.toplevel
```

## flashing a bootable NVMe image directly

`disko.devices.disk.nvme0` (`nix/nixos/disko-disk-config.nix`) targets
`/dev/nvme0n1` — the whole disk, GPT + FIRMWARE/ESP partitions + a ZFS root
pool. Instead of booting the Pi from an SD card and installing over the
network, you can build a `.raw` image of that same layout on this machine and
`dd` it straight onto the NVMe drive (pull it out of the HAT, e.g. via a
USB-NVMe enclosure, before flashing).

This uses [disko's image-building support](https://github.com/nix-community/disko/blob/master/docs/disko-images.md):
disko boots a throwaway `aarch64-linux` VM (via qemu, under the same
`binfmt`/emulation as the regular build above — see
`disko.imageBuilder.enableBinfmt` in `flake.nix`) to partition, format, and
install into a virtual disk file of a fixed size.

Because the image is virtual, `disko.devices.disk.nvme0.imageSize` (currently
`440G`) has to be set explicitly and fit under your drive's *actual* usable
capacity — a "500GB" drive is usually ~465 GiB usable. Bump it in
`nix/nixos/disko-disk-config.nix` if your drive is bigger, or the build will
fail with the image too small to fit the ZFS pool.

Build the installer script (recommended — runs outside the nix store, faster
to get the final image than the pure-sandbox `diskoImages` variant):

```
nix build .#nixosConfigurations.flybrain-rpi5.config.system.build.diskoImagesScript
sudo ./result --build-memory 4096
```

This drops `nvme0.raw` in the current directory once it finishes (expect the
qemu build + VM run to take a while under emulation — qemu itself isn't
cached for this niche `-host-cpu-only` variant, so it compiles from source
the first time).

Then flash it onto the NVMe drive. **Double-check the device node** — `dd` to
the wrong disk is unrecoverable:

```
lsblk                          # find the NVMe drive, NOT your normal disk
sudo dd if=nvme0.raw of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

Put the drive back in the HAT, boot the Pi5 (PCIe/NVMe boot is already
enabled via `pciex1`/`pciex1_gen` in `nix/nixos/rpi5-configtxt.nix`), and it
should come up with SSH already reachable using the key baked into
`flake.nix` (`services.openssh.enable` + `users.users.root.openssh.authorizedKeys.keys`).

If it doesn't boot from NVMe on its own, check the Pi5's EEPROM boot order
(`rpi-eeprom-config`) — NVMe should already be in the default order on
current firmware, but it can be overridden.

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
