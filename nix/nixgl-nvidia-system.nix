{
  lib,
  writeShellScriptBin,
  linkFarm,
  linuxPackages,
  zstd,
  mesa,
  intel-media-driver,
  libvdpau-va-gl,
  libglvnd,
  # The host's installed NVIDIA driver version (see flake.nix, re-detected
  # on every eval), or null if none is loaded.
  nvidiaVersion ? null,
}:
# nixGL's own nixGLNvidia builds a fresh copy of the NVIDIA userspace
# driver from the .run installer (matched to /proc/driver/nvidia/version),
# which is broken against the nixpkgs pin used here (nvidia-x11/generic.nix
# dropped the `kernel` override arg nixGL still passes). We do the same
# thing nixGL does - build a version-matched copy of the driver's
# userspace libraries from the official installer - just without that
# stale argument. The installer is fetched impurely (no pinned hash):
# it's inherently host-specific already (matched to whatever's installed
# right now), so there's nothing to usefully pin, and builtins.fetchurl
# caches by URL, so re-evaluating on every devshell entry only hits the
# network when the driver version actually changes. If nvidiaVersion is
# null, nvidiaUserspace is null and this falls back to symlinking the
# host's already-installed /usr/lib64 driver files directly (still
# correct, just not a reproducible nix derivation).
let
  nvidiaUserspace =
    if nvidiaVersion == null then
      null
    else
      let
        nvidiaDrivers = linuxPackages.nvidia_x11.overrideAttrs (old: {
          pname = "nvidia";
          name = "nvidia-x11-${nvidiaVersion}-flybrain";
          version = nvidiaVersion;
          src = builtins.fetchurl "https://download.nvidia.com/XFree86/Linux-x86_64/${nvidiaVersion}/NVIDIA-Linux-x86_64-${nvidiaVersion}.run";
          useGLVND = true;
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ zstd ];
        });
      in
      nvidiaDrivers.override { libsOnly = true; };

  haveNixNvidia = nvidiaUserspace != null;

  mesa-drivers = [ mesa ];

  # Mirrors nixGLIntel's own Mesa wrapper (needed for VA-API/GBM/DRI/the
  # GLX indirect shim, and because plain nix-built binaries have no
  # default library search path) but lists NVIDIA's real EGL ICD *before*
  # Mesa's in __EGL_VENDOR_LIBRARY_FILENAMES. Order matters here:
  # nixGLIntel always puts its own Mesa entry first (appending whatever
  # was already set), and Mesa's EGL driver fails hard against an NVIDIA
  # PCI id (falling back to swrast) rather than handing off to the next
  # vendor. GLX doesn't have this problem (glvnd queries the running X
  # screen for its vendor there).
  glxindirect = linkFarm "flybrain-mesa-glxindirect" {
    "lib/libGLX_indirect.so.0" = "${mesa}/lib/libGLX_mesa.so.0";
  };

  nvidiaEglJson =
    if haveNixNvidia then
      "${nvidiaUserspace}/share/glvnd/egl_vendor.d/10_nvidia.json"
    else
      "/usr/share/glvnd/egl_vendor.d/10_nvidia.json";

  nvidiaGbmPath = lib.optionalString haveNixNvidia "${nvidiaUserspace}/lib/gbm:";

  # The non-nix-nvidia branch resolves at shell runtime instead (see
  # nvidia_lib_dir below), not at eval time - the two branches are
  # different *kinds* of string, but both slot into the same
  # LD_LIBRARY_PATH position.
  nvidiaLdPath = if haveNixNvidia then "${nvidiaUserspace}/lib" else ''"$nvidia_lib_dir"'';
