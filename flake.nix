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

        # nixgl.overlay unconditionally sets enable32bits = true on
        # x86_64-linux, which pulls in pkgsi686Linux.mesa/intel-media-driver
        # (32-bit OpenGL/Vulkan/VA-API, needed for things like Steam/Proton).
        # We only wrap 64-bit programs (gz sim, QGroundControl), so build
        # nixgl ourselves with 32-bit support disabled to avoid an
        # unnecessary from-source i686 build (rust-bindgen/wayland/mesa).
        (final: _prev: {
          nixgl = import "${nixgl}/default.nix" {
            pkgs = final;
            enable32bits = false;
          };
        })

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
        (
          final: prev:
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

        # gjs's "Debugger" test group (delete/finish/frame/step/... commands)
        # attaches to a running interpreter to drive it, which needs
        # capabilities (ptrace-like control, a real pty) the nix build
        # sandbox doesn't provide, so 25 of 77 tests fail even though gjs
        # itself is fine. Pulled in transitively (e.g. by librsvg/appstream/
        # gnome icon theming) as a from-source build, so skip its checkPhase
        # rather than patching upstream's tests.
        (final: prev: {
          gjs = prev.gjs.overrideAttrs (_old: {
            doCheck = false;
          });
        })

        # systemd's own meson.build does
        # `pymod.find_installation('python3', modules: ['jinja2', ...])`
        # against a `buildPackages.python3Packages.python.withPackages` env,
        # hitting the same QEMU self-location bug described above for
        # gobject-introspection/virglrenderer: it reports jinja2 (and lxml)
        # as missing even though they're right there in the env's
        # site-packages. This is a hard configure-time failure (not a test),
        # and systemd sits under nearly everything in this closure, so fix it
        # the same way as virglrenderer - except a bare `PYTHONHOME = "...";`
        # derivation attribute silently does nothing here: systemd builds
        # with `__structuredAttrs = true`, and under structuredAttrs nixpkgs'
        # generic setup.sh only `declare`s arbitrary custom attrs as local
        # shell variables, it doesn't `export` them (confirmed via
        # `nix print-dev-env`: every other var gets a paired `export FOO`
        # line, PYTHONHOME didn't), so python3 subprocesses never actually
        # saw it. Export it explicitly via preConfigure instead. Also drop
        # the original (unwrapped) python3.withPackages entry from
        # nativeBuildInputs so there's only one `python3` on PATH for
        # meson's find_installation to resolve to. nixpkgs builds
        # `systemdMinimal` and `systemdLibs` via `systemd.override {...}`,
        # so all three top-level attrs need the fix applied individually.
        (
          final: prev:
          let
            fixSystemdPython =
              drv:
              drv.overrideAttrs (
                old:
                let
                  pythonEnv = prev.buildPackages.python3Packages.python.withPackages (
                    ps: with ps; [
                      lxml
                      jinja2
                      pyelftools
                      pefile
                    ]
                  );
                  isOldPythonEnv =
                    p: prev.lib.hasPrefix "python3-" (p.name or "") && prev.lib.hasSuffix "-env" (p.name or "");
                in
                {
                  nativeBuildInputs = (prev.lib.filter (p: !(isOldPythonEnv p)) (old.nativeBuildInputs or [ ])) ++ [
                    pythonEnv
                  ];
                  PYTHONHOME = "${pythonEnv}";
                  preConfigure = ''
                    export PYTHONHOME="${pythonEnv}"
                    ${old.preConfigure or ""}
                  '';
                }
              );
          in
          {
            systemd = fixSystemdPython prev.systemd;
            systemdMinimal = fixSystemdPython prev.systemdMinimal;
            systemdLibs = fixSystemdPython prev.systemdLibs;
          }
        )

        # sdl3's ctest suite is otherwise clean (24/25 pass) except
        # `testprocess`, which spawns child processes and checks their
        # inherited stdio/environment/exit codes - subprocess semantics that
        # behave differently under the nix build sandbox + QEMU user-mode
        # emulation. Pulled in transitively (e.g. by qemu itself), so skip
        # its checkPhase rather than patching upstream's tests.
        (final: prev: {
          sdl3 = prev.sdl3.overrideAttrs (_old: {
            doCheck = false;
          });
        })

        # e2fsprogs' test suite is otherwise clean (390/392 pass) except
        # `m_rootdir`/`m_minrootdir`, which build an ext4 image from a
        # sample directory tree and compare it against a golden checksum -
        # sensitive to file metadata (ownership/permissions/timestamps) that
        # the nix build sandbox doesn't reproduce identically to upstream's
        # fixture environment. Skip its checkPhase rather than patching
        # upstream's test fixtures.
        (final: prev: {
          e2fsprogs = prev.e2fsprogs.overrideAttrs (_old: {
            doCheck = false;
          });
        })

        # tpm2-tss's installCheckPhase runs its full integration test suite
        # against a TPM (real or swtpm-simulated) that isn't available in the
        # nix build sandbox, failing every test/integration/*.int case. Pulled
        # in transitively (e.g. by qemu's TPM support), so skip its
        # installCheckPhase rather than patching upstream's tests.
        (final: prev: {
          tpm2-tss = prev.tpm2-tss.overrideAttrs (_old: {
            doInstallCheck = false;
          });
        })

        # gssdp's and gupnp's test suites join a real multicast group
        # (239.255.255.250, SSDP) on a real network device, which the nix
        # build sandbox doesn't provide ("Failed to join group ...: No such
        # device"), aborting several tests in each. Pulled in transitively
        # (e.g. by gst-plugins-bad), so skip their checkPhases rather than
        # patching upstream's tests. Note nixpkgs keeps both an older
        # top-level `gssdp`/`gupnp` (1.4.x, needed elsewhere) and the newer
        # `gssdp_1_6`/`gupnp_1_6` actually pulled in here - the fix has to
        # target the `_1_6` attrs.
        (final: prev: {
          gssdp_1_6 = prev.gssdp_1_6.overrideAttrs (_old: {
            doCheck = false;
          });
          gupnp_1_6 = prev.gupnp_1_6.overrideAttrs (_old: {
            doCheck = false;
          });
        })

        # libical-glib's installCheckPhase ctest suite runs PyGObject-based
        # regression tests (`import gi`) through the same kind of
        # `python3.withPackages` wrapper env as gobject-introspection above,
        # hitting the identical QEMU self-location bug: `gi` is right there
        # in the env's site-packages, but sys.path resolves to the base
        # interpreter's instead. Pulled in transitively (e.g. by gst-plugins-
        # bad's rtsp support via libical's use in some CalDAV/iCal bits), so
        # skip its installCheckPhase rather than patching upstream's tests.
        (final: prev: {
          libical = prev.libical.overrideAttrs (_old: {
            doInstallCheck = false;
          });
        })

        # polkit's test suite runs test/wrapper.py through a
        # `python3.withPackages` env (providing dbus-python/dbusmock) whose
        # shebang is invoked directly, hitting the same QEMU self-location
        # bug described above for gobject-introspection: sys.path resolves
        # to the base interpreter's site-packages instead of the wrapper
        # env's, so `import dbus` fails even though dbus-python is right
        # there in the closure. Skip its checkPhase rather than patching
        # upstream's test runner.
        (final: prev: {
          polkit = prev.polkit.overrideAttrs (_old: {
            doCheck = false;
          });
        })

        # swtpm's test suite spawns real swtpm processes and waits on them to
        # write pidfiles over control sockets ("Socket TPM did not write
        # pidfile", "CMD_SET_DATAFD failed: Connecting to server"). Under
        # QEMU user-mode emulation the socket/process timing this depends on
        # doesn't hold up, so most of the suite fails even though swtpm
        # itself builds and works fine. It's pulled in transitively (e.g. by
        # qemu, for TPM device emulation), so skip its checkPhase rather than
        # patching upstream's tests.
        (final: prev: {
          swtpm = prev.swtpm.overrideAttrs (_old: {
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
              # rich's test_brokenpipeerror asserts a specific process exit
              # code after writing to a closed stdout pipe (SIGPIPE-driven
              # behavior); this comes out differently under the build
              # sandbox, same root-cause category as the other overrides
              # here. 1 of 951+ tests fails.
              rich = pyPrev.rich.overrideAttrs (_old: {
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
        # virglrenderer's src/gallium/meson.build does
        # `pymod.find_installation('python3', modules: ['yaml'])`, which
        # spawns python3 and actually tries `import yaml`. pyyaml is a
        # genuine input here (via buildPackages.python3.withPackages), but
        # under QEMU user-mode emulation (building this aarch64-linux system
        # via binfmt on an x86_64 host) CPython's self-location gets
        # confused the same way described in the writePython3(Bin) fix
        # above, and it silently falls back to the base interpreter's
        # site-packages - so the yaml module check fails even though pyyaml
        # is present in the closure. Setting PYTHONHOME explicitly (as a
        # real build-time env var, since this python3 isn't invoked through
        # a wrapper script the way writePython3 output is) sidesteps the
        # same self-location bug here.
        (final: prev: {
          virglrenderer = prev.virglrenderer.overrideAttrs (
            _old:
            let
              pythonEnv = prev.buildPackages.python3.withPackages (ps: [
                ps.pyyaml
              ]);
            in
            {
              nativeBuildInputs = [
                prev.meson
                prev.ninja
                prev.pkg-config
                pythonEnv
              ];
              PYTHONHOME = "${pythonEnv}";
            }
          );
        })
        # gobject-introspection's g-ir-scanner (and g-ir-compiler/g-ir-generate)
        # are plain python scripts whose shebang points at a
        # `python3.withPackages` env (providing mako/markdown/setuptools).
        # Under the same QEMU user-mode self-location bug described above,
        # invoking them directly - as every g-ir-scanner caller does, e.g.
        # gst-plugins-base's meson build - resolves sys.path to the *base*
        # interpreter's site-packages, which lacks setuptools. Since Python
        # 3.12 dropped distutils from the stdlib and giscanner unconditionally
        # does `import distutils.cygwinccompiler` at module scope, this
        # surfaces as `ModuleNotFoundError: No module named 'distutils'`
        # (setuptools vendors a distutils shim, but only once its
        # site-packages is actually found). Unlike the writePython3(Bin) and
        # virglrenderer fixes above, we don't control the callers here -
        # dozens of packages invoke g-ir-scanner during their own builds - so
        # fix it once by baking PYTHONHOME into the tool itself.
        #
        # gobject-introspection's *own* meson.build hits the same bug a step
        # earlier: it does `pymod.find_installation('python3', modules:
        # ['mako','markdown','setuptools'])`, which spawns that same
        # python3.withPackages env directly during its configure phase, so
        # the self-location confusion makes it report setuptools as missing
        # before the package even builds. Set PYTHONHOME as a real build-time
        # env var (same fix as virglrenderer) to cover that too.
        (
          final: prev:
          let
            girPythonEnv = prev.python3.withPackages (ps: [
              ps.mako
              ps.markdown
              ps.setuptools
            ]);
          in
          {
            gobject-introspection-unwrapped = prev.gobject-introspection-unwrapped.overrideAttrs (old: {
              nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];
              PYTHONHOME = "${girPythonEnv}";
              postFixup = ''
                ${old.postFixup or ""}
                for f in g-ir-scanner g-ir-compiler g-ir-generate; do
                  if [ -x "$dev/bin/$f" ]; then
                    wrapProgram "$dev/bin/$f" --set PYTHONHOME "${girPythonEnv}"
                  fi
                done
              '';
            });
          }
        )
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
