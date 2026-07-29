
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
dev box cannot build it as-is. There are two ways to get a system closure.

## cross-compiling from x86_64 (no emulation)

`nixos-raspberrypi` sets `nixpkgs.hostPlatform = "aarch64-linux"` and leaves
`nixpkgs.buildPlatform` defaulted to that same value — which is a *native*
aarch64 build. Setting `buildPlatform` explicitly flips nixpkgs into a cross
splice (the machinery behind `pkgsCross.aarch64-multiplatform`), so every
compiler runs natively on x86_64 and emits aarch64 code.

Add a cross variant alongside the existing config in `flake.nix`:

```nix
nixosConfigurations = rec {
  flybrain-rpi5 = nixos-raspberrypi.lib.nixosSystemFull {
    # ... unchanged ...
  };

  # identical config, cross-compiled from x86_64
  flybrain-rpi5-cross = flybrain-rpi5.extendModules {
    modules = [ { nixpkgs.buildPlatform = "x86_64-linux"; } ];
  };
};
```

Then build the system closure:

```
nix build .#nixosConfigurations.flybrain-rpi5-cross.config.system.build.toplevel
```

This needs no `binfmt_misc` registration, no `extra-platforms`, and no aarch64
remote builder. The RPi5 vendor kernel, the 16k-page-size variant, ZFS
userland and the ZFS kernel module all cross-compile.

### what you give up

Cross-built store paths hash differently from the natively-built aarch64 paths
published to `cache.nixos.org` and `nixos-raspberrypi.cachix.org`, so the
prebuilt kernel/firmware and most of the system closure stop substituting and
get compiled locally instead.

Measured on this config (`toplevel`, ZFS + NVMe + RPi5 vendor kernel):

| build mode | built locally | substituted |
| --- | --- | --- |
| native aarch64 (emulated) | 74 derivations | 595 paths / ~970 MiB |
| cross from x86_64 | 420 derivations | 48 paths / ~55 MiB |

So cross compiles roughly 6x more locally, but each of those builds runs at
full native x86_64 speed instead of under qemu. (The cross row was measured
with the cross toolchain already in the store; from a cold store also expect a
few GB of x86_64 build-time dependencies.)

### disk images still need emulation

`config.system.build.toplevel` cross-compiles cleanly, but
`config.system.build.diskoImages` does not get you out of emulation — disko
builds the image inside a VM and pulls in an *aarch64* qemu to partition and
format it, so that step still needs binfmt/qemu or an aarch64 builder.

To deploy without building an image at all, push the cross-built closure
straight to the board:

```
nixos-rebuild switch \
  --flake .#flybrain-rpi5-cross \
  --target-host root@<pi-address>
```

## native aarch64 build under qemu (keeps the binary caches)

The alternative is to build the unmodified `flybrain-rpi5` config as
`aarch64-linux` under emulation, which keeps all the cache hits. This needs
`qemu-user-static` registered with the `F` (fix-binary) flag — `F` is required
so the interpreter stays visible inside the nix build sandbox.

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
