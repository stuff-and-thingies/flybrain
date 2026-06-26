{stdenv, px4-source, symlinkJoin, cmake, opencv}:
stdenv.mkDerivation {
  name = "px4-gazebo-plugins";
  src = symlinkJoin {
    name = "joined";
    paths = [
      (px4-source)
      ./.
    ];
  };

  nativeBuildInputs = [ cmake ];
  propagatedBuildInputs = [ opencv ];
}