in
writeShellScriptBin "nixGL" ''
  export GBM_BACKENDS_PATH="${nvidiaGbmPath}/usr/lib64/gbm:${
    lib.makeSearchPathOutput "lib" "lib/gbm" mesa-drivers
  }"
  export LIBGL_DRIVERS_PATH=${lib.makeSearchPathOutput "lib" "lib/dri" mesa-drivers}
  export LIBVA_DRIVERS_PATH=${
    lib.makeSearchPathOutput "out" "lib/dri" (mesa-drivers ++ [ intel-media-driver ])
  }
  export __EGL_VENDOR_LIBRARY_FILENAMES="${nvidiaEglJson}:${mesa}/share/glvnd/egl_vendor.d/50_mesa.json''${__EGL_VENDOR_LIBRARY_FILENAMES:+:$__EGL_VENDOR_LIBRARY_FILENAMES}"
  # Nix-built binaries use nix's own hermetic ld.so.cache (baked into its
  # glibc), which never knows about /usr/lib64/libGLX_nvidia.so.0 /
  # libEGL_nvidia.so.0 - bare-filename dlopen()s (like the ones glvnd does
  # for the vendor libraries named in the EGL/GLX vendor JSON files above)
  # fall through to that cache and never reach the system's real driver,
  # no matter what's in LD_LIBRARY_PATH otherwise. It has to be added
  # explicitly, and LD_LIBRARY_PATH is always searched before a binary's
  # own RPATH - so adding all of /usr/lib64 would shadow every
  # nix-provided library of the same name too (notably libQt5Core.so.5,
  # where the version mismatch segfaults gz sim's GUI). Only ever add
  # directories containing exclusively NVIDIA-named libraries, so nothing
  # else can be shadowed by it. The host-file-symlink fallback can't be
  # done as a Nix derivation - the build sandbox has no access to
  # /usr/lib64 - so it has to happen at runtime.
  ${
    if haveNixNvidia then
      ""
    else
      ''
        nvidia_lib_dir="''${XDG_CACHE_HOME:-$HOME/.cache}/flybrain-nixgl-nvidia-libs"
        mkdir -p "$nvidia_lib_dir"
        for f in /usr/lib64/libnvidia-*.so* /usr/lib64/libGLX_nvidia.so* /usr/lib64/libEGL_nvidia.so* /usr/lib64/libGLESv1_CM_nvidia.so* /usr/lib64/libGLESv2_nvidia.so*; do
          [ -e "$f" ] && ln -sf "$f" "$nvidia_lib_dir/$(basename "$f")"
        done
        true
      ''
  }
  export LD_LIBRARY_PATH=${lib.makeLibraryPath mesa-drivers}:${
    lib.makeSearchPathOutput "lib" "lib/vdpau" [ libvdpau-va-gl ]
  }:${glxindirect}/lib:${lib.makeLibraryPath [ libglvnd ]}:${nvidiaLdPath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
  ${
    if haveNixNvidia then
      ''
        # NVIDIA's userspace driver does its own internal lookups of some
        # companion libraries by hardcoded absolute path (/usr/lib64/...),
        # bypassing the dynamic linker's normal search entirely - no
        # LD_LIBRARY_PATH/RPATH/vendor-JSON override can intercept that.
        # Left alone, this loads the system's copy of the driver *in
        # addition to* the nix-built one above, and mixing the two
        # crashes (segfault inside libnvidia-glcore) as soon as gz sim's
        # GUI creates its real rendering window. Redirect those absolute
        # paths to our nix-built files with a process-scoped mount
        # namespace instead: an unprivileged user+mount namespace
        # bind-mounts over /usr/lib64/lib*nvidia* for this process tree
        # only, leaving the real system (other processes already using
        # the GPU, e.g. the desktop compositor) completely untouched.
        #
        # The outer namespace has to be mapped to root (map-root-user) to
        # be allowed to do that bind mount at all, but that leaves the
        # real command running with getuid()==0 - which some GUI apps
        # (QGroundControl in particular) refuse to start under, since
        # they think they're actually running as root. Once the mounts
        # are done, re-enter a second, unprivileged user namespace mapped
        # back to the real caller's uid/gid before exec'ing the real
        # command. Only --user is unshared again here, not --mount, so
        # the bind mounts made above stay visible.
        real_uid="$(id -u)"
        real_gid="$(id -g)"
        exec unshare --user --mount --map-root-user bash -c '
          for f in "${nvidiaUserspace}"/lib/*; do
            b="/usr/lib64/$(basename "$f")"
            [ -f "$b" ] && [ -f "$f" ] && mount --bind "$f" "$b"
          done
          real_uid="$1"; real_gid="$2"; shift 2
          exec unshare --user --map-user="$real_uid" --map-group="$real_gid" -- "$@"
        ' bash "$real_uid" "$real_gid" "$@"
      ''
    else
      ''exec "$@"''
  }
''
