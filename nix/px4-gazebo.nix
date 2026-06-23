{ stdenv
, fetchFromGitHub
}:

stdenv.mkDerivation rec {
  name = "px4-gazebo-models";
  
  src = fetchFromGitHub {
    owner = "px4";
    repo = "PX4-gazebo-models";
    rev = "bb0b9cf974acf4f1bcb5f5fcf80b88841562dea9";
    hash = "sha256-GPtQtLsPqjUJXnuyijebe9jLTzzpmyQXPnMyzKbKBKk=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -r ./* $out/

    runHook postInstall
  '';

  meta = {
    description = "Description";
    license = [];
    # platforms = stdenv.lib.platforms.all;
  };
}