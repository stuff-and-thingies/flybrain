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
    rev = "ff7ae284c4b9cb1c39d182e9f1a1343b3817011e";
    hash = "sha256-6G6cmLqmEHfOZy8uFzlpH8IzkIrgJjwuqV3LM6VPOAo=";
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
