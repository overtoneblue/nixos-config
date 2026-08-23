{ ... }:
{
  config.modules = {
    system.flakePath = null;

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
