{
  nixConfig = {
    extra-substituters = [ "https://ros.cachix.org" ];
    extra-trusted-public-keys = [ "ros.cachix.org-1:dSyZxI8geDCJrwgvCOHDoAfOm5sV1wCPjBkKL+38Rvo=" ];
  };

  inputs = {
    nix-ros-overlay.url = "github:lopsided98/nix-ros-overlay/develop";
    nixpkgs.follows = "nix-ros-overlay/nixpkgs"; # IMPORTANT!!!
    nixgl.url = "github:nix-community/nixGL";
  };
  outputs = { self, nix-ros-overlay, nixpkgs, nixgl, ...}:
    nix-ros-overlay.inputs.flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ nix-ros-overlay.overlays.default nixgl.overlay (final: prev: { px4-gazebo-models = prev.callPackage ./nix/px4-gazebo.nix { }; }) ];
        };

      in
      {
        devShells.default = pkgs.mkShell {
          name = "sim-env";
          NIXPKGS_ALLOW_UNFREE=1;
          shellHook = ''
            export GZ_SIM_RESOURCE_PATH=${pkgs.px4-gazebo-models}/models
            export GZ_SIM_SERVER_CONFIG_PATH=${pkgs.px4-gazebo-models}/server.config
            alias start-sim='nixGL gz sim -r ${pkgs.px4-gazebo-models}/worlds/aruco.sdf'
            alias start-headless='start-sim -s'

          '';
          packages = [
            pkgs.colcon
            pkgs.nixgl.auto.nixGLDefault
            pkgs.px4-gazebo-models
            # ... other non-ROS packages
            (with pkgs.rosPackages.kilted; buildEnv {
              paths = [
                ros-core
                ros-gz # gazebo ionic
              ];
            })
          ];
        };

        legacyPackages =
          import nixpkgs {
            inherit system;
            overlays = [
              nix-ros-overlay.overlays.default
              nixgl.overlay
            ];
          };
      });

}