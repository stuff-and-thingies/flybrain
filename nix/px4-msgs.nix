{
  lib,
  buildRosPackage,
  fetchFromGitHub,
  ament-cmake,
  rosidl-default-generators,
  builtin-interfaces,
  rosidl-default-runtime,
}:

buildRosPackage {
  pname = "ros-kilted-px4-msgs";
  version = "1.17.0";

  src = fetchFromGitHub {
    owner = "PX4";
    repo = "px4_msgs";
    rev = "fbf499b1ab34207821de508f64a1677057bdda3a";
    hash = "sha256-HjrdQqLIqdpNEMZTSJSMcTImSM91qLccRNNqLJqrLIQ=";
  };

  buildType = "ament_cmake";
  nativeBuildInputs = [
    ament-cmake
    rosidl-default-generators
  ];
  buildInputs = [
    ament-cmake
    rosidl-default-generators
  ];
  propagatedBuildInputs = [
    builtin-interfaces
    rosidl-default-runtime
  ];

  meta = {
    description = "ROS 2 message definitions for PX4 uORB messages";
    license = with lib.licenses; [ bsd3 ];
  };
}
