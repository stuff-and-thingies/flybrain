{
  nixConfig = {
    extra-substituters = [ "https://ros.cachix.org" ];
    extra-trusted-public-keys = [ "ros.cachix.org-1:dSyZxI8geDCJrwgvCOHDoAfOm5sV1wCPjBkKL+38Rvo=" ];
  };

  inputs = {
    nix-ros-overlay.url = "github:lopsided98/nix-ros-overlay/develop";
    nixpkgs.follows = "nix-ros-overlay/nixpkgs"; # IMPORTANT!!!
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
      ...
    }:
    nix-ros-overlay.inputs.flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            nix-ros-overlay.overlays.default
            nixgl.overlay
            (final: prev: {
              px4-gazebo-models = prev.callPackage ./nix/px4-gazebo.nix { };
              nix2container = (prev.callPackage nix2container-src { pkgs = prev; }).nix2container;
            })

            (final: prev: {
              px4-sitl = prev.nix2container.buildImage {
                name = "px4-sitl";
                fromImage = prev.nix2container.pullImage {
                  imageName = "px4io/px4-sitl";
                  imageDigest = "sha256:b6bfb9e2aece2761ff78831c9bc6f13beb2840c36ba7e010f42b58f97924d2ab";
                  sha256 = "sha256-MjDfYuxpjpFfdi5wFoItEJJjZ4PTLKvlGlNrI4iUfXc=";
                };
                config =
                  let
                    app = pkgs.writeScript "entry" (builtins.readFile ./sih-entrypoint.sh);
                  in
                  {
                    entrypoint = [ app ];
                  };
              };
            })
          ];
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
            pkgs.niv
            pkgs.qgroundcontrol
            pkgs.px4-sitl.copyToDockerDaemon
            # ... other non-ROS packages
            (
              with pkgs.rosPackages.kilted;
              buildEnv {
                paths = [
                  ros-core
                  ros-gz # gazebo ionic
                ];
              }
            )
          ];
        };

        legacyPackages = pkgs;
        formatter = pkgs.nixfmt-tree;
      }
    );

}
