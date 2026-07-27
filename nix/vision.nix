{
  stdenv,
  buildRosPackage,
  ament-cmake,
  builtin-interfaces,
  opencv,
  vision-src
}:

buildRosPackage {
  pname = "vision";
  version = "0.0.0";

  src = vision-src;

  buildInputs = [
    opencv
  ];

  

}