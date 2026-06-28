{
  stdenv,
  fetchFromGitHub,
  micro-cdr,
  cmake,
}:

stdenv.mkDerivation {
  name = "Micro-XRCE-DDS-Client";

  src = fetchFromGitHub {
    owner = "eProsima";
    repo = "Micro-XRCE-DDS-Client";
    rev = "0840e720cfbad44cfd5c115d267f509b49048142";
    hash = "sha256-Dv29K4aDo9/+3do6TRBls0WBgCXsUDYA6BsX1s+GNbA=";
  };

  nativeBuildInputs = [ cmake ];
  propagatedBuildInputs = [ micro-cdr ];
  meta = {
    description = "";
    license = [ ];
  };
}
