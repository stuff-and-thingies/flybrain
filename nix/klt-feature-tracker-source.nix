{ stdenv
, fetchFromGitHub
}:

stdenv.mkDerivation {
  name = "klt-feature-tracker";

  src = fetchFromGitHub {
    owner = "px4";
    repo = "klt_feature_tracker";
    rev = "1315bb0b493d52c335159488a1c95d09addaf578";
    hash = "sha256-iXasKTeECyTd7SmjJjHyZ7HIXyVGFF93Goo51QpjOd0=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/klt-feature-tracker/
    
    find ./ -type f -name 'CMakeLists.txt' -delete

    cp -r ./* $out/klt-feature-tracker

    runHook postInstall
  '';

  meta = {
    description = "Description";
    license = [];
    # platforms = stdenv.lib.platforms.all;
  };
}