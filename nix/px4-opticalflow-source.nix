{ stdenv, fetchFromGitHub }:

stdenv.mkDerivation {
  name = "px4-opticalflow-source";
  src = fetchFromGitHub {
    owner = "PX4";
    repo = "PX4-OpticalFlow";
    rev = "090b90d9f9c155eca5dc65460f0a647bfd413841";
    hash = "sha256-brFfrOSaR0OB7tqvBuJM/AXgqp8UNDIV44amtT9aR9Y=";
  };


  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out
    
    # filter out their cmake for their build system
    find ./ -type f -name 'CMakeLists.txt' -delete
    cp -r ./* $out/
    runHook postInstall
  ''; 
}