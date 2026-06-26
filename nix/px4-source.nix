{ stdenv, fetchFromGitHub }:

stdenv.mkDerivation {
  name = "px4-autopilot-source";
  src = fetchFromGitHub {
    owner = "PX4";
    repo = "PX4-Autopilot";
    rev = "b885ad65a0387d46c3240971269cdfdc7f7f7925";
    hash = "sha256-VU+6RHQRSBGgwR6MM+6mvTEZIclV+V0Eelb+zNP4LJQ=";
  };


  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out

    find ./ -type f -name 'CMakeLists.txt' -delete

    cp -r ./* $out/
    runHook postInstall
  ''; 
}