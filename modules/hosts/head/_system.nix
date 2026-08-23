{ ... }:
{
  config.modules = {
    system.flakePath = "/srv/nixos-config";

    device = {
      type = "server";
      cpu = "intel";
      gpu = "intel";
      hasSound = false;
    };

    programs = {
      cli.enable = true;
      gui.enable = false;
    };
  };
}
