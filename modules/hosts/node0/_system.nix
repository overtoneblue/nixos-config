{ config, pkgs, ... }:
{
  config = {
    modules = {
      device = {
        type = "desktop";
        cpu = "amd";
        gpu = "nvidia";
        monitors = [
          "DP-2,2560x1440@239.97,1080x0,1"
          "DP-1,1920x1080@240,0x0,1,transform,1"
          "HDMI-A-1,3840x2160@60,auto,2"
        ];
        workspaces = [
          "workspace = 1, monitor:DP-2"
          "workspace = 2, monitor:DP-2"
          "workspace = 3, monitor:DP-2"
          "workspace = 4, monitor:DP-2"
          "workspace = 5, monitor:DP-2"
          "workspace = 6, monitor:DP-2"
          "workspace = 7, monitor:DP-1"
          "workspace = 8, monitor:DP-1"
          "workspace = 9, monitor:DP-1"
          "workspace = 10, monitor:HDMI-A-1"
        ];
        hasBluetooth = true;
        hasSound = true;
      };
      programs = {
        cli.enable = true;
        gui.enable = true;
        gpu-screen-recorder.enable = true;
        gaming = {
          enable = true;
          steam.enable = false;
          chess.enable = false;
          minecraft.enable = false;
          gamescope.enable = false;
        };
        default = {
          terminal = "wezterm";
          fileManager = "thunar";
        };
        override = { };
      };
      style = {
        pointerCursor = {
          package = pkgs.bibata-cursors;
          name = "Bibata-Modern-Ice";
          size = 24;
        };
        colors = {
          base00 = "#0b0e14";
          base01 = "#11141b";
          base02 = "#181b22";
          base03 = "#21242c";
          base04 = "#2d3039";
          base05 = "#c7d0dd";
          base06 = "#e2e6ee";
          base07 = "#ffffff";
          base08 = "#b7c2d9";
          base09 = "#c0cae2";
          base0A = "#d0d9ee";
          base0B = "#adc6ff";
          base0C = "#9bb3e7";
          base0D = "#7a8fb8";
          base0E = "#a4b3d4";
          base0F = "#8b94a5";
        };
      };
    };
  };
}
