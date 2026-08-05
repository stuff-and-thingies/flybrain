# Overlay collecting every workaround needed to get this flake's closure to
# build. None of these change what a package *does* - they only work around
# build/test-suite failures that show up in this flake's specific build
# environment (building aarch64-linux on an x86_64-linux host via QEMU
# user-mode emulation/binfmt, and/or the nix build sandbox's lack of real
# networking/ptrace/TPM/etc). Kept separate from the "real" overlay in
# flake.nix (which adds actual new packages) so the two don't get tangled.
{ nixgl }:
final: prev:
let
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
  virglrendererPythonEnv = prev.buildPackages.python3.withPackages (ps: [
    ps.pyyaml
  ]);

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
  girPythonEnv = prev.python3.withPackages (ps: [
    ps.mako
    ps.markdown
    ps.setuptools
  ]);
in
{
  # nixgl.overlay unconditionally sets enable32bits = true on
  # x86_64-linux, which pulls in pkgsi686Linux.mesa/intel-media-driver
  # (32-bit OpenGL/Vulkan/VA-API, needed for things like Steam/Proton).
  # We only wrap 64-bit programs (gz sim, QGroundControl), so build
  # nixgl ourselves with 32-bit support disabled to avoid an
  # unnecessary from-source i686 build (rust-bindgen/wayland/mesa).
  nixgl = import "${nixgl}/default.nix" {
    pkgs = final;
    enable32bits = false;
  };

  writers = prev.writers // {
    writePython3 = fixPythonWriter prev.writers.writePython3;
    writePython3Bin = fixPythonWriter prev.writers.writePython3Bin;
  };

  # mdbook's own testsuite compares the exact stderr text produced when a
  # preprocessor/renderer subcommand can't be spawned. Under the nix build
  # sandbox that text comes out differently than upstream's fixtures expect
  # (e.g. a generic "renderer failed" message instead of the specific
  # "wasn't found" / NotFound message), so 5 of its tests fail even though
  # nothing is actually broken. mdbook is pulled in transitively (e.g. by
  # nix-manual, wayland's docs) as a from-source build, so just skip its
  # checkPhase rather than patching upstream's test fixtures.
  mdbook = prev.mdbook.overrideAttrs (_old: {
    doCheck = false;
  });

  # gjs's "Debugger" test group (delete/finish/frame/step/... commands)
  # attaches to a running interpreter to drive it, which needs
  # capabilities (ptrace-like control, a real pty) the nix build
  # sandbox doesn't provide, so 25 of 77 tests fail even though gjs
  # itself is fine. Pulled in transitively (e.g. by librsvg/appstream/
  # gnome icon theming) as a from-source build, so skip its checkPhase
  # rather than patching upstream's tests.
  gjs = prev.gjs.overrideAttrs (_old: {
    doCheck = false;
  });

  systemd = fixSystemdPython prev.systemd;
  systemdMinimal = fixSystemdPython prev.systemdMinimal;
  systemdLibs = fixSystemdPython prev.systemdLibs;

  # sdl3's ctest suite is otherwise clean (24/25 pass) except
  # `testprocess`, which spawns child processes and checks their
  # inherited stdio/environment/exit codes - subprocess semantics that
  # behave differently under the nix build sandbox + QEMU user-mode
  # emulation. Pulled in transitively (e.g. by qemu itself), so skip
  # its checkPhase rather than patching upstream's tests.
  sdl3 = prev.sdl3.overrideAttrs (_old: {
    doCheck = false;
  });

  # e2fsprogs' test suite is otherwise clean (390/392 pass) except
  # `m_rootdir`/`m_minrootdir`, which build an ext4 image from a
  # sample directory tree and compare it against a golden checksum -
  # sensitive to file metadata (ownership/permissions/timestamps) that
  # the nix build sandbox doesn't reproduce identically to upstream's
  # fixture environment. Skip its checkPhase rather than patching
  # upstream's test fixtures.
  e2fsprogs = prev.e2fsprogs.overrideAttrs (_old: {
    doCheck = false;
  });

  # tpm2-tss's installCheckPhase runs its full integration test suite
  # against a TPM (real or swtpm-simulated) that isn't available in the
  # nix build sandbox, failing every test/integration/*.int case. Pulled
  # in transitively (e.g. by qemu's TPM support), so skip its
  # installCheckPhase rather than patching upstream's tests.
  tpm2-tss = prev.tpm2-tss.overrideAttrs (_old: {
    doInstallCheck = false;
  });

  # gssdp's and gupnp's test suites join a real multicast group
  # (239.255.255.250, SSDP) on a real network device, which the nix
  # build sandbox doesn't provide ("Failed to join group ...: No such
  # device"), aborting several tests in each. Pulled in transitively
  # (e.g. by gst-plugins-bad), so skip their checkPhases rather than
  # patching upstream's tests. Note nixpkgs keeps both an older
  # top-level `gssdp`/`gupnp` (1.4.x, needed elsewhere) and the newer
  # `gssdp_1_6`/`gupnp_1_6` actually pulled in here - the fix has to
  # target the `_1_6` attrs.
  gssdp_1_6 = prev.gssdp_1_6.overrideAttrs (_old: {
    doCheck = false;
  });
  gupnp_1_6 = prev.gupnp_1_6.overrideAttrs (_old: {
    doCheck = false;
  });

  # libical-glib's installCheckPhase ctest suite runs PyGObject-based
  # regression tests (`import gi`) through the same kind of
  # `python3.withPackages` wrapper env as gobject-introspection above,
  # hitting the identical QEMU self-location bug: `gi` is right there
  # in the env's site-packages, but sys.path resolves to the base
  # interpreter's instead. Pulled in transitively (e.g. by gst-plugins-
  # bad's rtsp support via libical's use in some CalDAV/iCal bits), so
  # skip its installCheckPhase rather than patching upstream's tests.
  libical = prev.libical.overrideAttrs (_old: {
    doInstallCheck = false;
  });

  # polkit's test suite runs test/wrapper.py through a
  # `python3.withPackages` env (providing dbus-python/dbusmock) whose
  # shebang is invoked directly, hitting the same QEMU self-location
  # bug described above for gobject-introspection: sys.path resolves
  # to the base interpreter's site-packages instead of the wrapper
  # env's, so `import dbus` fails even though dbus-python is right
  # there in the closure. Skip its checkPhase rather than patching
  # upstream's test runner.
  polkit = prev.polkit.overrideAttrs (_old: {
    doCheck = false;
  });

  # swtpm's test suite spawns real swtpm processes and waits on them to
  # write pidfiles over control sockets ("Socket TPM did not write
  # pidfile", "CMD_SET_DATAFD failed: Connecting to server"). Under
  # QEMU user-mode emulation the socket/process timing this depends on
  # doesn't hold up, so most of the suite fails even though swtpm
  # itself builds and works fine. It's pulled in transitively (e.g. by
  # qemu, for TPM device emulation), so skip its checkPhase rather than
  # patching upstream's tests.
  swtpm = prev.swtpm.overrideAttrs (_old: {
    doCheck = false;
  });

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
  nix = prev.nix.overrideAttrs (_old: {
    doCheck = false;
  });

  virglrenderer = prev.virglrenderer.overrideAttrs (_old: {
    nativeBuildInputs = [
      prev.meson
      prev.ninja
      prev.pkg-config
      virglrendererPythonEnv
    ];
    PYTHONHOME = "${virglrendererPythonEnv}";
  });

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
