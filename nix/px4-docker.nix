{ dockerTools }:
dockerTools.pullImage {
  imageName = "px4io/px4-dev";
  imageDigest = "sha256:288dc1d7f5290855e86dbaf8b8f55cd17f46f27e9df2affb2056df6363bc6fb0";
  hash = "sha256-eYi6bjdoMk8GnxLUDrkdWRlz8z2PaGMBv7qtCyy4rog=";
  finalImageName = "px4io/px4-dev";
  finalImageTag = "v1.17.0";
}
