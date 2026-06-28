{
  stdenv,
  fetchFromGitHub,
  cmake,
}:

stdenv.mkDerivation {
  name = "Fast-CDR";

  src = fetchFromGitHub {
    owner = "eProsima";
    repo = "Fast-CDR";
    rev = "v2.2.7";
    hash = "sha256-qJLX27VPSDm/df1CKa2ANbPaQ0Dph5bf/Q4Hp/Afz9U=";
  };

  nativeBuildInputs = [ cmake ];

  meta = {
    description = "";
    license = [ ];
  };
}
