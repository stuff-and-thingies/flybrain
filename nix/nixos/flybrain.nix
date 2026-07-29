{ config, lib }:
{
  options.flybrain.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "enable flybrain service";
  };

  config = lib.mkIf config.flybrain.enable {

  };

}
