{ pkgs, ... }:
{
  config = {
    modules = {
      device = {
        type = "armlaptop";
        cpu = "snapdragon";
        gpu = "adreno";
        monitors = [ ",preferred,auto,1.2" ];
        hasBluetooth = true;
        hasSound = true;
      };
      programs = {
        cli.enable = true;
        gui.enable = true;
        # Heavy / x86-only desktop apps (Discord, Signal, Steam, the app
        # package groups) stay off until we want them on the laptop.
        desktopApps.enable = false;
        default = {
          terminal = "wezterm";
          fileManager = "thunar";
        };
      };
      style = {
        pointerCursor = {
          package = pkgs.bibata-cursors;
          name = "Bibata-Modern-Ice";
          size = 24;
        };
      };
    };
  };
}
