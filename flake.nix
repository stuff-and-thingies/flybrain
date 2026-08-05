{
  nixConfig = {
    extra-substituters = [
      "https://ros.cachix.org"
      "https://nixos-raspberrypi.cachix.org"
      "https://rcmast3r.cachix.org"
      "http://neb-cache.yeet/neb-cache"
    ];
    extra-trusted-public-keys = [
      "ros.cachix.org-1:dSyZxI8geDCJrwgvCOHDoAfOm5sV1wCPjBkKL+38Rvo="
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      "rcmast3r.cachix.org-1:dH22dF877RZ1j7uvAgqnQWNChxdQDeqgBRWpXzoi84c="
      "neb-cache:KTaVU/xOSztooic5m8ZrvvP/5lp3Lg3Y/P7NUyZtKII="
    ];
  };

  inputs = {

    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/develop";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixos-raspberrypi/nixpkgs";
    };

    nix-ros-overlay.url = "github:lopsided98/nix-ros-overlay/develop";
    nix-ros-overlay.inputs.nixpkgs.follows = "nixos-raspberrypi/nixpkgs";

    nixpkgs.follows = "nixos-raspberrypi/nixpkgs";

    nixgl.url = "github:nix-community/nixGL";
    nixgl.inputs.nixpkgs.follows = "nixos-raspberrypi/nixpkgs";

    nix2container-src.url = "github:nlewo/nix2container";
    nix2container-src.flake = false;

  };
  outputs =
    {
      self,
      nix-ros-overlay,
      nixpkgs,
      nixgl,
      nix2container-src,
      nixos-raspberrypi,
      disko,
      ...
    }@inputs:
    let
      pkgs-overlays = [
        nix-ros-overlay.overlays.default

        (import ./nix/fix-overlay.nix { inherit nixgl; })

        (final: prev: {
          px4-gazebo-models = prev.callPackage ./nix/px4-gazebo.nix { };
          nix2container = (prev.callPackage nix2container-src { pkgs = prev; }).nix2container;

          micro-cdr = prev.callPackage ./nix/micro-cdr.nix { };
          micro-xrce-dds-client = prev.callPackage ./nix/micro-xrce-dds-client.nix { };

          fast-cdr = prev.callPackage ./nix/fast-cdr.nix { };
          fast-dds-2 = prev.callPackage ./nix/fast-dds-2.nix { inherit (final) fast-cdr; };
          spdlog-1_9 = prev.callPackage ./nix/spdlog-1_9.nix { };
          micro-xrce-dds-agent = prev.callPackage ./nix/micro-xrce-dds-agent.nix {
            inherit (final) fast-cdr fast-dds-2 spdlog-1_9;
          };

          rosPackages = prev.rosPackages // {
            kilted = prev.rosPackages.kilted.overrideScope (
              rFinal: _rPrev: {
                px4-msgs = rFinal.callPackage ./nix/px4-msgs.nix { };
                px4-ros2-cpp = rFinal.callPackage ./nix/px4-ros2-cpp.nix { };
              }
            );
          };

          px4-sitl = final.nix2container.buildImage {
            name = "px4-sitl";
            fromImage = final.nix2container.pullImage {
              imageName = "px4io/px4-sitl";
              imageDigest = "sha256:b6bfb9e2aece2761ff78831c9bc6f13beb2840c36ba7e010f42b58f97924d2ab";
              sha256 = "sha256-MjDfYuxpjpFfdi5wFoItEJJjZ4PTLKvlGlNrI4iUfXc=";
            };
            config =
              let
                app = prev.writeScript "entry" (builtins.readFile ./sih-entrypoint.sh);
              in
              {
                entrypoint = [ app ];
              };
          };
        })
      ];
    in
    nix-ros-overlay.inputs.flake-utils.lib.eachDefaultSystem (
      system:
      let
        # The host's installed NVIDIA driver version, re-detected on every
        # eval (this flake already requires --impure) so a real,
        # version-matched nix-native copy of the userspace driver can be
        # built from the official installer (see nixgl-nvidia-system.nix).
        # `time = builtins.currentTime` forces the derivation to actually
        # re-run `cp` each eval rather than reusing a stale store path -
        # builtins.readFile can't read /proc files directly (they report
        # size 0, which Nix treats as empty; see nix#3539), so the version
        # has to be copied out to a normal file first. Null (falls back to
        # symlinking the host's /usr/lib64 driver files directly at
        # devshell runtime) if no NVIDIA driver is loaded at all.
        nvidiaVersion =
          let
            versionFile =
              nixpkgs.legacyPackages.${system}.runCommand "flybrain-nvidia-version-file"
                {
                  time = builtins.currentTime;
                  preferLocalBuild = true;
                  allowSubstitutes = false;
                }
                "cp /proc/driver/nvidia/version $out 2>/dev/null || touch $out";
            match = builtins.match ".*Kernel Module.*  ([0-9]+\\.[0-9]+\\.[0-9]+)  .*" (
              builtins.readFile versionFile
            );
          in
          if match != null then builtins.head match else null;

        pkgs = import nixpkgs {
          inherit system;
          overlays = pkgs-overlays;
        };

        # The GUI/GL wrapper is the only thing that differs between GPU
        # vendors; everything else about the sim devshell is shared.
        mkSimShell =
          {
            gzWrapperPkg,
            gzWrapperCmd,
          }:
          pkgs.mkShell {
            name = "sim-env";
            NIXPKGS_ALLOW_UNFREE = 1;
            shellHook = ''
              alias qcntrl='${gzWrapperCmd} QGroundControl'

              export FLYBRAIN_PX4_GZ_IMAGE="px4-sitl-gazebo:${pkgs.px4-sitl-gazebo.imageTag}"
              export FLYBRAIN_PX4_GZ_COPY="${pkgs.px4-sitl-gazebo.copyToDockerDaemon}/bin/copy-to-docker-daemon"
              export FLYBRAIN_PX4_GZ_MODELS="${pkgs.px4-gazebo-models}/models"
              export FLYBRAIN_PX4_GZ_WORLDS="${pkgs.px4-gazebo-models}/worlds"
              export FLYBRAIN_PX4_GZ_SERVER_CONFIG="${pkgs.px4-gazebo-models}/server.config"
              export FLYBRAIN_GZ_BRIDGE_IMAGE="flybrain-ros-gz-harmonic-bridge:dev"
              export FLYBRAIN_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
              export GZ_SIM_RESOURCE_PATH="$FLYBRAIN_PX4_GZ_MODELS:$FLYBRAIN_PX4_GZ_WORLDS''${GZ_SIM_RESOURCE_PATH:+:$GZ_SIM_RESOURCE_PATH}"
              export GZ_SIM_SERVER_CONFIG_PATH="''${GZ_SIM_SERVER_CONFIG_PATH:-$FLYBRAIN_PX4_GZ_SERVER_CONFIG}"

              export FLYBRAIN_GZ_CMD="''${FLYBRAIN_GZ_CMD:-${gzWrapperCmd} gz}"

              ensure-gz-bridge() {
              if ! command -v docker >/dev/null 2>&1; then
                echo "warning: docker not found; skipping Gazebo bridge image build" >&2
                return 0
              fi

              if ! docker info >/dev/null 2>&1; then
                echo "warning: docker daemon unavailable; skipping Gazebo bridge image build" >&2
                return 0
              fi

              docker image inspect "$FLYBRAIN_GZ_BRIDGE_IMAGE" >/dev/null 2>&1 \
                || docker build \
                  -t "$FLYBRAIN_GZ_BRIDGE_IMAGE" \
                  "$FLYBRAIN_ROOT/docker/ros-gz-harmonic-bridge"
            }

            alias start-sih-sitl='docker image inspect px4-sitl:${pkgs.px4-sitl.imageTag} >/dev/null 2>&1 \
              || ${pkgs.px4-sitl.copyToDockerDaemon}/bin/copy-to-docker-daemon \
              && docker run --rm -it \
                --network host \
                px4-sitl:${pkgs.px4-sitl.imageTag}'

            alias build-gz-bridge='docker build \
              -t "$FLYBRAIN_GZ_BRIDGE_IMAGE" \
              "$FLYBRAIN_ROOT/docker/ros-gz-harmonic-bridge"'

            start-sim-gz-nix() {
              if ! command -v docker >/dev/null 2>&1; then
                echo "error: docker not found" >&2
                return 1
              fi

              if ! docker info >/dev/null 2>&1; then
                echo "error: docker daemon unavailable or current user cannot access it" >&2
                return 1
              fi

              ensure-gz-bridge || return

              if ! docker image inspect "$FLYBRAIN_PX4_GZ_IMAGE" >/dev/null 2>&1; then
                "$FLYBRAIN_PX4_GZ_COPY" || return
              fi

              "$FLYBRAIN_ROOT/scripts/start-sim-gz.sh" "$FLYBRAIN_PX4_GZ_IMAGE" "$@"
            }

            start-sim-gz-native() {
              FLYBRAIN_GZ_NATIVE=1 start-sim-gz-nix "$@"
            }

            generate-aruco-world() {
              python "$FLYBRAIN_ROOT/scripts/generate-aruco-world.py" "$@"
            }

            start-sim-gz-aruco-multi-nix() {
              PX4_GZ_WORLD=aruco_multi \
                FLYBRAIN_PX4_GZ_WORLDS="$FLYBRAIN_ROOT/sim/worlds" \
                GZ_SIM_RESOURCE_PATH="$FLYBRAIN_ROOT/sim/models:$GZ_SIM_RESOURCE_PATH" \
                start-sim-gz-nix "$@"
            }

            start-sim-gz-aruco-multi-native() {
              FLYBRAIN_GZ_NATIVE=1 start-sim-gz-aruco-multi-nix "$@"
            }

            ensure-gz-bridge
          '';
          packages = [
            pkgs.colcon
            gzWrapperPkg
            pkgs.px4-gazebo-models
            pkgs.qgroundcontrol
            pkgs.micro-xrce-dds-agent
            (pkgs.python3.withPackages (ps: [ ps.opencv4 ]))
            pkgs.px4-sitl.copyToDockerDaemon
            pkgs.px4-sitl-gazebo.copyToDockerDaemon

            # https://github.com/lopsided98/nix-ros-overlay/issues/288#issuecomment-2679601803
            (pkgs.runCommand "ros-autocompletions" { } ''
              for dir in {bash-completion/completions,zsh/site-functions}; do
                  mkdir -p $out/share/$dir
                  for program in {ros2,colcon,rosidl}; do
                      ${pkgs.python3.pkgs.argcomplete}/bin/register-python-argcomplete $program > $out/share/$dir/_$program
                  done
              done
            '')
            # ... other non-ROS packages
            (
              with pkgs.rosPackages.kilted;
              buildEnv {
                paths = [
                  ros-core
                  ros-gz # gazebo ionic
                  foxglove-bridge

                  # build tools for ROS 2 ament cmake
                  ament-cmake
                  ament-cmake-core
                  ament-lint-auto
                  ament-lint-common

                  # dependencies used by ros2_ws packages
                  eigen3-cmake-module # we'll probably need this regardless
                  rclcpp
                  nav-msgs
                  tf2
                  tf2-ros
                  px4-msgs
                  px4-ros2-cpp
                ];
              }
            )
          ];
          };

      in
      {
        # NVIDIA (proprietary driver already installed on the host).
        devShells.default = mkSimShell {
          gzWrapperPkg = pkgs.nixgl-nvidia-system;
          gzWrapperCmd = "nixGL";
        };

        # AMD/Intel, via nixGL's stock Mesa wrapper - no host-specific
        # patching needed since Mesa ships an open-source amdgpu/iris
        # driver, unlike NVIDIA.
        devShells.amd = mkSimShell {
          gzWrapperPkg = pkgs.nixgl.nixGLIntel;
          gzWrapperCmd = "nixGLIntel";
        };

        formatter = pkgs.nixfmt-tree;
        legacyPackages = pkgs;
      }
    )
    // {
      nixosConfigurations = {
        flybrain-rpi5 = nixos-raspberrypi.lib.nixosSystemFull {
          specialArgs = inputs;

          modules = [
            ({ nixos-raspberrypi, ... }: {
              imports = with nixos-raspberrypi.nixosModules; [
                raspberry-pi-5.base
                # raspberry-pi-5.page-size-16k
              ];
            })
            {
              networking.hostId = "8821e309";
            } # NOTE: for zfs, must be unique
            ({ lib, ... }: {
              nixpkgs.overlays = pkgs-overlays;
              boot.loader.raspberry-pi.bootloader = "kernel";
              system.stateVersion = "26.05";
            })

            # Without this there is no way to log into the box at all,
            # over SSH or otherwise.
            ({ ... }: {
              services.openssh.enable = true;
              users.users.root.openssh.authorizedKeys.keys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBIWROhXthac0SiUb/ZY/f4cRhvkrwaV8W4eXGaDe63K ben@nebs-desktop.lan"
              ];
            })

            # Lets `nix build .#nixosConfigurations.flybrain-rpi5.config.system.build.diskoImages`
            # build a flashable aarch64-linux .raw image on this x86_64-linux host, by running
            # disko's installer VM under qemu/binfmt emulation instead of natively.
            ({ pkgs, ... }: {
              disko.imageBuilder.enableBinfmt = true;
              environment.systemPackages = [ pkgs.rosPackages.kilted.ros-core ];
            })

            disko.nixosModules.disko
            ./nix/nixos/rpi5-configtxt.nix
            ./nix/nixos/disko-disk-config.nix
          ];
        };
      };

    };
}
