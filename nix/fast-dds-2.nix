{
  lib,
  stdenv,
  cmake,
  fetchFromGitHub,
  openssl,
  asio,
  tinyxml-2,
  foonathan-memory,
  fast-cdr,
  pkg-config,
}:

stdenv.mkDerivation {
  pname = "fast-dds-2";
  version = "2.14.6";

  src = fetchFromGitHub {
    owner = "eProsima";
    repo = "Fast-DDS";
    rev = "v2.14.6";
    hash = "sha256-UrL5m5OWreZyjoubH9F1am3MUajwC9AInOwLTLGqs5I=";
  };

  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  buildInputs = [
    asio
  ];

  propagatedBuildInputs = [
    openssl
    tinyxml-2
    foonathan-memory
    fast-cdr
  ];

  cmakeFlags = [
    "-DCMAKE_BUILD_TYPE=Release"
    "-DBUILD_SHARED_LIBS=ON"
    "-DSECURITY=OFF"
    "-DCOMPILE_EXAMPLES=OFF"
    "-DCMAKE_PREFIX_PATH=${foonathan-memory}"
    "-DSQLITE3_SUPPORT=OFF"
  ];

  meta = {
    description = "eProsima Fast DDS 2.x (fastrtps) for use with Micro-XRCE-DDS-Agent v2.x";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
  };
}
