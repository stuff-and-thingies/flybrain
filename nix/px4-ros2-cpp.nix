{
  lib,
  buildRosPackage,
  fetchFromGitHub,
  ament-cmake,
  ament-index-cpp,
  eigen,
  eigen3-cmake-module,
  rclcpp,
  px4-msgs,
  python3,
}:

buildRosPackage {
  pname = "ros-${rclcpp.rosDistro}-px4-ros2-cpp";
  version = "0.0.1";

  src = fetchFromGitHub {
    owner = "Auterion";
    repo = "px4-ros2-interface-lib";
    rev = "c3e410f035806e8c56246708432ded09c976434b";
    hash = "sha256-rKZPpm8jhy+gznnkKQ7O+WOEWrlJxQt8+zbuELV786k=";
  };

  sourceRoot = "source/px4_ros2_cpp";

  # CMakeLists.txt branches on $ENV{ROS_DISTRO} (unset in the nix build sandbox),
  # which otherwise leaves a bare STREQUAL with no left-hand side. Every
  # buildRosPackage output carries its distro name in passthru.rosDistro, so
  # derive it from a dependency instead of hardcoding one distro here.
  ROS_DISTRO = rclcpp.rosDistro;

  buildType = "ament_cmake";
  nativeBuildInputs = [
    ament-cmake
    eigen3-cmake-module
    (python3.withPackages (ps: [ ps.empy ]))
  ];
  buildInputs = [
    eigen
    eigen3-cmake-module
  ];
  propagatedBuildInputs = [
    ament-index-cpp
    px4-msgs
    rclcpp
  ];

  meta = {
    description = "Library to interface with PX4 from ROS 2 (C++)";
    homepage = "https://github.com/Auterion/px4-ros2-interface-lib";
    license = with lib.licenses; [ bsd3 ];
  };
}
