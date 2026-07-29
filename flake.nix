{
  nixConfig = {
    extra-substituters = [
      "https://ros.cachix.org"
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "ros.cachix.org-1:dSyZxI8geDCJrwgvCOHDoAfOm5sV1wCPjBkKL+38Rvo="
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
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

    nixpkgs.follows = "nixos-raspberrypi/nixpkgs"; # IMPORTANT!!!
    nixgl.url = "github:nix-community/nixGL";

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
        nixgl.overlay

        # Work around a CPython bug that only manifests when scripts built by
        # `pkgs.writers.writePython3`/`writePython3Bin` (e.g. nixpkgs'
        # `fetchCargoVendor`/`importCargoLock` helper "replace-workspace-values",
        # used while vendoring zenoh's cargo deps for rmw_zenoh_cpp) are executed
        # under QEMU user-mode emulation, as happens when building this
        # aarch64-linux system on an x86_64-linux host via binfmt.
        #
        # Those writers produce a `python3.withPackages` env whose `bin/pythonX.Y`
        # is executed directly (not via a wrapper that sets PYTHONPATH). Under
        # qemu-user, CPython's own path/prefix self-location gets confused and it
        # falls back to the *unwrapped* base interpreter's site-packages, missing
        # any extra `libraries` (e.g. tomli/tomli-w), which surfaces as
        # `ModuleNotFoundError`. Explicitly setting PYTHONHOME to the env's own
        # store path sidesteps the broken self-location and fixes this for every
        # writePython3(Bin)-produced tool, not just this one.
        (final: prev:
          let
            fixPythonWriter =
              origWriter: name: attrs: content:
              let
                libraries = attrs.libraries or [ ];
                hasLibraries = if prev.lib.isFunction libraries then true else libraries != [ ];
                pythonEnv = prev.python3.withPackages (
                  if prev.lib.isFunction libraries then libraries else (_: libraries)
                );
              in
              origWriter name (
                attrs
                // {
                  makeWrapperArgs =
                    (attrs.makeWrapperArgs or [ ])
                    ++ prev.lib.optionals hasLibraries [
                      "--set"
                      "PYTHONHOME"
                      "${pythonEnv}"
                    ];
                }
              ) content;
          in
          {
            writers = prev.writers // {
              writePython3 = fixPythonWriter prev.writers.writePython3;
              writePython3Bin = fixPythonWriter prev.writers.writePython3Bin;
            };
          }
        )

        # mdbook's own testsuite compares the exact stderr text produced when a
        # preprocessor/renderer subcommand can't be spawned. Under the nix build
        # sandbox that text comes out differently than upstream's fixtures expect
        # (e.g. a generic "renderer failed" message instead of the specific
        # "wasn't found" / NotFound message), so 5 of its tests fail even though
        # nothing is actually broken. mdbook is pulled in transitively (e.g. by
        # nix-manual, wayland's docs) as a from-source build, so just skip its
        # checkPhase rather than patching upstream's test fixtures.
        (final: prev: {
          mdbook = prev.mdbook.overrideAttrs (_old: {
            doCheck = false;
          });
        })

        # trio's test suite assumes a real network stack: it checks concrete
        # SO_PROTOCOL values (`assert 14 in [42, 1]`), binds a real local
        # address, and execs a subprocess via `/dev/fd/0`. None of that holds
        # inside the nix build sandbox, so 4 tests fail there even though
        # trio itself is fine. This is pulled in transitively by anyio and
        # cascades to httpx/django/selenium/breezy/vcs2l and several
        # ros-kilted python tools, so skip its tests rather than patching
        # upstream's tests. This nixpkgs' buildPythonPackage runs pytest in
        # installCheckPhase (gated by doInstallCheck), not the classic
        # checkPhase/doCheck, so both must be disabled. Overridden via
        # pythonPackagesExtensions (not a plain top-level override) so the
        # fix propagates to every python package that depends on trio.
        (final: prev: {
          pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
            (pyFinal: pyPrev: {
              trio = pyPrev.trio.overrideAttrs (_old: {
                doCheck = false;
                doInstallCheck = false;
              });
              # anyio's test suite asserts an exact threading.active_count()
              # after a thread-pool run (`assert 3 == 4`); the sandboxed/
              # emulated build environment schedules background threads
              # differently, so this is another environment-flakiness
              # failure rather than a real bug. Same doInstallCheck gate as
              # trio above.
              anyio = pyPrev.anyio.overrideAttrs (_old: {
                doCheck = false;
                doInstallCheck = false;
              });
              # 1 of django's 18164 tests fails in the sandbox: it expects a
              # logging-formatter subprocess's stderr to contain "Formatters
              # failed to launch", but gets empty stderr, because subprocess
              # spawn/exec behaves differently under the build sandbox (same
              # root cause category as the mdbook subprocess-message
              # mismatch above). Not worth 7 more minutes of test runtime
              # for one environment-specific assertion.
              django = pyPrev.django.overrideAttrs (_old: {
                doCheck = false;
                doInstallCheck = false;
              });
            })
          ];
        })

        # nix's own functional-test suite (meson test, labeled
        # "nix-functional-tests" in the build graph) spins up nested
        # sandboxed builds, unix sockets, and network-timeout-based
        # substituter tests. Under qemu-user aarch64 emulation these barely
        # progress (a single test run took well over an hour with near-zero
        # CPU use, likely stuck on syscalls/timeouts that behave differently
        # under emulation) and would take many hours to complete, if they
        # complete at all. `nix` here is only a build/runtime dependency
        # (nixos-rebuild-ng, ros-core's PATH), not something we're patching,
        # so there's no reason to pay for its test suite here.
        (final: prev: {
          nix = prev.nix.overrideAttrs (_old: {
            doCheck = false;
          });
        })

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
        pkgs = import nixpkgs {
          inherit system;
          overlays = pkgs-overlays;
        };

      in
      {
        devShells.default = pkgs.mkShell {
          name = "sim-env";
          NIXPKGS_ALLOW_UNFREE = 1;
          shellHook = ''
            export GZ_SIM_RESOURCE_PATH=${pkgs.px4-gazebo-models}/models
            export GZ_SIM_SERVER_CONFIG_PATH=${pkgs.px4-gazebo-models}/server.config
            alias start-sim='nixGL gz sim -r ${pkgs.px4-gazebo-models}/worlds/aruco.sdf'
            alias start-headless='start-sim -s'
            alias qcntrl='nixGL QGroundControl'

            alias start-sih-sitl='docker image inspect px4-sitl:${pkgs.px4-sitl.imageTag} >/dev/null 2>&1 \
              || ${pkgs.px4-sitl.copyToDockerDaemon}/bin/copy-to-docker-daemon \
              && docker run --rm -it --network host px4-sitl:${pkgs.px4-sitl.imageTag}'
          '';
          packages = [
            pkgs.colcon
            pkgs.nixgl.auto.nixGLDefault
            pkgs.px4-gazebo-models
            pkgs.qgroundcontrol
            pkgs.micro-xrce-dds-agent
            pkgs.px4-sitl.copyToDockerDaemon

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
              nixpkgs.overlays = pkgs-overlays;
              imports = with nixos-raspberrypi.nixosModules; [
                raspberry-pi-5.base
                # raspberry-pi-5.page-size-16k
              ];
            })
            {
              networking.hostId = "8821e309";
            } # NOTE: for zfs, must be unique
            ({ lib, ... }: {
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
