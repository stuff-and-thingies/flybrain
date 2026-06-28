{
  stdenv,
  fetchFromGitHub,
  cmake,
}:

stdenv.mkDerivation {
  name = "Micro-CDR";

  src = fetchFromGitHub {
    owner = "RCMast3r";
    repo = "Micro-CDR";
    rev = "6b5ce5488c43642d2b11fe4f800ad1cacd6afd35";
    hash = "sha256-2mqVr/I0wCcSgM7vJtm3tKwUoCMJRrp3pwRieGoYDoo=";
  };

  nativeBuildInputs = [ cmake ];

  meta = {
    description = "";
    license = [ ];
  };
}
