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
          overlays = [ nix-ros-overlay.overlays.default nixgl.overlay 
          (final: prev: {
            # source drvs
            px4-opticalflow-source = prev.callPackage ./nix/px4-opticalflow-source.nix { };
            klt-feature-tracker-source = prev.callPackage ./nix/klt-feature-tracker-source.nix { };
            px4-source = prev.callPackage ./nix/px4-source.nix { };

            px4-gazebo-models = prev.callPackage ./nix/px4-gazebo.nix { };

            px4-opticalflow = prev.callPackage ./px4/px4-opticalflow { };
            px4-gazebo-plugins = prev.callPackage ./px4/px4-gazebo-plugins { };

          })
          ];
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


            alias link-px4-gazebo-plugins='ln -nfs ${pkgs.px4-source}/src/modules/simulation/gz_plugins ./px4/px4-gazebo-plugins/src'
            alias link-px4-opticalflow='ln -nfs ${pkgs.px4-opticalflow-source}/include ./px4/px4-opticalflow/include && ln -nfs ${pkgs.px4-opticalflow-source}/src ./px4/px4-opticalflow/src && ln -nfs ${pkgs.klt-feature-tracker-source}/klt-feature-tracker ./px4/px4-opticalflow/klt-feature-tracker'

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

        legacyPackages = pkgs;

      });

}