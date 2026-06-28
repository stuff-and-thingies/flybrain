{
  stdenv,
  fetchFromGitHub,
  cmake,
  fast-cdr,
  fast-dds-2,
  spdlog-1_9,
}:

stdenv.mkDerivation {
  name = "Micro-XRCE-DDS-Agent";

  src = fetchFromGitHub {
    owner = "eProsima";
    repo = "Micro-XRCE-DDS-Agent";
    rev = "v2.4.3";
    hash = "sha256-t2PZurWc8Kbkm3zFyNwHQea4Yj+zHWFXFqZ0E19km54=";
  };

  nativeBuildInputs = [ cmake ];

  cmakeFlags = [
    "-DUAGENT_P2P_PROFILE=OFF"
    "-DUAGENT_USE_SYSTEM_FASTCDR=ON"
    "-DUAGENT_USE_SYSTEM_FASTDDS=ON"
    "-DUAGENT_USE_SYSTEM_LOGGER=ON"
  ];

  buildInputs = [
    fast-cdr
    fast-dds-2
    spdlog-1_9
  ];

  meta = {
    description = "";
    license = [ ];
    mainProgram = "MicroXRCEAgent";
  };
}
