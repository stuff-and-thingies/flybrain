{stdenv, px4-opticalflow-source, klt-feature-tracker-source, symlinkJoin, cmake, opencv}:
stdenv.mkDerivation {
  name = "px4-opticalflow";
  src = symlinkJoin {
    name = "joined";
    paths = [
      (px4-opticalflow-source)
      (klt-feature-tracker-source)
      ./.
    ];
  };

  nativeBuildInputs = [ cmake ];
  propagatedBuildInputs = [ opencv ];
}