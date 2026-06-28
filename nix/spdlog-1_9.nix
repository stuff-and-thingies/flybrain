{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
}:

stdenv.mkDerivation {
  pname = "spdlog";
  version = "1.9.2";

  src = fetchFromGitHub {
    owner = "gabime";
    repo = "spdlog";
    rev = "v1.9.2";
    sha256 = "sha256-GSUdHtvV/97RyDKy8i+ticnSlQCubGGWHg4Oo+YAr8Y=";
  };

  nativeBuildInputs = [ cmake ];

  cmakeFlags = [
    "-DSPDLOG_BUILD_EXAMPLE=OFF"
    "-DSPDLOG_BUILD_BENCH=OFF"
    "-DSPDLOG_BUILD_TESTS=OFF"
    "-DSPDLOG_INSTALL=ON"
    "-DSPDLOG_FMT_EXTERNAL=OFF"
  ];

  postInstall = ''
    rm -f $out/lib/pkgconfig/spdlog.pc
  '';

  meta = {
    description = "Very fast, header only, C++ logging library (pinned to 1.9.2 for Micro-XRCE-DDS-Agent compatibility)";
    license = lib.licenses.mit;
  };
}
